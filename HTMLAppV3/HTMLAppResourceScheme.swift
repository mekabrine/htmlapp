import Foundation
import CryptoKit
import WebKit
import UniformTypeIdentifiers

/// Per-WebView resource origin. Never serves another app's files or arbitrary URLs.
/// Feature support still depends on WebKit; custom origins are not HTTPS origins.
@MainActor
final class HTMLAppResourceScheme: NSObject, WKURLSchemeHandler {
    static let scheme = "htmlapp-resource"
    private let root: URL
    private let host: String
    private var document = Data()
    private var modules: [String: String] = [:]
    init(root: URL) {
        self.root = root.resolvingSymlinksInPath()
        host = "app-" + SHA256.hash(data: Data(root.lastPathComponent.utf8)).map { String(format: "%02x", $0) }.joined()
        super.init()
    }
    func load(_ html: String, into webView: WKWebView) {
        document = Data(html.utf8)
        modules = ForgeModuleBundle.files(in: html)
        webView.load(URLRequest(url: URL(string: "htmlapp-resource://\(host)/index.html")!))
    }
    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url, url.scheme == Self.scheme, url.host == host,
              ["GET", "HEAD"].contains(urlSchemeTask.request.httpMethod ?? "GET") else {
            urlSchemeTask.didFailWithError(URLError(.unsupportedURL)); return
        }
        let path = url.path
        let bytes: Data
        let mime: String
        if path == "/index.html" {
            bytes = document; mime = "text/html"
        } else if let source = modules[String(path.dropFirst())] {
            bytes = Data(source.utf8)
            mime = path.hasSuffix(".css") ? "text/css" : path.hasSuffix(".json") ? "application/json" : "text/javascript"
        } else {
            let base: URL
            let relative: String
            if path.hasPrefix("/libraries/") {
                guard let bundled = Bundle.main.url(forResource: "RuntimeLibraries", withExtension: nil) else {
                    urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist)); return
                }
                base = bundled.resolvingSymlinksInPath(); relative = String(path.dropFirst("/libraries/".count))
            } else { base = root; relative = String(path.dropFirst()) }
            let file = base.appendingPathComponent(relative).standardizedFileURL.resolvingSymlinksInPath()
            guard !relative.isEmpty, !relative.contains("\0"),
                  file.path.hasPrefix(base.path + "/"),
                  let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                  size <= 32 * 1024 * 1024,
                  let data = try? Data(contentsOf: file, options: .mappedIfSafe) else {
                urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist)); return
            }
            bytes = data
            switch file.pathExtension.lowercased() {
            case "js", "mjs": mime = "text/javascript"
            case "wasm": mime = "application/wasm"
            case "css": mime = "text/css"
            default: mime = UTType(filenameExtension: file.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
            }
        }
        var headers = ["Content-Type": mime, "Access-Control-Allow-Origin": "*", "Cache-Control": "no-store", "Accept-Ranges": "bytes"]
        var status = 200
        var output = bytes
        if let range = urlSchemeTask.request.value(forHTTPHeaderField: "Range") {
            let pieces = range.hasPrefix("bytes=") ? String(range.dropFirst(6)).split(separator: "-", omittingEmptySubsequences: false) : []
            if pieces.count == 2, let start = Int(pieces[0]), start >= 0, start < bytes.count,
               let end = pieces[1].isEmpty ? bytes.count - 1 : Int(pieces[1]), end >= start {
                let last = min(end, bytes.count - 1)
                output = bytes.subdata(in: start..<(last + 1)); status = 206
                headers["Content-Range"] = "bytes \(start)-\(last)/\(bytes.count)"
            } else { status = 416; output = Data(); headers["Content-Range"] = "bytes */\(bytes.count)" }
        }
        headers["Content-Length"] = String(output.count)
        guard let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers) else {
            urlSchemeTask.didFailWithError(URLError(.badServerResponse)); return
        }
        urlSchemeTask.didReceive(response)
        if urlSchemeTask.request.httpMethod != "HEAD" { urlSchemeTask.didReceive(output) }
        urlSchemeTask.didFinish()
    }
    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}
}
