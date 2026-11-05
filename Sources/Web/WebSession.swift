import Foundation
import WebKit
import AppKit
import Combine

/// One isolated web session per linked account.
///
/// Bublr never proxies or intercepts credentials: it hosts the provider's own web client in a
/// `WKWebView` whose cookie jar is keyed to the account's UUID. Signing in, sending messages and
/// read receipts therefore behave exactly like the real provider, and two accounts of the same
/// provider never see each other's session.
final class WebSession: NSObject, ObservableObject {
    enum Purpose: Equatable {
        case signingIn
        case chatting
    }

    enum AuthState: String {
        case loading
        case signedIn
        case signedOut
        /// The page is up and shows neither a sign-in surface nor a known signed-in shell.
        case app
        case unknown
        case error

        var isEntered: Bool { self == .signedIn || self == .app }
    }

    let accountID: UUID
    let provider: ProviderID
    let webView: WKWebView

    @Published var title: String = ""
    @Published var displayHost: String = ""
    @Published var progress: Double = 0
    @Published var isLoading: Bool = false
    @Published var canGoBack: Bool = false
    @Published var unread: Int = 0
    @Published var isSignedIn: Bool = false
    @Published var loadError: String?
    @Published var purpose: Purpose = .chatting
    @Published var authState: AuthState = .unknown

    /// Current page zoom. Read from the account when the session is made, then owned here so the web view
    /// and the toolbar label cannot disagree.
    private(set) var pageZoom: Double = 1

    var onTitleChange: ((Int) -> Void)?
    var onSignedIn: (() -> Void)?
    var onSessionLost: (() -> Void)?
    var customURL: URL?

    private var authTimer: Timer?
    private var titlePoll: Timer?
    private let spec: ProviderSpec
    private var signedOutStreak = 0

    static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.1 Safari/605.1.15"

    init(account: Account, purpose: Purpose) {
        self.accountID = account.id
        self.provider = account.provider
        self.spec = account.provider.spec
        self.purpose = purpose

        let config = WKWebViewConfiguration()
        // "Keep me signed in" is the only thing that makes a session outlive the app. With it off the
        // provider's cookies sit in memory only; Bublr never stores credentials of any kind.
        config.websiteDataStore = account.keepsSession
            ? WKWebsiteDataStore(forIdentifier: account.id)
            : .nonPersistent()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        config.preferences.isElementFullscreenEnabled = true

        let controller = WKUserContentController()
        let bootstrap = WKUserScript(
            source: WebSession.injectedRuntime,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false
        )
        controller.addUserScript(bootstrap)
        config.userContentController = controller

        self.webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 800, height: 600), configuration: config)
        super.init()

        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.customUserAgent = WebSession.userAgent
        webView.isInspectable = true
        // Applied before the first load so a reopened chat never flashes at 100% and then snaps.
        pageZoom = account.zoom
        webView.pageZoom = account.zoom

        controller.add(WeakMessageHandler(self), name: "bublr")

        if let custom = account.customURL, let url = URL(string: custom) {
            customURL = url
        }
        loadStartPage()
        startTitlePoll()
        startAuthPoll()
        if ProcessInfo.processInfo.environment["BUBLR_DIAG"] != nil { logDiagnostics() }
    }

    deinit {
        authTimer?.invalidate()
        titlePoll?.invalidate()
    }

    var specForProvider: ProviderSpec { spec }

    // MARK: Loading

    var startURL: URL {
        customURL ?? spec.homeURL
    }

    private func loadStartPage() {
        var request = URLRequest(url: startURL)
        request.timeoutInterval = 45
        webView.load(request)
        displayHost = startURL.host ?? ""
    }

    /// `WKWebView.pageZoom` scales the provider's page without touching the panel frame, so zoom and the
    /// window's own resize stay independent.
    func setZoom(_ value: Double) {
        let clamped = Zoom.clamped(value)
        guard clamped != pageZoom else { return }
        pageZoom = clamped
        webView.pageZoom = clamped
    }

    func reload() {
        if webView.url == nil {
            loadStartPage()
        } else {
            webView.reload()
        }
    }

    func goBack() {
        if webView.canGoBack { webView.goBack() }
    }

    func goHome() {
        webView.load(URLRequest(url: startURL))
    }

    func openInBrowser() {
        if let url = webView.url { NSWorkspace.shared.open(url) }
    }

    func beginSignIn(method: LoginMethod) {
        purpose = .signingIn
        isSignedIn = false
        signedOutStreak = 0
        progress = 0
        loadError = nil
        if webView.url == nil { loadStartPage() } else { webView.reload() }
        if method == .credentials, let js = spec.credentialsSwitchJS {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
                self?.webView.evaluateJavaScript(js, completionHandler: nil)
            }
        }
    }

    func finishSignIn() {
        purpose = .chatting
        isSignedIn = true
        authState = .signedIn
    }

    // MARK: Diagnostics

    private func logDiagnostics() {
        for (index, delay) in [3.0, 9.0, 17.0].enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.dumpState(index) }
        }
    }

    private func dumpState(_ index: Int) {
        {
            let js = """
            (function(){
              function ink(c){ try { const d=c.getContext('2d').getImageData(0,0,c.width,c.height).data; let n=0; for(let i=0;i<d.length;i+=4){ if(d[i]<128 && d[i+3]>0) n++; } return n; } catch(e){ return -1 } }
              const canvases=[...document.querySelectorAll('canvas')].map(c=>({w:c.width,h:c.height,ink:ink(c)}));
              const imgs=[...document.images].map(i=>({src:(i.currentSrc||i.src||'').slice(0,70),w:i.naturalWidth,h:i.naturalHeight,vis:i.getBoundingClientRect().width|0}));
              const cvEl=document.querySelector('canvas');
              const qrInfo=cvEl?{cls:cvEl.className,parent:cvEl.parentElement?cvEl.parentElement.className:''}:null;
              const bgData=[...document.querySelectorAll('*')].filter(e=>{const b=getComputedStyle(e).backgroundImage||'';return b.indexOf('data:')>=0}).length;
              const qrNodes=[...document.querySelectorAll('[class*="qr" i]')].slice(0,6).map(e=>({tag:e.tagName,cls:(e.className||'').toString().slice(0,60),kids:e.childElementCount,html:e.innerHTML.slice(0,80)}));
              const svgCount=document.querySelectorAll('svg').length;
              return JSON.stringify({t:document.title,cv:canvases.length,canvases:canvases,imgs:imgs.length,images:imgs,qr:qrInfo,bg:bgData,svg:svgCount,qrNodes:qrNodes,txt:document.body.innerText.slice(0,200)});
            })()
            """
            self.webView.evaluateJavaScript(js) { value, error in
                NSLog("BublrDump\(index) \(value as? String ?? "err:\(String(describing: error))")")
            }
        }()
    }

    // MARK: Auth probing

    private func startAuthPoll() {
        authTimer?.invalidate()
        let timer = Timer(timeInterval: 2.5, repeats: true) { [weak self] _ in
            self?.probeAuth()
        }
        RunLoop.main.add(timer, forMode: .common)
        authTimer = timer
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.probeAuth()
        }
    }

    private func probeAuth() {
        guard let host = webView.url?.host, !host.isEmpty else { return }
        let allowed = spec.hosts.isEmpty || spec.hosts.contains { host == $0 || host.hasSuffix("." + $0) }
        guard allowed else { return }

        webView.evaluateJavaScript(spec.authProbeJS) { [weak self] value, _ in
            guard let self, let string = value as? String,
                  let data = string.data(using: .utf8),
                  let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let raw = dict["state"] as? String,
                  let state = AuthState(rawValue: raw) else { return }
            DispatchQueue.main.async {
                self.handle(state: state)
            }
        }
    }

    private func handle(state: AuthState) {
        authState = state
        switch state {
        case .signedIn, .app:
            signedOutStreak = 0
            if purpose == .signingIn {
                handleSignedIn()
            } else if !isSignedIn {
                isSignedIn = true
            }
        case .signedOut:
            signedOutStreak += 1
            // Hysteresis: SPAs blink through an auth route while booting, so two consecutive
            // observations are required before declaring the session dead.
            if purpose == .chatting, isSignedIn, signedOutStreak >= 2 {
                isSignedIn = false
                onSessionLost?()
            }
        case .loading, .unknown, .error:
            break
        }
    }

    private func handleSignedIn() {
        guard !isSignedIn else { return }
        isSignedIn = true
        purpose = .chatting
        onSignedIn?()
    }

    // MARK: Title / unread

    private func startTitlePoll() {
        let timer = Timer(timeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.refreshTitle()
        }
        RunLoop.main.add(timer, forMode: .common)
        titlePoll = timer
    }

    private func refreshTitle() {
        webView.evaluateJavaScript("document.title") { [weak self] value, _ in
            guard let self, let title = value as? String else { return }
            DispatchQueue.main.async { self.apply(title: title) }
        }
    }

    private func apply(title: String) {
        if self.title != title { self.title = title }
        let count = WebSession.unreadCount(inTitle: title)
        if count != unread {
            unread = count
            onTitleChange?(count)
        }
    }

    static func unreadCount(inTitle title: String) -> Int {
        // Providers announce unread counts in the document title: "(3) Telegram", "Telegram (3)".
        guard let regex = try? NSRegularExpression(pattern: "\\((\\d{1,4})\\)") else { return 0 }
        let range = NSRange(title.startIndex..<title.endIndex, in: title)
        guard let match = regex.firstMatch(in: title, range: range),
              match.numberOfRanges > 1,
              let r = Range(match.range(at: 1), in: title) else { return 0 }
        return Int(title[r]) ?? 0
    }

    // MARK: Injected runtime

    static let injectedRuntime = """
    (function () {
      if (window.__bublrRuntime) return;
      window.__bublrRuntime = true;
      function post(payload) {
        try { window.webkit.messageHandlers.bublr.postMessage(payload); } catch (e) {}
      }
      function report() {
        post({ kind: 'title', title: document.title || '' });
      }
      try {
        var titleEl = document.querySelector('title');
        if (titleEl) {
          new MutationObserver(report).observe(titleEl, { subtree: true, childList: true, characterData: true });
        }
      } catch (e) {}
      setInterval(report, 2500);
    })();
    """

    // MARK: Message handler

    fileprivate func handle(message: WKScriptMessage) {
        guard let dict = message.body as? [String: Any], let kind = dict["kind"] as? String else { return }
        switch kind {
        case "title":
            if let title = dict["title"] as? String { apply(title: title) }
        default:
            break
        }
    }
}

// MARK: - Delegates

extension WebSession: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        isLoading = true
        loadError = nil
        progress = max(progress, 0.08)
        displayHost = webView.url?.host ?? displayHost
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        displayHost = webView.url?.host ?? displayHost
        webView.evaluateJavaScript(WebSession.injectedRuntime, completionHandler: nil)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isLoading = false
        progress = 1
        displayHost = webView.url?.host ?? displayHost
        canGoBack = webView.canGoBack
        if let title = webView.title, !title.isEmpty { apply(title: title) }
        // SPAs need a beat after `didFinish` before their first meaningful paint.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.probeAuth()
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        isLoading = false
        handle(error: error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        isLoading = false
        handle(error: error)
    }

    private func handle(error: Error) {
        let ns = error as NSError
        // A cancelled navigation is normal: providers redirect constantly during sign-in.
        if ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled { return }
        if ns.domain == "WebKitErrorDomain" && (ns.code == 102 || ns.code == 101) { return }
        loadError = ns.localizedDescription
    }
}

extension WebSession: WKUIDelegate {
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        forNavigationAction navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        guard let url = navigationAction.request.url else { return nil }
        if navigationAction.targetFrame == nil {
            // Links that ask for a new window are usually articles, not chat: send them to the browser.
            if spec.hosts.isEmpty || spec.hosts.contains(where: { url.host == $0 || (url.host?.hasSuffix("." + $0) ?? false) }) {
                webView.load(URLRequest(url: url))
            } else {
                NSWorkspace.shared.open(url)
            }
        }
        return nil
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping () -> Void
    ) {
        completionHandler()
    }
}

// MARK: - Weak message proxy

private final class WeakMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: WebSession?

    init(_ target: WebSession) { self.target = target }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let target else { return }
        DispatchQueue.main.async { target.handle(message: message) }
    }
}

// MARK: - Session store

final class WebSessionStore: ObservableObject {
    private var sessions: [UUID: WebSession] = [:]

    func existing(accountID: UUID) -> WebSession? { sessions[accountID] }

    func session(for account: Account, purpose: WebSession.Purpose = .chatting) -> WebSession {
        if let existing = sessions[account.id] {
            if existing.purpose != purpose {
                existing.purpose = purpose
            }
            return existing
        }
        let session = WebSession(account: account, purpose: purpose)
        session.onTitleChange = { [weak self] count in
            guard let self else { return }
            DispatchQueue.main.async {
                self.unreadHandler?(account.id, count)
            }
        }
        sessions[account.id] = session
        return session
    }

    /// Wired by the app delegate so the workspace can persist unread counts.
    var unreadHandler: ((UUID, Int) -> Void)?

    /// Forgets the in-memory session object only. The account's stored cookies are untouched.
    func drop(accountID: UUID) {
        sessions.removeValue(forKey: accountID)
    }

    /// Erases every cookie, cache and storage bucket this Mac held for the account.
    func eraseData(accountID: UUID) {
        WKWebsiteDataStore(forIdentifier: accountID).removeData(
            ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
            modifiedSince: .distantPast
        ) {}
    }

    /// Unlinks the account locally: session object and stored website data both go.
    func discard(accountID: UUID) {
        drop(accountID: accountID)
        eraseData(accountID: accountID)
    }
}
