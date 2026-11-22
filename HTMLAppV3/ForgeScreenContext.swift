import SwiftUI
import UIKit
import WebKit

@MainActor
final class ForgeScreenContext: ObservableObject {
    weak var webView: WKWebView?
    @Published private(set) var picking = false
    @Published private(set) var selection = ""

    func toggleSelection() {
        guard let webView else { return }
        if picking { clear(); return }
        picking = true
        webView.evaluateJavaScript("window.__forgeScreenContext?.pick(true)") { [weak self] _, error in
            if error != nil { self?.picking = false }
        }
    }

    func accept(_ description: String) {
        guard picking else { return }
        selection = String(description.prefix(800))
        picking = false
    }

    func clear() {
        picking = false
        selection = ""
        webView?.evaluateJavaScript("window.__forgeScreenContext?.clear()")
    }

    func report() async -> String {
        guard let webView else { return "" }
        let value = try? await webView.evaluateJavaScript("window.__forgeScreenContext?.report()")
        guard let text = value as? String, !text.isEmpty else { return "" }
        return String(text.prefix(3000))
    }

    func screenshot() async -> ForgeAttachment? {
        guard let webView, webView.window != nil, !webView.bounds.isEmpty else { return nil }
        let configuration = WKSnapshotConfiguration()
        configuration.rect = webView.bounds
        configuration.snapshotWidth = NSNumber(value: min(Double(webView.bounds.width), 800))
        configuration.afterScreenUpdates = false
        let image: UIImage? = await withCheckedContinuation { continuation in
            webView.takeSnapshot(with: configuration) { image, _ in continuation.resume(returning: image) }
        }
        guard let image else { return nil }
        return try? ForgeAttachment.photo(image, name: "Current app screen.jpg")
    }

    static let script = #"""
    (() => {
      let picking = false, marked = null, outline = '', last = '';
      const describe = (el, styles = false) => {
        const hint = el.getAttribute('data-forge-id') || el.id;
        const screen = el.closest('[data-htmlapp-screen],[data-forge-screen],[data-screen]');
        const tab = screen?.getAttribute('data-htmlapp-screen') || screen?.getAttribute('data-forge-screen') || screen?.getAttribute('data-screen');
        const classes = typeof el.className === 'string' ? el.className.trim().slice(0, 160) : '';
        const id = hint ? ' id=' + hint : '';
        const css = styles ? getComputedStyle(el) : null;
        return (el.localName + id + (classes ? ' classes=' + classes : '') +
          (tab ? ' screen=' + tab : '') + (css ? ' font=' + css.fontSize + ' color=' + css.color +
          ' background=' + css.backgroundColor + ' display=' + css.display : '')).slice(0, 800);
      };
      const clear = () => {
        picking = false;
        if (marked) { marked.style.outline = outline; marked = null; }
      };
      document.addEventListener('click', event => {
        if (!(event.target instanceof Element)) return;
        const el = event.target.closest('[data-forge-id],button,a,input,select,textarea,[role="button"]') || event.target;
        if (!picking) { last = describe(el); return; }
        event.preventDefault(); event.stopImmediatePropagation();
        clear(); marked = el; outline = el.style.outline; el.style.outline = '3px solid #a855f7';
        window.webkit.messageHandlers.htmlappForgeSelection.postMessage({selection:describe(el, true)});
      }, true);
      window.__forgeScreenContext = {
        pick(value) { clear(); picking = value; },
        clear,
        report() {
          const tab = document.querySelector('[data-htmlapp-screen]:not([hidden]),[role="tab"][aria-selected="true"]');
          const width = window.innerWidth, height = window.innerHeight;
          const visible = [];
          const nodes = document.querySelectorAll('header,main,nav,section,h1,h2,button,a,input,select,textarea,[data-forge-id],[role="button"]');
          for (const node of nodes) {
            const rect = node.getBoundingClientRect();
            if (rect.width < 2 || rect.height < 2 || rect.right <= 0 || rect.left >= width ||
                rect.bottom <= 0 || rect.top >= height || node.closest('[hidden],[aria-hidden="true"]')) continue;
            const style = getComputedStyle(node);
            if (style.visibility !== 'visible' || style.opacity === '0') continue;
            visible.push(describe(node, true) + ' x/y/w/h=' +
              [rect.x, rect.y, rect.width, rect.height].map(Math.round).join('/'));
            if (visible.length >= 12) break;
          }
          return 'Viewport ' + width + '×' + height + '\n' +
            (tab ? describe(tab) : 'Current app view') +
            (last ? '\nLast control: ' + last : '') + '\n' + visible.join('\n');
        }
      };
    })();
    """#
}
