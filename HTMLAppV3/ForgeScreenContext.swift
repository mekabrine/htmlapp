import SwiftUI
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
        guard let webView else { return "Screen details unavailable." }
        let value = try? await webView.evaluateJavaScript("window.__forgeScreenContext?.report()")
        guard let text = value as? String, !text.isEmpty else { return "Screen details unavailable." }
        return String(text.prefix(1800))
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
          return (tab ? describe(tab) : 'Current app view') + (last ? '\nLast control: ' + last : '');
        }
      };
    })();
    """#
}
