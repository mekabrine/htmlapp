import Foundation
import UIKit
import WebKit

/// Checks actual DOM geometry before Forge offers a style to the user.
/// A full app verifier runs after coding, but visual sketches must be tested
/// before selection so a tiny desktop canvas isn't chosen as a "good" look.
@MainActor
enum ForgeStyleMobileQualityCheck {
    static func inspect(_ html: String) async -> String? {
        let session = Session(html: html)
        return await session.run()
    }

    private final class Session: NSObject, WKNavigationDelegate {
        private let html: String
        private var continuation: CheckedContinuation<String?, Never>?
        private var webView: WKWebView?
        private var watchdog: Task<Void, Never>?
        private var finished = false

        init(html: String) {
            self.html = html
            super.init()
        }

        func run() async -> String? {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                let config = WKWebViewConfiguration()
                config.websiteDataStore = .nonPersistent()
                config.defaultWebpagePreferences.allowsContentJavaScript = true
                config.preferences.javaScriptCanOpenWindowsAutomatically = false
                let webView = WKWebView(
                    frame: CGRect(x: 0, y: 0, width: 320, height: 700),
                    configuration: config
                )
                self.webView = webView
                webView.isHidden = true
                webView.navigationDelegate = self
                webView.scrollView.contentInsetAdjustmentBehavior = .never
                webView.scrollView.pinchGestureRecognizer?.isEnabled = false
                var document = html
                let safeHead = """
                <meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
                <meta http-equiv="Content-Security-Policy"
                content="default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline';
                img-src data: blob:; font-src data:; connect-src 'none'; frame-src 'none'">
                """
                if let head = document.range(
                    of: #"<head\b[^>]*>"#, options: [.regularExpression, .caseInsensitive]
                ) {
                    document.replaceSubrange(head, with: String(document[head]) + safeHead)
                }
                webView.loadHTMLString(document, baseURL: nil)
                watchdog = Task { [weak self] in
                    try? await Task.sleep(nanoseconds: 4_000_000_000)
                    guard !Task.isCancelled else { return }
                    // Fail closed. A style that we could not measure must
                    // never be silently approved as a good mobile preview.
                    self?.finish("This style could not be verified at phone width. Generate a simpler responsive layout.")
                }
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let check = #"""
            (() => {
              const width = 320;
              const actualViewport = document.documentElement.clientWidth || innerWidth;
              const elements = Array.from(document.body?.querySelectorAll('*') || []).slice(0, 1000);
              const overflowing = [];
              let tinyText = 0;
              let visibleText = 0;
              for (const element of elements) {
                const css = getComputedStyle(element);
                if (css.display === 'none' || css.visibility === 'hidden' ||
                    Number(css.opacity) === 0) continue;
                const bounds = element.getBoundingClientRect();
                if (bounds.width < 1 || bounds.height < 1) continue;
                if (bounds.right > width + 6 || bounds.left < -6) {
                  const id = element.id ? '#' + element.id
                    : element.className && typeof element.className === 'string'
                      ? '.' + element.className.trim().split(/\s+/).slice(0, 2).join('.')
                      : element.tagName.toLowerCase();
                  if (overflowing.length < 6) overflowing.push(id.slice(0, 70));
                }
                if (!element.children.length && element.textContent?.trim().length > 4) {
                  visibleText++;
                  if (parseFloat(css.fontSize) < 11.5) tinyText++;
                }
              }
              return {
                width,
                actualViewport,
                scrollWidth: Math.max(document.documentElement.scrollWidth,
                  document.body?.scrollWidth || 0),
                overflow: overflowing,
                tinyText, visibleText
              };
            })()
            """#
            webView.evaluateJavaScript(check) { [weak self] result, error in
                Task { @MainActor in
                    guard let self else { return }
                    guard error == nil, let values = result as? [String: Any] else {
                        self.finish("Could not inspect this style's live layout. Try a simpler responsive sketch.")
                        return
                    }
                    let viewport = (values["width"] as? NSNumber)?.doubleValue ?? 320
                    let actualViewport = (values["actualViewport"] as? NSNumber)?.doubleValue ?? 320
                    let scroll = (values["scrollWidth"] as? NSNumber)?.doubleValue ?? 320
                    let over = values["overflow"] as? [String] ?? []
                    let tiny = (values["tinyText"] as? NSNumber)?.intValue ?? 0
                    let text = (values["visibleText"] as? NSNumber)?.intValue ?? 0
                    if actualViewport > viewport + 5 || scroll > viewport + 5 || !over.isEmpty {
                        self.finish("Mobile preview overflows the 320px viewport. Out-of-bounds elements: " +
                                    over.prefix(4).joined(separator: ", ") +
                                    ". Stack content vertically and use responsive widths.")
                    } else if text >= 4 && tiny >= 3 && tiny * 3 >= text {
                        self.finish("Preview text is too small to read at normal iPhone scale. " +
                                    "Use 14–17px body text and larger headings, not a shrunken desktop mockup.")
                    } else {
                        self.finish(nil)
                    }
                }
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!,
                     withError error: Error) {
            finish("The generated style preview couldn't be loaded.")
        }

        func webView(_ webView: WKWebView,
                     didFailProvisionalNavigation navigation: WKNavigation!,
                     withError error: Error) {
            finish("The generated style preview couldn't be loaded.")
        }

        private func finish(_ issue: String?) {
            guard !finished else { return }
            finished = true
            watchdog?.cancel()
            webView?.stopLoading()
            webView?.navigationDelegate = nil
            webView = nil
            continuation?.resume(returning: issue)
            continuation = nil
        }
    }
}
