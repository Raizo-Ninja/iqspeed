import SwiftUI
import WebKit
import UIKit

private let host = "iqspeed.net"
private let home = URL(string: "https://iqspeed.net/")!
private let bg = UIColor(red: 7/255, green: 11/255, blue: 22/255, alpha: 1)

struct WebContainer: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> WebViewController { WebViewController() }
    func updateUIViewController(_ vc: WebViewController, context: Context) {}
}

/// Hosts the site in a WKWebView and adds native pieces: share sheet, printing,
/// keep-awake while a test runs, pull-to-refresh, offline screen, external links in Safari.
final class WebViewController: UIViewController, WKNavigationDelegate, WKScriptMessageHandler, WKUIDelegate {
    private var web: WKWebView!
    private let refresh = UIRefreshControl()
    private var busy = false { didSet { UIApplication.shared.isIdleTimerDisabled = busy; refresh.isEnabled = !busy } }

    // Same bridge names the Android app exposes, so the site needs one code path.
    private static let glue = """
    (function(){ if(window.__iqGlue) return; window.__iqGlue = 1;
      var post = function(m){ try{ window.webkit.messageHandlers.iq.postMessage(m); }catch(e){} };
      window.AndroidBridge = {
        share: function(t){ post({a:'share', t:String(t)}); },
        setBusy: function(b){ post({a:'busy', b:!!b}); },
        print: function(){ post({a:'print'}); },
        retry: function(){ post({a:'retry'}); }
      };
      window.print = function(){ post({a:'print'}); };
      var hook = function(){
        var b = document.getElementById('startBtn'); if(!b) return false;
        var f = function(){ post({a:'busy', b:!!b.disabled}); };
        new MutationObserver(f).observe(b, {attributes:true, attributeFilter:['disabled']}); f(); return true;
      };
      if(!hook()) document.addEventListener('DOMContentLoaded', hook);
    })();
    """

    override func loadView() {
        let cfg = WKWebViewConfiguration()
        cfg.applicationNameForUserAgent = "IQSpeedApp/iOS"
        cfg.allowsInlineMediaPlayback = true
        let ucc = WKUserContentController()
        ucc.addUserScript(WKUserScript(source: Self.glue, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        ucc.add(WeakHandler(self), name: "iq")
        cfg.userContentController = ucc

        web = WKWebView(frame: .zero, configuration: cfg)
        web.navigationDelegate = self
        web.uiDelegate = self
        web.isOpaque = false
        web.backgroundColor = bg
        web.scrollView.backgroundColor = bg
        web.scrollView.contentInsetAdjustmentBehavior = .never   // the page handles safe areas itself
        web.allowsBackForwardNavigationGestures = true
        refresh.tintColor = UIColor(red: 62/255, green: 224/255, blue: 1, alpha: 1)
        refresh.addTarget(self, action: #selector(pull), for: .valueChanged)
        web.scrollView.refreshControl = refresh
        view = web
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        web.load(URLRequest(url: home))
    }

    @objc private func pull() {
        if busy { refresh.endRefreshing(); return }
        if web.url?.host == host { web.reload() } else { web.load(URLRequest(url: home)) }
    }

    // MARK: bridge
    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame else { return }
        let origin = message.frameInfo.securityOrigin
        let trusted = (origin.protocol == "https" && origin.host == host) || web.url == nil || web.url?.scheme == "about"
        guard trusted, let body = message.body as? [String: Any], let action = body["a"] as? String else { return }
        switch action {
        case "busy":
            busy = (body["b"] as? Bool) ?? false
        case "share":
            guard let text = body["t"] as? String else { return }
            let sheet = UIActivityViewController(activityItems: [String(text.prefix(20000))], applicationActivities: nil)
            sheet.popoverPresentationController?.sourceView = view
            sheet.popoverPresentationController?.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.maxY - 80, width: 1, height: 1)
            present(sheet, animated: true)
        case "print":
            let pc = UIPrintInteractionController.shared
            let info = UIPrintInfo(dictionary: nil); info.jobName = "iqspeed-report"; info.outputType = .general
            pc.printInfo = info
            pc.printFormatter = web.viewPrintFormatter()
            pc.present(animated: true)
        case "retry":
            web.load(URLRequest(url: home))
        default: break
        }
    }

    // MARK: navigation
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url else { return decisionHandler(.cancel) }
        if url.scheme == "about" { return decisionHandler(.allow) }
        if url.scheme == "https" && url.host == host { return decisionHandler(.allow) }
        if action.targetFrame?.isMainFrame ?? true {
            UIApplication.shared.open(url)
            return decisionHandler(.cancel)
        }
        decisionHandler(.allow)
    }

    // target=_blank links
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = action.request.url { UIApplication.shared.open(url) }
        return nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { refresh.endRefreshing() }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        refresh.endRefreshing()
        let e = error as NSError
        if e.code == NSURLErrorCancelled { return }
        webView.loadHTMLString(Self.offline, baseURL: nil)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { webView.reload() }

    private static let offline = """
    <!doctype html><html lang="ar" dir="rtl"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
    <style>html,body{margin:0;height:100%;background:#070b16;color:#e8eefb;font-family:-apple-system,sans-serif}
    .w{min-height:100%;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:14px;padding:24px;box-sizing:border-box;text-align:center}
    .i{width:72px;height:72px;border-radius:20px;background:linear-gradient(135deg,#3ee0ff,#7c6cff);display:grid;place-items:center}
    h1{font-size:20px;margin:6px 0 0}p{color:#8a99ba;margin:0;line-height:1.7;max-width:320px}
    button{margin-top:10px;border:0;border-radius:14px;padding:13px 28px;font-size:16px;font-weight:700;color:#06101f;background:linear-gradient(135deg,#3ee0ff,#7c6cff)}</style></head>
    <body><div class="w"><div class="i"><svg width="36" height="36" viewBox="0 0 64 64"><path d="M35 12 20 38h12l-3 14 15-26H33z" fill="#06101f"/></svg></div>
    <h1>لا يوجد اتصال بالإنترنت</h1><p>تحقق من الواي فاي أو بيانات الهاتف ثم أعد المحاولة.<br>پەیوەندی ئینتەرنێت نییە — دووبارە هەوڵ بدەرەوە.<br>No internet connection.</p>
    <button onclick="window.webkit.messageHandlers.iq.postMessage({a:'retry'})">إعادة المحاولة · Retry</button></div></body></html>
    """
}

/// Avoids the retain cycle WKUserContentController creates with its message handlers.
private final class WeakHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ t: WKScriptMessageHandler) { target = t }
    func userContentController(_ c: WKUserContentController, didReceive m: WKScriptMessage) { target?.userContentController(c, didReceive: m) }
}
