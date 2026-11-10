import Foundation
import WebKit
import UIKit

@MainActor
enum HTMLRuntimeVerifier {
    static func verify(html: String, timeout: TimeInterval = 6) async -> [String] {
        guard !html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ["Runtime: generated HTML was empty."]
        }
        let staticWarnings = HTMLAppBridgeLint.warnings(in: html)
        let session = HTMLRuntimeCheckSession(html: html)
        return staticWarnings + (await session.run(timeout: timeout))
    }
}

@MainActor
private final class HTMLRuntimeCheckSession: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    private let html: String
    private var webView: WKWebView?
    private var continuation: CheckedContinuation<[String], Never>?
    private var timeoutTask: Task<Void, Never>?
    private var completed = false
    private var issues: [String] = []
    private var mockAppStorage: [String: String] = [:]
    private var mockDocuments: [String: [String: [String: Any]]] = [:]

    init(html: String) {
        self.html = html
        super.init()
    }

    func run(timeout: TimeInterval) async -> [String] {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            start()

            timeoutTask = Task { [weak self] in
                let nanos = UInt64(max(1, timeout) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanos)
                guard !Task.isCancelled else { return }
                self?.finish(extra: ["Runtime: offscreen WebView verification timed out after \(Int(timeout)) seconds."])
            }
        }
    }

    private func start() {
        let configuration = WKWebViewConfiguration()
        let resources = HTMLAppResourceScheme(root: SourceCache.shared.baseURL(appID: "PREVIEW"))
        configuration.setURLSchemeHandler(resources, forURLScheme: HTMLAppResourceScheme.scheme)
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []

        let controller = configuration.userContentController
        controller.addUserScript(WKUserScript(
            source: Self.diagnosticsScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        ))
        controller.addUserScript(WKUserScript(
            source: PermissionBridgeScript.source(sensorPolicy: "deny"),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        ))
        controller.addUserScript(WKUserScript(
            source: DownloadBridgeScript.source,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        ))
        controller.addUserScript(WKUserScript(
            source: HTMLNativeAPIScript.source,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        ))
        controller.addUserScript(WKUserScript(
            source: HTMLAppRuntimeFoundation.source,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        ))
        controller.addUserScript(WKUserScript(
            source: HTMLLocalNetworkScript.source,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        ))
        controller.addUserScript(WKUserScript(
            source: HTMLAppResponsiveViewport.source,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        ))

        for name in Self.messageHandlerNames {
            controller.add(self, name: name)
        }

        let webView = WKWebView(
            frame: CGRect(x: 0, y: 0, width: 390, height: 844),
            configuration: configuration
        )
        webView.navigationDelegate = self
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.pinchGestureRecognizer?.isEnabled = false
        webView.isHidden = true
        self.webView = webView
        // QA must not wait on external CDNs or send traffic when exercising
        // preview controls. Block remote resources in the disposable test view.
        let rules = #"[{"trigger":{"url-filter":"^https?://"},"action":{"type":"block"}}]"#
        WKContentRuleListStore.default().compileContentRuleList(
            forIdentifier: "HTMLAppOfflineQAV1", encodedContentRuleList: rules
        ) { [weak self, weak webView] list, error in
            Task { @MainActor in
                guard let self, !self.completed, let webView else { return }
                if let list { webView.configuration.userContentController.add(list) }
                if let error {
                    self.issues.append("QA network filter could not initialize: " + error.localizedDescription)
                }
                if HTMLAppDocumentMode.usesPackageRuntime(self.html) {
                    resources.load(self.html, into: webView)
                } else {
                    webView.loadHTMLString(self.html, baseURL: SourceCache.shared.baseURL(appID: "PREVIEW"))
                }
            }
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 80_000_000)
            guard let self, !Task.isCancelled else { return }
            await self.runChecks()
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(extra: ["Runtime: WebView navigation failed: \(error.localizedDescription)"])
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(extra: ["Runtime: WebView failed to load the generated document: \(error.localizedDescription)"])
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "htmlappNative" {
            // Simulate native calls without touching real permissions or disk.
            // Every request receives a deterministic response so generated app
            // tests cannot hang awaiting a non-existent native device.
            guard message.frameInfo.isMainFrame,
                  let body = message.body as? [String: Any],
                  let id = body["id"] as? String,
                  let method = body["method"] as? String else { return }
            let args = body["args"] as? [String: Any] ?? [:]
            let value: Any
            let ok: Bool
            switch method {
            case "capabilities.list":
                ok = true
                value = [
                    "methods": HTMLAppBridgeRegistry.methods,
                    "permissions": HTMLPermission.allCases.map { $0.rawValue },
                    "protocolVersion": HTMLAppBridgeRegistry.protocolVersion,
                    "qaMock": true, "nativeHardwareAvailable": false
                ] as [String: Any]
            case "capabilities.describe":
                ok = true
                var descriptor = HTMLAppBridgeRegistry.describe(args["method"] as? String ?? "") ?? [:]
                descriptor["available"] = false
                descriptor["qaMock"] = true
                value = descriptor
            case "permissions.status":
                ok = true
                value = [
                    "permission": args["permission"] as? String ?? "",
                    "hostPolicy": "deny",
                    "systemAuthorization": "denied",
                    "available": false,
                    "canRequest": false,
                    "settingsRequired": true,
                    "qaMock": true
                ] as [String: Any]
            case "permissions.request":
                replyToMockRequest(id: id, ok: false,
                                   value: ["code": "qa_permission_denied", "message": "Native permissions are unavailable in offline QA."])
                return
            case "ui.alert", "ui.menu", "ui.datePicker":
                ok = true
                value = ["cancelled": true]
            case "network.allowedDomains":
                ok = true
                value = ["domains": []]
            case "network.request":
                replyToMockRequest(id: id, ok: false,
                                   value: ["code": "qa_offline", "message": "No remote API calls are made during offline QA."])
                return
            case "db.put":
                let collection = args["collection"] as? String ?? ""
                let key = args["id"] as? String ?? ""
                if collection.isEmpty || key.isEmpty || (args["document"] as? [String: Any]) == nil {
                    replyToMockRequest(id: id, ok: false,
                                       value: ["code": "invalid_arguments", "message": "Database put requires collection, id and document."])
                    return
                }
                mockDocuments[collection, default: [:]][key] = args["document"] as? [String: Any]
                ok = true
                value = ["ok": true]
            case "db.get":
                let collection = args["collection"] as? String ?? ""
                let key = args["id"] as? String ?? ""
                ok = true
                value = (mockDocuments[collection]?[key] as Any?) ?? NSNull()
            case "db.delete":
                let collection = args["collection"] as? String ?? ""
                let key = args["id"] as? String ?? ""
                mockDocuments[collection]?.removeValue(forKey: key)
                ok = true
                value = ["ok": true]
            case "db.count":
                let collection = args["collection"] as? String ?? ""
                ok = true
                value = ["count": mockDocuments[collection]?.count ?? 0]
            case "db.query":
                let collection = args["collection"] as? String ?? ""
                let cursor = args["cursor"] as? String ?? ""
                let limit = max(1, min(100, args["limit"] as? Int ?? 50))
                let rows = (mockDocuments[collection] ?? [:]).keys.sorted()
                    .filter { $0 > cursor }.prefix(limit).compactMap { key -> [String: Any]? in
                        guard let document = mockDocuments[collection]?[key] else { return nil }
                        return ["id": key, "document": document]
                    }
                ok = true
                value = ["items": rows, "cursor": rows.last?["id"] ?? NSNull() as Any]
            case "db.search":
                let collection = args["collection"] as? String ?? ""
                let text = args["text"] as? String ?? ""
                let limit = max(1, min(50, args["limit"] as? Int ?? 50))
                let rows = (mockDocuments[collection] ?? [:]).keys.sorted()
                    .filter { key in
                        let doc = mockDocuments[collection]?[key] ?? [:]
                        return key.localizedCaseInsensitiveContains(text) ||
                            String(describing: doc).localizedCaseInsensitiveContains(text)
                    }.prefix(limit).compactMap { key -> [String: Any]? in
                        guard let document = mockDocuments[collection]?[key] else { return nil }
                        return ["id": key, "document": document]
                    }
                ok = true
                value = ["items": rows]
            case "appStorage.get":
                ok = true
                let stored: Any = mockAppStorage[args["key"] as? String ?? ""] ?? NSNull()
                value = ["value": stored]
            case "appStorage.set":
                let key = args["key"] as? String ?? ""
                guard !key.isEmpty, let text = args["value"] as? String else {
                    replyToMockRequest(id: id, ok: false, value: ["code": "invalid_arguments", "message": "QA storage set requires key and value."])
                    return
                }
                mockAppStorage[key] = text
                ok = true
                value = ["saved": true]
            case "tabs.configure":
                let items = args["items"] as? [[String: Any]] ?? []
                let selected = args["selected"] as? String ?? items.first?["id"] as? String ?? ""
                ok = !items.isEmpty && items.count <= 7
                value = ["enabled": ok]
                if ok, let tabBytes = try? JSONSerialization.data(withJSONObject: items), let tabJSON = String(data: tabBytes, encoding: .utf8) {
                    webView?.evaluateJavaScript("window.__htmlappQATabs = \(tabJSON);")
                }
                if ok, let bytes = try? JSONSerialization.data(withJSONObject: ["id": selected]),
                   let json = String(data: bytes, encoding: .utf8) {
                    webView?.evaluateJavaScript("window.dispatchEvent(new CustomEvent('htmlapp:native-tab-select',{detail:\(json)}));")
                }
            case "tabs.select":
                ok = true; value = ["selected": args["id"] as? String ?? ""]
                if let bytes = try? JSONSerialization.data(withJSONObject: ["id": args["id"] as? String ?? ""]),
                   let json = String(data: bytes, encoding: .utf8) {
                    webView?.evaluateJavaScript("window.dispatchEvent(new CustomEvent('htmlapp:native-tab-select',{detail:\(json)}));")
                }
            case "appStorage.remove":
                mockAppStorage.removeValue(forKey: args["key"] as? String ?? "")
                ok = true
                value = ["removed": true]
            case "appStorage.all":
                ok = true
                value = ["values": mockAppStorage]
            case "appStorage.clear":
                mockAppStorage.removeAll()
                ok = true
                value = ["cleared": true]
            default:
                ok = false
                value = ["code": "qa_unavailable", "message": "This native action needs actual device capability or permission and is unavailable in offline QA."]
            }
            replyToMockRequest(id: id, ok: ok, value: value)
            return
        }
        guard message.name == "htmlappRuntimeLog" else { return }
        if let text = message.body as? String { appendIssue(text) }
    }

    private func replyToMockRequest(id: String, ok: Bool, value: Any) {
        let payload: [Any] = [id, ok, value]
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else { return }
        webView?.evaluateJavaScript("window.__htmlappNativeResolve && window.__htmlappNativeResolve.apply(null, \(json));")
    }

    private func runChecks() async {
        guard let webView else {
            finish(extra: ["Runtime: WebView was unavailable during verification."])
            return
        }

        // Compile each inline classic script without executing it. A syntax error
        // prevents all handlers in that script from registering.
        let scriptErrors = try? await evaluate(Self.inlineScriptSyntaxProbe, in: webView) as? [String]
        if let scriptErrors { scriptErrors.forEach(appendIssue) }

        // Detect tap blockers even when the JavaScript syntax is valid.
        if let blocked = (try? await evaluate(Self.touchabilityProbe, in: webView)) as? [String] {
            blocked.forEach(appendIssue)
        }

        if let navigation = (try? await evaluate(Self.navigationProbe, in: webView)) as? [String] {
            navigation.forEach(appendIssue)
        }
        if let canvas = (try? await evaluate(Self.canvasProbe, in: webView)) as? [String] {
            canvas.forEach(appendIssue)
        }
        let phone = await snapshot(webView, width: 390, height: 844)
        if let phone {
            if phone.domNonEmpty == false {
                appendIssue("Runtime: document body rendered empty at 390pt width.")
            }
            if phone.horizontalOverflow {
                appendIssue("Runtime: horizontal page overflow at 390pt; " + (phone.overflowOffender ?? "inspect fixed-width content."))
            }
            if let unmarked = phone.unmarkedScroller, !unmarked.isEmpty {
                appendIssue("Runtime: unmarked horizontal scroller at 390pt: " + unmarked + ". Mark intentional component scrolling or fix its layout.")
            }
            if phone.pageZoomEnabled {
                appendIssue("Runtime: page zoom allowed at 390pt; the fixed app viewport policy was not applied.")
            }
        } else {
            appendIssue("Runtime: could not inspect the generated DOM at 390pt width.")
        }

        // A quick cross-device resize catches phone/tablet breakpoint issues
        // without a second WebView launch or additional remote AI calls.
        for (width, height) in [
            (CGFloat(320), CGFloat(700)), (CGFloat(375), CGFloat(812)),
            (CGFloat(430), CGFloat(932)), (CGFloat(844), CGFloat(390)),
            (CGFloat(768), CGFloat(1024)), (CGFloat(1024), CGFloat(768))
        ] {
            if let layout = await snapshot(webView, width: width, height: height) {
                if layout.horizontalOverflow {
                    appendIssue("Runtime: horizontal page overflow at \(Int(width))pt; " + (layout.overflowOffender ?? "inspect fixed-width content."))
                }
                if let unmarked = layout.unmarkedScroller, !unmarked.isEmpty {
                    appendIssue("Runtime: unmarked horizontal scroller at \(Int(width))pt: " + unmarked + ".")
                }
                if layout.pageZoomEnabled {
                    appendIssue("Runtime: page zoom allowed at \(Int(width))pt.")
                }
            }
        }

        _ = await snapshot(webView, width: 390, height: 844)
        if let interactive = (try? await evaluate(Self.interactiveProbe, in: webView)) as? [String] {
            interactive.forEach(appendIssue)
        }

        // Keep this bounded: only safe navigation, not broad destructive UI tests.
        // The dedicated debugging screen can perform more exhaustive checking.
        // Exercise non-destructive navigation in a disposable, nonpersistent runtime.
        // These are smoke tests, not permission to submit forms or mutate user data.
        if let tapped = (try? await evaluate(Self.clickProbeScript, in: webView)) as? [String: Any],
           let count = tapped["tested"] as? Int, count > 0 {
            try? await Task.sleep(nanoseconds: 90_000_000)
            let stillAlive = (try? await evaluate(
                "!!document.body && (document.body.children.length > 0 || (document.body.textContent || '').trim().length > 0)",
                in: webView
            )) as? Bool
            if stillAlive == false {
                appendIssue("Runtime: document became blank after simulated navigation interaction.")
            }
        }

        let recordedValue = try? await evaluate(
            "JSON.stringify((window.__htmlappRuntimeIssues || []).slice(0, 40))",
            in: webView
        )
        if let recorded = recordedValue as? String,
           let data = recorded.data(using: .utf8),
           let values = try? JSONDecoder().decode([String].self, from: data) {
            values.forEach(appendIssue)
        }

        finish(extra: [])
    }

    private static let navigationProbe = #"""
    (() => {
      const issues = [];
      const manifest = document.getElementById('htmlapp-navigation');
      if (window.__htmlappNavigationError) issues.push('Native navigation: ' + window.__htmlappNavigationError);
      if (manifest && !window.__htmlappNavigationConfigured) issues.push('Native navigation: manifest did not configure.');
      const screens = Array.from(document.querySelectorAll('[data-htmlapp-screen]'));
      const tabs = window.__htmlappQATabs || [];
      const bottomNavigation = Array.from(document.querySelectorAll('nav,[role="tablist"],.tabbar,.tab-bar,.bottom-nav')).filter(e => {
        const rect=e.getBoundingClientRect(),style=getComputedStyle(e);
        return style.display!=='none' && rect.height>0 && rect.top>innerHeight-160 &&
          ['fixed','sticky','absolute'].includes(style.position) && e.querySelectorAll('button,a,[role="tab"]').length>=2;
      });
      if(bottomNavigation.length && !tabs.length) issues.push('Native navigation: primary bottom navigation did not configure built-in tabs.');
      if(tabs.length && screens.length) {
        const original=screens.find(e=>!e.hidden)?.getAttribute('data-htmlapp-screen');
        for(const tab of tabs) {
          window.dispatchEvent(new CustomEvent('htmlapp:native-tab-select',{detail:{id:tab.id}}));
          const visible=screens.filter(e=>!e.hidden && getComputedStyle(e).display!=='none');
          if(visible.length!==1 || visible[0].getAttribute('data-htmlapp-screen')!==tab.id)
            issues.push('Native navigation: tab '+tab.id+' did not reveal its matching screen.');
        }
        if(original)window.dispatchEvent(new CustomEvent('htmlapp:native-tab-select',{detail:{id:original}}));
      }
      if (screens.length > 1 && !window.HTMLAppNative?.screens) issues.push('Native navigation: screen router missing.');
      if (manifest && screens.filter(e => !e.hidden).length !== 1) issues.push('Native navigation: exactly one screen must be visible.');
      if (manifest && Array.from(document.querySelectorAll('[data-htmlapp-tab-fallback]')).some(e => getComputedStyle(e).display !== 'none'))
        issues.push('Native navigation: HTML fallback overlaps mounted native tabs.');
      return issues;
    })()
    """#


    // Opt-in only: a solid-color splash screen is legitimate, but an app
    // claiming its canvas should already be drawn must not silently pass.
    private static let canvasProbe = #"""
    (() => {
      const issues = [];
      const canvases = Array.from(document.querySelectorAll('canvas[data-htmlapp-verify-drawing]')).slice(0, 8);
      for (const canvas of canvases) {
        const r = canvas.getBoundingClientRect();
        const style = getComputedStyle(canvas);
        if (r.width < 100 || r.height < 100 || style.display === 'none' ||
            style.visibility === 'hidden' || canvas.closest('[hidden], [inert]')) continue;
        if (!canvas.width || !canvas.height) {
          issues.push('Canvas QA: visible canvas has zero backing resolution.');
          continue;
        }
        // Downsample without reading a potentially enormous 4K backing store.
        // Tainted canvases and WebGL readbacks are left to on-device testing.
        try {
          const thumb = document.createElement('canvas');
          thumb.width = thumb.height = 48;
          const ctx = thumb.getContext('2d', { willReadFrequently: true });
          ctx.drawImage(canvas, 0, 0, 48, 48);
          const pixels = ctx.getImageData(0, 0, 48, 48).data;
          let painted = 0, first = -1, different = 0;
          for (let i = 0; i < pixels.length; i += 4) {
            if (pixels[i + 3] < 5) continue;
            painted++;
            // Quantization ignores insignificant GPU/antialiasing noise.
            const key = ((pixels[i] >> 4) << 8) | ((pixels[i + 1] >> 4) << 4) | (pixels[i + 2] >> 4);
            if (first === -1) first = key;
            else if (key !== first) different++;
          }
          if (!painted || different < 6)
            issues.push('Canvas QA: opt-in canvas appears blank or uniform after startup; verify the initial draw and animation loop on a device.');
        } catch (_) {
          // Origin-tainted canvas or unsupported readback: no false pass/fail.
        }
      }
      return issues;
    })()
    """#

    private static let switchGeometryProbe = #"""
    (() => {
      const issues = [];
      const visible = el => el && el.getClientRects().length && getComputedStyle(el).visibility === 'visible';
      for (const host of [...document.querySelectorAll('htmlapp-switch, [data-htmlapp-switch]')].slice(0, 20)) {
        if (!visible(host)) continue;
        const name = host.id || host.getAttribute('label') || host.getAttribute('aria-label') || 'switch';
        const report = text => issues.push('Switch layout: ' + name + ' ' + text);
        const bundled = host.localName === 'htmlapp-switch';
        const root = bundled ? host.shadowRoot : host;
        const track = root?.querySelector(bundled ? '.track' : '[data-htmlapp-switch-track]');
        const thumb = root?.querySelector(bundled ? '.thumb' : '[data-htmlapp-switch-thumb]');
        const input = bundled ? root?.querySelector('input') : null;
        if (!track || !thumb) { report('is missing its track or thumb.'); continue; }
        function measure(on) {
          const t = track.getBoundingClientRect(), k = thumb.getBoundingClientRect();
          const top = k.top - t.top, bottom = t.bottom - k.bottom;
          const left = k.left - t.left, right = t.right - k.right;
          const suffix = on === null ? '.' : ' when ' + (on ? 'on.' : 'off.');
          if (t.height < 12 || t.height > 36 || t.width < t.height + 8) {
            report('has a ' + Math.round(t.height) + 'px track. Use a fixed, compact track' + suffix);
          }
          if (Math.abs(top - bottom) > 1.5 || Math.min(top, bottom, left, right) < -.5) {
            report('thumb is clipped or vertically off-center (top ' + Math.round(top) + 'px, bottom ' + Math.round(bottom) + 'px)' + suffix);
          }
          if (on !== null) {
            const inset = Math.min(left, right);
            if ((on ? right > left : left > right) || Math.abs(inset - top) > 2) {
              report('thumb is at the wrong endpoint or has uneven edge spacing' + suffix);
            }
          }
        }
        if (input) {
          const saved = input.checked;
          try {
            input.checked = false; measure(false);
            input.checked = true; measure(true);
          } finally { input.checked = saved; }
        } else {
          const value = host.getAttribute('aria-checked');
          measure(value === null ? null : (value === 'true') !== (getComputedStyle(track).direction === 'rtl'));
        }
      }
      return issues;
    })()
    """#

    private static let interactiveProbe = #"""
    (() => {
      const issues = [];
      for (const host of [...document.querySelectorAll('htmlapp-switch')].slice(0, 8)) {
        const copy = host.cloneNode(false);
        copy.removeAttribute('id');
        copy.hidden = true;
        document.body.append(copy);
        let changes = 0;
        copy.addEventListener('click', event => event.stopPropagation());
        copy.addEventListener('change', event => { event.stopPropagation(); changes++; });
        try {
          const input = copy.shadowRoot?.querySelector('input');
          if (!input) continue;
          copy.checked = false;
          copy.disabled = false;
          input.click();
          copy.disabled = true;
          input.click();
          if (!copy.checked || changes !== 1) issues.push('Switch layout: bundled switch failed toggle or disabled-state QA.');
        } finally { copy.remove(); }
      }
      for (const viewer of [...document.querySelectorAll('htmlapp-viewer')].slice(0, 4)) {
        if (!viewer.getClientRects().length || getComputedStyle(viewer).visibility !== 'visible') continue;
        // App-owned assets might not be present in the disposable PREVIEW root.
        if (viewer.hasAttribute('src') && viewer.dataset.htmlappViewer !== 'ready') {
          issues.push('3D asset QA: check the local model in the installed app.');
          continue;
        }
        if (viewer.dataset.htmlappViewer !== 'ready' || !viewer.htmlappInspect) {
          issues.push('3D viewer QA: viewer failed to initialize. Check its module import, shape and fallback.');
          continue;
        }
        const root = viewer.shadowRoot, canvas = root.querySelector('canvas');
        const bounds = canvas.getBoundingClientRect();
        const initial = viewer.htmlappInspect();
        if (!initial.rendered || initial.triangles < 1 || initial.contextLost || !initial.width || !initial.height ||
            Math.abs(initial.aspect - bounds.width / Math.max(1, bounds.height)) > .05) {
          issues.push('3D viewer QA: renderer did not draw or match the visible viewport.');
        }
        const send = (type, clientX) => canvas.dispatchEvent(new PointerEvent(type, {
          pointerId: 200, pointerType: 'touch', button: 0, clientX, clientY: 50
        }));
        root.querySelector('nav button:last-child').click();
        const resetPose = viewer.htmlappInspect().pose.join(',');
        send('pointerdown', 30); send('pointermove', 90); send('pointerup', 90);
        const changed = viewer.htmlappInspect().pose.join(',') !== resetPose;
        root.querySelector('nav button:last-child').click();
        if (!changed || viewer.htmlappInspect().pose.join(',') !== resetPose) {
          issues.push('3D viewer QA: drag or Reset view did not change the camera or object as expected.');
        }
      }
      return issues;
    })()
    """#

    private struct Snapshot {
        let domNonEmpty: Bool
        let horizontalOverflow: Bool
        let overflowOffender: String?
        let unmarkedScroller: String?
        let pageZoomEnabled: Bool
    }

    private func snapshot(_ webView: WKWebView, width: CGFloat, height: CGFloat) async -> Snapshot? {
        webView.frame = CGRect(x: 0, y: 0, width: width, height: height)
        webView.setNeedsLayout()
        webView.layoutIfNeeded()
        try? await Task.sleep(nanoseconds: 25_000_000)
        if let controls = (try? await evaluate(Self.switchGeometryProbe, in: webView)) as? [String] {
            controls.forEach(appendIssue)
        }

        let snapshotValue = try? await evaluate(
            """
            (() => ({
              domNonEmpty: !!document.body && (
                document.body.children.length > 0 ||
                (document.body.textContent || '').trim().length > 0
              ),
              horizontalOverflow: (() => {
                const width = document.documentElement.clientWidth || window.innerWidth;
                const scrollOverflow = Math.max(
                  document.documentElement.scrollWidth, document.body?.scrollWidth || 0
                ) > width + 2;
                const offenders = Array.from(document.body?.querySelectorAll('*') || [])
                  .filter(el => !el.closest('[data-htmlapp-horizontal-scroll="true"]'))
                  .filter(el => {
                    const cs = getComputedStyle(el);
                    if (cs.display === 'none' || cs.visibility === 'hidden' ||
                        Number(cs.opacity) === 0 || cs.position === 'fixed') return false;
                    const rect = el.getBoundingClientRect();
                    return rect.width > 1 && rect.height > 1 &&
                      (rect.right > width + 3 || rect.left < -3);
                  });
                window.__htmlappLayoutOffender = offenders.length
                  ? offenders.slice(0, 3).map(el => {
                      const r = el.getBoundingClientRect();
                      return (el.id ? '#' + el.id : el.tagName.toLowerCase()) +
                        ' [' + Math.round(r.left) + ',' + Math.round(r.right) + ']';
                    }).join(', ')
                  : null;
                return scrollOverflow || offenders.length > 0;
              })(),
              overflowOffender: window.__htmlappLayoutOffender,
              unmarkedScroller: (() => {
                // A local carousel/table is legitimate only with an explicit
                // marker. An unmarked overflow:auto container feels like a
                // broken desktop webpage inside an iOS application.
                const nodes = Array.from(document.body?.querySelectorAll('*') || [])
                  .filter(el => !el.closest('[data-htmlapp-horizontal-scroll="true"]'))
                  .filter(el => {
                    if (['INPUT', 'TEXTAREA'].includes(el.tagName)) return false;
                    const style = getComputedStyle(el);
                    if (style.display === 'none' || style.visibility === 'hidden') return false;
                    if (style.overflowX !== 'auto' && style.overflowX !== 'scroll') return false;
                    const rect = el.getBoundingClientRect();
                    return rect.width > 5 && rect.height > 5 &&
                      el.scrollWidth > el.clientWidth + 3;
                  });
                return nodes.slice(0, 3).map(el =>
                  el.id ? '#' + el.id : el.tagName.toLowerCase()
                ).join(', ');
              })(),
              pageZoomEnabled: (() => {
                const content = document.querySelector('meta[name="viewport"]')?.content || '';
                const directives = content.toLowerCase().split(',').map(item => item.trim());
                return !directives.includes('user-scalable=no') ||
                  !directives.includes('maximum-scale=1') ||
                  (window.visualViewport?.scale || 1) > 1.01;
              })()
            }))()
            """,
            in: webView
        )
        guard let object = snapshotValue as? [String: Any] else { return nil }

        return Snapshot(
            domNonEmpty: object["domNonEmpty"] as? Bool ?? false,
            horizontalOverflow: object["horizontalOverflow"] as? Bool ?? false,
            overflowOffender: object["overflowOffender"] as? String,
            unmarkedScroller: object["unmarkedScroller"] as? String,
            pageZoomEnabled: object["pageZoomEnabled"] as? Bool ?? false
        )
    }

    private func evaluate(_ script: String, in webView: WKWebView) async throws -> Any? {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Any?, Error>) in
            webView.evaluateJavaScript(script) { value, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: value) }
            }
        }
    }

    private func appendIssue(_ raw: String) {
        let clean = raw
            .replacingOccurrences(of: "\n", with: " ")
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        guard !clean.isEmpty, !issues.contains(clean), issues.count < 40 else { return }
        issues.append(clean)
    }

    private func finish(extra: [String]) {
        guard !completed else { return }
        completed = true
        extra.forEach(appendIssue)
        timeoutTask?.cancel()

        if let webView {
            webView.stopLoading()
            let controller = webView.configuration.userContentController
            Self.messageHandlerNames.forEach { controller.removeScriptMessageHandler(forName: $0) }
            webView.navigationDelegate = nil
        }
        webView = nil

        let result = issues
        continuation?.resume(returning: result)
        continuation = nil
    }

    private static let messageHandlerNames = [
        "htmlappRuntimeLog",
        "htmlappLocation",
        "htmlappNotificationPermission",
        "htmlappNotification",
        "htmlappHaptic",
        "htmlappSensorPermission",
        "htmlappDownload",
        "htmlappNative",
        "htmlappNetwork"
    ]

    private static let diagnosticsScript = #"""
    (() => {
      if (window.__htmlappRuntimeDiagnosticsInstalled) return;
      window.__htmlappRuntimeDiagnosticsInstalled = true;
      const issues = [];
      window.__htmlappRuntimeIssues = issues;

      const describe = (value) => {
        try {
          if (value instanceof Error) return value.stack || value.message || String(value);
          if (typeof value === 'string') return value;
          return JSON.stringify(value);
        } catch (_) {
          return String(value);
        }
      };

      const push = (kind, value) => {
        const text = `${kind}: ${describe(value)}`.slice(0, 900);
        if (!issues.includes(text) && issues.length < 40) issues.push(text);
        try { window.webkit?.messageHandlers?.htmlappRuntimeLog?.postMessage(text); } catch (_) {}
      };

      const originalConsoleError = console.error?.bind(console);
      console.error = (...args) => {
        push('console.error', args.map(describe).join(' '));
        if (originalConsoleError) originalConsoleError(...args);
      };

      window.addEventListener('error', (event) => {
        if (event.target && event.target !== window) {
          const target = event.target;
          push('resource error', target.src || target.href || target.tagName || 'unknown resource');
          return;
        }
        push('uncaught error', `${event.message || 'unknown'} ${event.filename || ''}:${event.lineno || 0}:${event.colno || 0}`);
      }, true);

      window.addEventListener('unhandledrejection', (event) => {
        push('unhandled rejection', event.reason || 'unknown promise rejection');
      });

      if (typeof window.fetch === 'function') {
        const nativeFetch = window.fetch.bind(window);
        window.fetch = (...args) => nativeFetch(...args).catch((error) => {
          push('network failure', `${String(args[0] || '')} ${describe(error)}`);
          throw error;
        });
      }

      window.alert = (message) => push('blocking alert invoked', message);
      window.confirm = (message) => { push('blocking confirm invoked', message); return false; };
      window.prompt = (message) => { push('blocking prompt invoked', message); return null; };
    })();
    """#

    private static let touchabilityProbe = #"""
    (() => {
      const issues = [];
      const controls = Array.from(document.querySelectorAll(
        'button, [role="button"], [role="tab"], input, select, textarea, a[href]'
      )).filter(el => {
        const r = el.getBoundingClientRect();
        const css = getComputedStyle(el);
        return r.width >= 18 && r.height >= 18 &&
          css.display !== 'none' && css.visibility !== 'hidden' &&
          !el.disabled && !el.closest('[hidden], [inert]');
      }).slice(0, 35);
      let noPointer = 0, covered = 0;
      for (const el of controls) {
        if (getComputedStyle(el).pointerEvents === 'none') {
          noPointer++;
          continue;
        }
        const r = el.getBoundingClientRect();
        // Do not clamp offscreen elements into the viewport: that probes a
        // different element and produces false overlay/tapability failures.
        if (r.bottom <= 0 || r.top >= innerHeight || r.right <= 0 || r.left >= innerWidth) continue;
        const cx = Math.max(1, Math.min(innerWidth - 1, r.left + r.width / 2));
        const cy = Math.max(1, Math.min(innerHeight - 1, r.top + r.height / 2));
        const hit = document.elementFromPoint(cx, cy);
        if (hit && hit !== el && !el.contains(hit) && !hit.contains(el)) covered++;
      }
      if (noPointer >= Math.max(2, Math.ceil(controls.length / 2))) {
        issues.push('Runtime tapability: most visible controls have pointer-events disabled (' +
          noPointer + '/' + controls.length + ').');
      }
      if (covered >= Math.max(3, Math.ceil(controls.length * 0.6))) {
        issues.push('Runtime tapability: ' + covered + ' visible controls are covered by another element. Inspect overlays/z-index.');
      }
      return issues;
    })()
    """#

    private static let inlineScriptSyntaxProbe = #"""
    (() => {
      const found = [];
      for (const [i, el] of Array.from(document.scripts).entries()) {
        if (el.src || el.type === 'module' ||
            (el.type && !/^(text\/javascript|application\/javascript)$/i.test(el.type))) continue;
        const source = el.textContent || '';
        if (!source.trim()) continue;
        try {
          // Function constructor parses only; does not run app code.
          new Function(source);
        } catch (error) {
          found.push('JavaScript syntax in inline script ' + (i + 1) + ': ' +
            String(error?.message || error).slice(0, 250) +
            '. Fix this before release; unparsed scripts leave buttons unresponsive.');
        }
      }
      const buttons = document.querySelectorAll('button,[role="button"],[role="tab"]').length;
      if (found.length && buttons) {
        found.push('JavaScript did not compile; ' + buttons + ' controls may be unresponsive.');
      }
      return found;
    })()
    """#

    private static let clickProbeScript = #"""
    (() => {
      // Only try small safe navigation/toggle affordances. Never press save,
      // delete, purchase, submit, permission or external actions during QA.
      const safe = /\b(tab|menu|open|close|view|show|next|back|settings|details|more|filter)\b/i;
      const forbidden = /\b(delete|remove|reset|clear|pay|buy|purchase|send|share|upload|download|save|submit|connect|record|start|stop|log ?out|sign ?out)\b/i;
      const controls = Array.from(document.querySelectorAll(
        'button:not([type="submit"]),[role="tab"],[role="button"],input[type="checkbox"]'
      )).filter((element) => {
        const label = [element.getAttribute('aria-label'), element.textContent,
          element.getAttribute('title')].filter(Boolean).join(' ').trim().slice(0, 140);
        const rect = element.getBoundingClientRect();
        const style = getComputedStyle(element);
        return !element.disabled && !element.closest('form') &&
          rect.width > 0 && rect.height > 0 &&
          style.visibility !== 'hidden' && style.display !== 'none' &&
          safe.test(label) && !forbidden.test(label);
      }).slice(0, 5);
      let tested = 0;
      const preventNavigation = (event) => {
        const link = event.target?.closest?.('a');
        if (link) event.preventDefault();
      };
      document.addEventListener('click', preventNavigation, true);
      for (const control of controls) {
        try {
          control.dispatchEvent(new MouseEvent('click', {
            bubbles: true, cancelable: true, view: window
          }));
          tested++;
        } catch (error) {
          const text = 'navigation click threw: ' + String(error?.message || error).slice(0, 260);
          window.__htmlappRuntimeIssues?.push(text);
        }
      }
      document.removeEventListener('click', preventNavigation, true);
      return { tested };
    })();

    """#
}
