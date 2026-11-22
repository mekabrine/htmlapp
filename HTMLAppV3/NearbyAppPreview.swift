import SwiftUI
import UIKit
import WebKit

/// Renders only the app source being shared. The preview has no saved session,
/// native bridge, persistent website data, network access, or user interaction.
@MainActor
struct NearbyAppPreview: UIViewRepresentable {
    let html: String
    let completion: (Data?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(completion: completion) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let coordinator = context.coordinator
        configuration.setURLSchemeHandler(coordinator.resources, forURLScheme: HTMLAppResourceScheme.scheme)
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = coordinator
        webView.isUserInteractionEnabled = false
        coordinator.start(html: html, in: webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.cancel()
        webView.stopLoading()
        webView.navigationDelegate = nil
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        private let root = FileManager.default.temporaryDirectory.appendingPathComponent("NearbyPreview-" + UUID().uuidString)
        lazy var resources = HTMLAppResourceScheme(root: root)
        private var completion: ((Data?) -> Void)?
        private var timeout: Task<Void, Never>?
        private var navigation: WKNavigation?

        init(completion: @escaping (Data?) -> Void) {
            self.completion = completion
        }

        func start(html: String, in webView: WKWebView) {
            timeout = Task { [weak self] in
                do { try await Task.sleep(nanoseconds: 4_000_000_000) } catch { return }
                self?.finish(nil)
            }
            // Keep the custom HTMLApp resource origin for bundled libraries.
            let remoteRules = #"[{"trigger":{"url-filter":"^(https?|wss?|ftp)://"},"action":{"type":"block"}}]"#
            WKContentRuleListStore.default().compileContentRuleList(
                forIdentifier: "HTMLAppNearbyPreviewOffline", encodedContentRuleList: remoteRules
            ) { [weak self, weak webView] list, _ in
                Task { @MainActor in
                    guard let self, let webView, self.completion != nil else { return }
                    guard let list else { self.finish(nil); return }
                    webView.configuration.userContentController.add(list)
                    let source = Self.restrictNetwork(in: html)
                    if HTMLAppDocumentMode.usesPackageRuntime(source) {
                        self.navigation = self.resources.load(source, into: webView)
                    } else {
                        self.navigation = webView.loadHTMLString(source, baseURL: nil)
                    }
                }
            }
        }

        private static func restrictNetwork(in html: String) -> String {
            let policy = """
            <meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'unsafe-inline' 'unsafe-eval' htmlapp-resource:; style-src 'unsafe-inline' htmlapp-resource:; img-src data: blob: htmlapp-resource:; font-src data: htmlapp-resource:; media-src data: blob: htmlapp-resource:; connect-src 'none'; frame-src 'none'; form-action 'none'; base-uri 'none'">
            """
            var document = html
            if let head = document.range(of: #"<head\b[^>]*>"#, options: [.regularExpression, .caseInsensitive]),
               let documentRoot = document.range(of: #"<html\b[^>]*>"#, options: [.regularExpression, .caseInsensitive]),
               documentRoot.upperBound <= head.lowerBound,
               document[documentRoot.upperBound..<head.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                document.insert(contentsOf: policy, at: head.upperBound)
            } else {
                document = policy + document
            }
            return document
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard action.targetFrame?.isMainFrame == true, action.navigationType == .other,
                  let url = action.request.url,
                  url.absoluteString == "about:blank" || resources.isDocumentURL(url) else {
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard navigation === self.navigation, completion != nil,
                  webView.bounds.width > 1, webView.bounds.height > 1 else { return }
            let config = WKSnapshotConfiguration()
            config.rect = webView.bounds
            config.snapshotWidth = 320
            config.afterScreenUpdates = true
            webView.takeSnapshot(with: config) { [weak self] image, _ in
                self?.finish(image?.jpegData(compressionQuality: 0.68))
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            if navigation === self.navigation { finish(nil) }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            if navigation === self.navigation { finish(nil) }
        }

        func cancel() {
            timeout?.cancel()
            timeout = nil
            completion = nil
        }

        private func finish(_ data: Data?) {
            let done = completion
            cancel()
            done?(data)
        }
    }
}
