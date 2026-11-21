import SwiftUI
import WebKit

/// A WKWebView that injects the blocker script into every page before the site's own code runs.
struct BlockingWebView: UIViewRepresentable {
    let platform: Platform
    let settings: BlockerSettings

    // Look exactly like Safari on THIS phone's iOS version. A mismatched user agent
    // (e.g. claiming iOS 18 on an iOS 17 phone) makes Instagram's login reject us.
    private static var safariSuffix: String {
        let parts = UIDevice.current.systemVersion.split(separator: ".")
        let version = parts.prefix(2).joined(separator: ".")
        return "Version/\(version) Mobile/15E148 Safari/604.1"
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(platform: platform, settings: settings)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()              // keeps you logged in between launches
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = .all  // no autoplay
        config.applicationNameForUserAgent = Self.safariSuffix  // real WebKit UA + Safari suffix
        config.preferences.javaScriptCanOpenWindowsAutomatically = true

        let script = WKUserScript(
            source: platform.blockerScript(settings: settings),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        config.userContentController.addUserScript(script)

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.allowsBackForwardNavigationGestures = true  // swipe to go back
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator

        let refresh = UIRefreshControl()
        refresh.addTarget(context.coordinator, action: #selector(Coordinator.pullToRefresh(_:)), for: .valueChanged)
        webView.scrollView.refreshControl = refresh

        context.coordinator.webView = webView
        webView.load(URLRequest(url: platform.homeURL))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let platform: Platform
        let settings: BlockerSettings
        weak var webView: WKWebView?

        init(platform: Platform, settings: BlockerSettings) {
            self.platform = platform
            self.settings = settings
        }

        @objc func pullToRefresh(_ sender: UIRefreshControl) {
            webView?.reload()
            sender.endRefreshing()
        }

        // Second line of defence: catches full page loads of blocked URLs
        // (the injected JS handles in-page navigation, which never reaches here).
        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url,
                  navigationAction.targetFrame?.isMainFrame ?? true,
                  let safeURL = platform.redirect(for: url, settings: settings) else {
                decisionHandler(.allow)
                return
            }
            decisionHandler(.cancel)
            webView.load(URLRequest(url: safeURL))
        }

        // Login flows (Facebook, Google, security checks) open real popup windows that talk
        // back to the page that opened them. Show them as a layer on top, then remove on close.
        func webView(_ webView: WKWebView,
                     createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction,
                     windowFeatures: WKWindowFeatures) -> WKWebView? {
            let popup = WKWebView(frame: webView.bounds, configuration: configuration)
            popup.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            popup.navigationDelegate = self
            popup.uiDelegate = self
            webView.addSubview(popup)
            return popup
        }

        func webViewDidClose(_ webView: WKWebView) {
            if webView !== self.webView {
                webView.removeFromSuperview()
            }
        }
    }
}
