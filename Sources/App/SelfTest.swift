import AppKit
import SwiftUI
import WebKit
import Foundation

/// `Bublr --selftest` exercises what is easy to get wrong without a human watching: model and
/// layout math, persistence, the overlay contract, and — most importantly — that the real provider
/// sign-in pages load and render inside the exact `WKWebView` configuration the app uses.
final class SelfTestRunner: NSObject, NSApplicationDelegate {
    private var passed = 0
    private var failed = 0
    private var results: [[String: Any]] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        DispatchQueue.main.async { [weak self] in
            self?.runAll()
        }
    }

    private func check(_ name: String, _ condition: Bool, _ detail: String = "") {
        if condition { passed += 1 } else { failed += 1 }
        results.append(["check": name, "ok": condition, "detail": detail])
        print("\(condition ? "PASS" : "FAIL")  \(name)\(detail.isEmpty ? "" : "  — \(detail)")")
    }

    private func runAll() {
        print("Bublr self-test — \(Date())")
        modelTests()
        layoutTests()
        persistenceTests()
        overlayTests()
        print("\nLive provider pages (real network, real WKWebView, off-screen)")
        liveWebTests { [weak self] in
            self?.summary()
        }
    }

    // MARK: Model

    private func modelTests() {
        check("unread parsed from '(3) Telegram'", WebSession.unreadCount(inTitle: "(3) Telegram") == 3)
        check("unread parsed from 'Telegram (12)'", WebSession.unreadCount(inTitle: "Telegram (12)") == 12)
        check("unread zero for plain title", WebSession.unreadCount(inTitle: "Telegram") == 0)
        check("unread guard rejects 5 digits", WebSession.unreadCount(inTitle: "(99999) Telegram") == 0)

        let workspace = Workspace(storeURL: temporaryStoreURL("model"))
        let bubble = workspace.addBubble(for: .telegram)
        check("bubble added", workspace.bubble(for: .telegram) != nil)
        check("bubble begins expanded", bubble.collapsed == false)

        let account = workspace.addAccount(provider: .telegram, label: "")
        check("account added to provider", workspace.accounts(for: .telegram).count == 1)
        check("account gets a friendly default label", account.label == "Telegram 1", account.label)
        check("new account needs sign-in", workspace.account(id: account.id)?.status == .needsSignIn)

        workspace.beginSignIn(account: account, method: .qr)
        check("sign-in pending", workspace.pendingSignIns.count == 1)
        workspace.setAccountStatus(id: account.id, status: .connected)
        workspace.updatePendingSignIn(accountID: account.id, method: .credentials)
        check("sign-in method can change", workspace.pendingSignIns.first?.method == .credentials)
        workspace.finishSignIn(accountID: account.id)
        check("sign-in finished", workspace.pendingSignIns.isEmpty)
        check("account connected", workspace.account(id: account.id)?.status == .connected)

        workspace.setUnread(5, for: account.id)
        check("unread rolls up to the provider", workspace.unreadTotal(for: .telegram) == 5)
        workspace.setDrill(account.id, for: .telegram)
        check("drill clears unread", workspace.account(id: account.id)?.unread == 0)
        check("drill target stored", workspace.bubble(for: .telegram)?.drilledAccountID == account.id)

        workspace.setCollapsed(true, for: .telegram)
        check("collapse clears drill", workspace.bubble(for: .telegram)?.drilledAccountID == nil)

        workspace.setFloating(true, for: account.id)
        check("account pops out", workspace.account(id: account.id)?.isFloating == true)
        check("pop-out gives it a frame", workspace.account(id: account.id)?.floatingOrigin != nil)
        workspace.setFloatingCollapsed(true, for: account.id)
        check("popped-out bubble collapses", workspace.account(id: account.id)?.floatingCollapsed == true)
        workspace.setFloating(false, for: account.id)
        check("account docks back", workspace.account(id: account.id)?.isFloating == false)

        workspace.renameAccount(id: account.id, label: "Work")
        check("rename applies", workspace.account(id: account.id)?.label == "Work")

        let second = workspace.addAccount(provider: .telegram, label: "Personal")
        check("accounts stack", workspace.accounts(for: .telegram).count == 2)
        workspace.removeAccount(id: second.id)
        check("remove account", workspace.accounts(for: .telegram).count == 1)

        workspace.addBubble(for: .messenger)
        check("second provider bubble", workspace.bubbles.count == 2)
        _ = workspace.addAccount(provider: .messenger, label: "")
        workspace.removeBubble(for: .messenger)
        check("removing a bubble removes its accounts", workspace.accounts(for: .messenger).isEmpty)

        let catalog = ProviderCatalog.all
        check("catalog covers Telegram, Messenger, Zalo",
              catalog.contains { $0.id == .telegram } && catalog.contains { $0.id == .messenger } && catalog.contains { $0.id == .zalo })
        check("telegram allows QR and password",
              ProviderCatalog.telegramSpec.loginMethods.contains(.qr) && ProviderCatalog.telegramSpec.loginMethods.contains(.credentials))
        check("zalo allows QR", ProviderCatalog.zaloSpec.loginMethods.contains(.qr))
        check("whatsapp is QR-only", ProviderCatalog.whatsappSpec.loginMethods == [.qr])
        check("whatsapp is browser-only", !ProviderCatalog.whatsappSpec.runsInWebKit)
        check("browser-only providers stay out of the catalog", !ProviderCatalog.available.contains { $0.id == .whatsapp })
        let core: [ProviderID] = [.telegram, .messenger, .zalo]
        check("core providers are offered", core.allSatisfy { wanted in ProviderCatalog.available.contains { $0.id == wanted } })
        check("messenger is password-only", ProviderCatalog.messengerSpec.loginMethods == [.credentials])
        check("every provider uses https", catalog.allSatisfy { $0.homeURL.scheme == "https" })
        check("every provider has an auth probe", catalog.allSatisfy { $0.authProbeJS.contains("signedOut") })
        check("every login method has guidance",
              catalog.allSatisfy { spec in spec.loginMethods.allSatisfy { spec.loginHint[$0]?.isEmpty == false } })
        check("provider hosts cover their home host",
              catalog.allSatisfy { spec in spec.hosts.isEmpty || spec.hosts.contains { spec.homeURL.host?.hasSuffix($0) == true } })

        // Privacy: Bublr stores a label and a provider session, never a credential.
        workspace.setKeepSignedIn(false, for: account.id)
        check("keep-me-signed-in can be turned off", workspace.account(id: account.id)?.keepsSession == false)
        workspace.setKeepSignedIn(true, for: account.id)
        check("keep-me-signed-in can be turned back on", workspace.account(id: account.id)?.keepsSession == true)

        var legacy = Account(provider: .zalo, label: "Old")
        legacy.keepSignedIn = nil
        check("accounts from older builds default to a remembered session", legacy.keepsSession)

        let store = WebSessionStore()
        let persistent = store.session(for: Account(provider: .telegram, label: "P"))
        check("a remembered account keeps a persistent store",
              persistent.webView.configuration.websiteDataStore.isPersistent)
        var privateAccount = Account(provider: .telegram, label: "Q")
        privateAccount.keepSignedIn = false
        let ephemeral = store.session(for: privateAccount)
        check("a private account keeps nothing on disk",
              !ephemeral.webView.configuration.websiteDataStore.isPersistent)

        let privacyURL = temporaryStoreURL("privacy")
        let privacy = Workspace(storeURL: privacyURL)
        privacy.addBubble(for: .telegram)
        let savedAccount = privacy.addAccount(provider: .telegram, label: "Work")
        privacy.setAccountStatus(id: savedAccount.id, status: .connected)
        privacy.setUnread(2, for: savedAccount.id)
        privacy.saveNow()
        let raw = (try? String(contentsOf: privacyURL, encoding: .utf8)) ?? ""
        let lowered = raw.lowercased()
        let forbidden = ["password", "passwd", "secret", "token", "otp", "2fa", "cookie", "credential"]
        check("state file stores no secret material",
              forbidden.allSatisfy { !lowered.contains("\"\($0)") },
              forbidden.filter { lowered.contains("\"\($0)") }.joined(separator: ","))
        check("state file does keep the bubble layout",
              lowered.contains("\"bubbles\"") && lowered.contains("\"accounts\""))
        try? FileManager.default.removeItem(at: privacyURL.deletingLastPathComponent())
    }

    // MARK: Layout

    private func layoutTests() {
        check("empty bubble height", Metrics.expandedHeight(accountCount: 0) == 290,
              "\(Metrics.expandedHeight(accountCount: 0))")
        check("one account bubble height", Metrics.expandedHeight(accountCount: 1) == 200,
              "\(Metrics.expandedHeight(accountCount: 1))")
        check("more accounts grow the bubble",
              Metrics.expandedHeight(accountCount: 2) > Metrics.expandedHeight(accountCount: 1))
        check("bubble caps at five visible rows",
              Metrics.expandedHeight(accountCount: 9) == Metrics.expandedHeight(accountCount: 5))
        check("collapsed bubble is a 64pt square", Metrics.collapsedSide == 64)
        check("chat is larger than the list", Metrics.chatWidth > Metrics.bubbleWidth && Metrics.chatHeight > 400)
    }

    // MARK: Persistence

    private func persistenceTests() {
        let url = temporaryStoreURL("persist")
        let workspace = Workspace(storeURL: url)
        workspace.addBubble(for: .zalo)
        let account = workspace.addAccount(provider: .zalo, label: "Family")
        workspace.setAccountStatus(id: account.id, status: .connected)
        workspace.setUnread(9, for: account.id)
        workspace.setCollapsed(true, for: .zalo)
        workspace.saveNow()

        let reloaded = Workspace(storeURL: url)
        check("state file written", FileManager.default.fileExists(atPath: url.path), url.path)
        check("accounts survive relaunch", reloaded.accounts.count == 1)
        check("labels survive relaunch", reloaded.accounts.first?.label == "Family")
        check("unread survives relaunch", reloaded.accounts.first?.unread == 9)
        check("collapsed bubble survives relaunch", reloaded.bubble(for: .zalo)?.collapsed == true)
        check("provider survives relaunch", reloaded.accounts.first?.provider == .zalo)
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    // MARK: Overlay

    private func overlayTests() {
        let workspace = Workspace(storeURL: temporaryStoreURL("overlay"))
        workspace.addBubble(for: .telegram)
        workspace.addAccount(provider: .telegram, label: "QA")
        let sessions = WebSessionStore()
        let overlay = OverlayController(workspace: workspace, sessions: sessions)
        overlay.start()
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))

        let panel = overlay.panel(for: .provider(.telegram))
        check("overlay creates one panel per provider bubble", panel != nil)
        if let panel {
            check("bubble floats above normal windows", panel.level == .floating, "level=\(panel.level.rawValue)")
            check("bubble joins every Space", panel.collectionBehavior.contains(.canJoinAllSpaces))
            check("bubble survives full-screen apps", panel.collectionBehavior.contains(.fullScreenAuxiliary))
            check("bubble never activates the app", panel.styleMask.contains(.nonactivatingPanel))
            check("bubble is transparent", !panel.isOpaque && panel.backgroundColor.alphaComponent == 0)
            check("bubble can accept typing", panel.canBecomeKey)
            check("bubble is not a main window", !panel.canBecomeMain)
            check("bubble is on screen", panel.isVisible)

            let expanded = panel.frame.size
            check("bubble width matches metrics", abs(expanded.width - Metrics.bubbleWidth) < 1, "\(expanded.width)")
            check("bubble height fits one account",
                  abs(expanded.height - Metrics.expandedHeight(accountCount: 1)) < 1, "\(expanded.height)")

            workspace.setCollapsed(true, for: .telegram)
            overlay.sync()
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
            check("collapse shrinks the panel to a circle",
                  abs(panel.frame.width - Metrics.collapsedSide) < 1 && abs(panel.frame.height - Metrics.collapsedSide) < 1,
                  "\(panel.frame.size)")

            workspace.setCollapsed(false, for: .telegram)
            overlay.sync()
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
            check("expand restores the bubble",
                  abs(panel.frame.height - Metrics.expandedHeight(accountCount: 1)) < 1,
                  "\(panel.frame.height)")

            let originBefore = panel.frame.origin
            var moved = panel.frame
            moved.origin = NSPoint(x: originBefore.x - 40, y: originBefore.y - 30)
            panel.setFrame(moved, display: true)
            RunLoop.current.run(until: Date().addingTimeInterval(0.4))
            check("moving the panel persists (drag path)",
                  workspace.bubble(for: .telegram)?.origin == panel.frame.origin,
                  "panel=\(panel.frame.origin) stored=\(String(describing: workspace.bubble(for: .telegram)?.origin))")

            // The real header handle, as installed in the live bubble.
            let handle = firstDragHandle(panel.contentView)
            check("the live bubble header installs a drag handle", handle != nil)
            if let handle {
                let headerStart = panel.frame.origin
                handle.beginDrag(at: NSPoint(x: 700, y: 600))
                handle.continueDrag(to: NSPoint(x: 640, y: 566))
                check("dragging the live header moves the bubble",
                      abs(panel.frame.origin.x - (headerStart.x - 60)) < 1
                        && abs(panel.frame.origin.y - (headerStart.y - 34)) < 1,
                      "panel=\(panel.frame.origin) start=\(headerStart)")
                handle.finishDrag(clickCount: 1)
                RunLoop.current.run(until: Date().addingTimeInterval(0.3))
                check("a dropped bubble remembers its new place",
                      workspace.bubble(for: .telegram)?.origin == panel.frame.origin,
                      "panel=\(panel.frame.origin) stored=\(String(describing: workspace.bubble(for: .telegram)?.origin))")
            }

            // A bubble under the pointer must not be re-laid-out by an unrelated state change:
            // that was what made dragging feel glued in place.
            let dragStart = panel.frame.origin
            NotificationCenter.default.post(name: .bublrBeginDrag, object: panel)
            panel.setFrameOrigin(NSPoint(x: dragStart.x + 60, y: dragStart.y - 45))
            workspace.setUnread(3, for: workspace.accounts(for: .telegram).first?.id ?? UUID())
            overlay.sync(animated: false)
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            check("a dragged bubble is not re-positioned mid-drag",
                  abs(panel.frame.origin.x - (dragStart.x + 60)) < 1 && abs(panel.frame.origin.y - (dragStart.y - 45)) < 1,
                  "panel=\(panel.frame.origin) start=\(dragStart)")
            NotificationCenter.default.post(name: .bublrEndDrag, object: panel, userInfo: ["moved": true])
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
            check("drag end persists where the bubble was dropped",
                  workspace.bubble(for: .telegram)?.origin == panel.frame.origin,
                  "panel=\(panel.frame.origin) stored=\(String(describing: workspace.bubble(for: .telegram)?.origin))")
        // Regression: a click must release the panel, or later layout changes (collapse) never land.
        NotificationCenter.default.post(name: .bublrBeginDrag, object: panel)
        NotificationCenter.default.post(name: .bublrEndDrag, object: panel, userInfo: ["moved": false])
        workspace.setCollapsed(true, for: .telegram)
        overlay.sync(animated: false)
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        check("a click releases the panel for later layout",
              abs(panel.frame.width - Metrics.collapsedSide) < 1, "\(panel.frame.size)")
        workspace.setCollapsed(false, for: .telegram)
        overlay.sync(animated: false)
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))

            workspace.setVisible(false)
            overlay.updateVisibility()
            check("hide all removes the bubble", !panel.isVisible)
            workspace.setVisible(true)
            overlay.updateVisibility()
            check("show all brings it back", panel.isVisible)
        }
        overlay.stop()
        dragTests()
    }

    // MARK: Drag gesture

    /// Exercises the handle itself: hit-testing through SwiftUI, pointer-following maths and click-vs-drag.
    private func dragTests() {
        let host = NSHostingView(rootView: DragRegion { Color.clear }
            .frame(width: 332, height: 58))
        host.frame = NSRect(x: 0, y: 0, width: 332, height: 58)
        let hitWindow = NSWindow(contentRect: host.frame, styleMask: [.borderless],
                                 backing: .buffered, defer: false)
        hitWindow.contentView = host
        hitWindow.orderBack(nil)
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        let hit = host.hitTest(NSPoint(x: 160, y: 30))
        check("the drag handle wins hit-testing over the header",
              hit is DragHandleView, String(describing: hit.map { type(of: $0) }))
        hitWindow.orderOut(nil)

        let window = NSWindow(contentRect: NSRect(x: 400, y: 400, width: 332, height: 58),
                              styleMask: [.borderless, .nonactivatingPanel],
                              backing: .buffered, defer: false)
        let handle = DragHandleView(frame: NSRect(x: 0, y: 0, width: 332, height: 58))
        window.contentView = handle
        window.orderBack(nil)

        var clicks = 0
        var finished = 0
        handle.onClick = { clicks += 1 }
        let observer = NotificationCenter.default.addObserver(
            forName: .bublrEndDrag, object: window, queue: .main
        ) { note in
            if note.userInfo?["moved"] as? Bool == true { finished += 1 }
        }

        handle.beginDrag(at: NSPoint(x: 500, y: 500))
        handle.continueDrag(to: NSPoint(x: 545, y: 470))
        let moved = window.frame.origin
        check("the bubble follows the pointer while dragging",
              abs(moved.x - 445) < 1 && abs(moved.y - 370) < 1, "\(moved)")
        handle.finishDrag(clickCount: 1)
        check("finishing a drag reports it", finished == 1, "finished=\(finished)")
        check("a drag is not treated as a click", clicks == 0, "clicks=\(clicks)")

        handle.beginDrag(at: NSPoint(x: 500, y: 500))
        handle.continueDrag(to: NSPoint(x: 501, y: 500))
        handle.finishDrag(clickCount: 1)
        check("a press without movement is a click", clicks == 1, "clicks=\(clicks)")


        NotificationCenter.default.removeObserver(observer)
        window.orderOut(nil)
    }

    // MARK: Live web

    private func liveWebTests(completion: @escaping () -> Void) {
        // CI has no business depending on Telegram's, Zalo's or Meta's uptime.
        if ProcessInfo.processInfo.environment["BUBLR_SKIP_LIVE"] != nil {
            print("SKIP  live provider pages (BUBLR_SKIP_LIVE is set)")
            completion()
            return
        }
        let providers: [ProviderID] = [.telegram, .zalo, .messenger]
        let group = DispatchGroup()
        for provider in providers {
            group.enter()
            LivePageProbe.start(provider: provider, timeout: 45) { [weak self] outcome in
                self?.recordLive(provider: provider, outcome: outcome)
                group.leave()
            }
        }
        group.notify(queue: .main) { completion() }
    }

    private func recordLive(provider: ProviderID, outcome: LivePageProbe.Outcome) {
        let spec = provider.spec
        check("\(spec.name): page loaded", outcome.loaded, outcome.error ?? outcome.finalURL)
        let hostOK = outcome.hosts.contains { host in spec.hosts.contains { host == $0 || host.hasSuffix("." + $0) } }
        check("\(spec.name): stayed on a provider host", hostOK || spec.hosts.isEmpty, outcome.hosts.joined(separator: ","))

        var surface = false
        var evidence = "state=\(outcome.authState) canvas=\(outcome.canvas) images=\(outcome.images) password=\(outcome.passwordFields)"
        switch provider {
        case .telegram, .zalo:
            // Both draw the code as SVG/DOM, so presence of a QR surface is the honest signal.
            surface = outcome.hasQRCode
        case .messenger:
            surface = outcome.passwordFields > 0
        default:
            surface = outcome.loaded
        }
        check("\(spec.name): sign-in surface rendered", surface, evidence)
        check("\(spec.name): detector sees a sign-in page", outcome.authState == "signedOut", "state=\(outcome.authState)")
        check("\(spec.name): title reported", !outcome.title.isEmpty, outcome.title)
    }

    private func firstDragHandle(_ view: NSView?) -> DragHandleView? {
        guard let view else { return nil }
        if let handle = view as? DragHandleView { return handle }
        for sub in view.subviews {
            if let handle = firstDragHandle(sub) { return handle }
        }
        return nil
    }

    // MARK: Helpers

    private func temporaryStoreURL(_ name: String) -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("bublr-selftest-\(name)-\(UUID().uuidString)", isDirectory: true)
        return dir.appendingPathComponent("state.json")
    }

    private func summary() {
        print("\n\(passed)/\(passed + failed) checks passed, \(failed) failed")
        let payload: [String: Any] = ["passed": passed, "failed": failed, "checks": results]
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: URL(fileURLWithPath: "/tmp/bublr-selftest.json"))
        }
        exit(failed == 0 ? 0 : 1)
    }
}

// MARK: - Live page probe

final class LivePageProbe: NSObject, WKNavigationDelegate {
    struct Outcome {
        var loaded = false
        var error: String?
        var finalURL = ""
        var hosts: [String] = []
        var title = ""
        var canvas = 0
        var images = 0
        var svgs = 0
        var passwordFields = 0
        var body = ""
        var authState = ""

        /// The page is showing its own QR code (SVG, canvas or a QR-coded element).
        var hasQRCode: Bool {
            if svgs > 0 || canvas > 0 { return true }
            return body.localizedCaseInsensitiveContains("qr")
        }
    }

    private static var active: [LivePageProbe] = []

    private var webView: WKWebView?
    private var window: NSWindow?
    private var completion: ((Outcome) -> Void)?
    private var outcome = Outcome()
    private var providerID: ProviderID = .custom
    private var finished = false
    private var timeoutWork: DispatchWorkItem?

    static func start(provider: ProviderID, timeout: TimeInterval, completion: @escaping (Outcome) -> Void) {
        let probe = LivePageProbe()
        active.append(probe)
        probe.completion = { result in
            active.removeAll { $0 === probe }
            completion(result)
        }
        probe.begin(provider: provider, timeout: timeout)
    }

    private func begin(provider: ProviderID, timeout: TimeInterval) {
        providerID = provider
        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore.nonPersistent()
        config.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 900, height: 700), configuration: config)
        webView.customUserAgent = WebSession.userAgent
        webView.navigationDelegate = self
        self.webView = webView

        // Off-screen host window: real rendering without appearing over the user's work.
        let window = NSWindow(
            contentRect: NSRect(x: -5000, y: -5000, width: 900, height: 700),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = webView
        window.orderBack(nil)
        self.window = window

        var request = URLRequest(url: provider.spec.homeURL)
        request.timeoutInterval = max(10, timeout - 8)
        webView.load(request)

        let work = DispatchWorkItem { [weak self] in
            self?.finish(error: "timed out after \(Int(timeout))s")
        }
        timeoutWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: work)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        outcome.loaded = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 12) { [weak self] in
            self?.inspect()
        }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(error: error.localizedDescription)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(error: error.localizedDescription)
    }

    private func inspect() {
        guard let webView else { return }
        let js = """
        (function () {
          try {
            var text = document.body ? (document.body.innerText || '').replace(/\\s+/g, ' ').slice(0, 400) : '';
            return JSON.stringify({
              title: document.title || '',
              href: location.href,
              host: location.host,
              canvas: document.querySelectorAll('canvas').length,
              svgs: document.querySelectorAll('svg').length,
              images: document.querySelectorAll('img').length,
              password: document.querySelectorAll('input[type=password]').length,
              body: text
            });
          } catch (e) { return JSON.stringify({ error: String(e) }); }
        })()
        """
        webView.evaluateJavaScript(js) { [weak self] value, error in
            guard let self else { return }
            if let error {
                self.finish(error: "DOM probe failed: \(error.localizedDescription)")
                return
            }
            if let string = value as? String,
               let data = string.data(using: .utf8),
               let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                self.outcome.title = dict["title"] as? String ?? ""
                self.outcome.finalURL = dict["href"] as? String ?? ""
                let host = dict["host"] as? String ?? ""
                if !host.isEmpty { self.outcome.hosts = [host] }
                self.outcome.canvas = dict["canvas"] as? Int ?? 0
                self.outcome.images = dict["images"] as? Int ?? 0
                self.outcome.svgs = dict["svgs"] as? Int ?? 0
                self.outcome.passwordFields = dict["password"] as? Int ?? 0
                self.outcome.body = dict["body"] as? String ?? ""
            }
            self.probeAuth()
        }
    }

    private func probeAuth() {
        guard let webView else { return }
        webView.evaluateJavaScript(providerID.spec.authProbeJS) { [weak self] value, _ in
            guard let self else { return }
            if let string = value as? String,
               let data = string.data(using: .utf8),
               let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                self.outcome.authState = dict["state"] as? String ?? ""
            }
            self.finish(error: nil)
        }
    }

    private func finish(error: String?) {
        guard !finished else { return }
        finished = true
        timeoutWork?.cancel()
        if let error { outcome.error = error }
        if outcome.finalURL.isEmpty { outcome.finalURL = webView?.url?.absoluteString ?? "" }
        if outcome.hosts.isEmpty, let host = webView?.url?.host { outcome.hosts = [host] }
        let result = outcome
        completion?(result)
        completion = nil
        webView?.stopLoading()
        window?.orderOut(nil)
        window = nil
        webView = nil
    }
}

// MARK: - DOM probe (developer tool)

/// `Bublr --probe <url> [seconds]` prints the rendered DOM shape of any page using the exact
/// web configuration the app ships, then exits. Used to verify provider sign-in surfaces.
final class DomProbeRunner: NSObject, NSApplicationDelegate {
    private let urlString: String
    private let wait: Double
    private var webView: WKWebView?
    private var window: NSWindow?

    init(urlString: String, wait: Double) {
        self.urlString = urlString
        self.wait = wait
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        guard let url = URL(string: urlString) else { print("bad url"); exit(2) }
        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore.default()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        let controller = WKUserContentController()
        controller.addUserScript(WKUserScript(source: """
        (function(){
          window.__errs = [];
          window.addEventListener('error', function(e){ try { window.__errs.push('error: ' + e.message); } catch(x){} });
          window.addEventListener('unhandledrejection', function(e){ try { window.__errs.push('rejection: ' + e.reason); } catch(x){} });
          try {
            Object.defineProperty(navigator.storage, 'persist', { value: function(){ return Promise.resolve(true); }, configurable: true });
          } catch (e) {}
          var oe = console.error;
          console.error = function(){ try { window.__errs.push(Array.prototype.join.call(arguments, ' ')); } catch(x){}; oe.apply(console, arguments); };
        })();
        """, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        config.userContentController = controller

        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 900, height: 700), configuration: config)
        webView.customUserAgent = ProcessInfo.processInfo.environment["BUBLR_UA"] ?? WebSession.userAgent
        self.webView = webView
        let window = NSWindow(contentRect: NSRect(x: -5000, y: -5000, width: 900, height: 700),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = webView
        window.orderBack(nil)
        self.window = window
        webView.load(URLRequest(url: url))

        DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in
            self?.dump()
        }
    }

    private func dump() {
        let js = """
        (function () {
          try {
            var qr = [];
            document.querySelectorAll('*').forEach(function (el) {
              var c = (el.className && typeof el.className === 'string') ? el.className : '';
              if (/qr/i.test(c) || /qr/i.test(el.id || '')) {
                var r = el.getBoundingClientRect();
                qr.push({ tag: el.tagName, cls: c.slice(0, 80), w: Math.round(r.width), h: Math.round(r.height) });
              }
            });
            return JSON.stringify({
              title: document.title || '',
              href: location.href,
              canvas: document.querySelectorAll('canvas').length,
              svgs: document.querySelectorAll('svg').length,
              images: document.querySelectorAll('img').length,
              svgs: document.querySelectorAll('svg').length,
              iframes: document.querySelectorAll('iframe').length,
              password: document.querySelectorAll('input[type=password]').length,
              text: (document.body ? document.body.innerText : '').replace(/\\s+/g, ' ').slice(0, 1500),
              qr: qr.slice(0, 12),
              errors: (window.__errs || []).slice(0, 8)
            }, null, 2);
          } catch (e) { return JSON.stringify({ error: String(e) }); }
        })()
        """
        if let shotIndex = CommandLine.arguments.firstIndex(of: "--shot"),
           CommandLine.arguments.count > shotIndex + 1 {
            let path = CommandLine.arguments[shotIndex + 1]
            let config = WKSnapshotConfiguration()
            webView?.takeSnapshot(with: config) { image, error in
                if let image, let tiff = image.tiffRepresentation,
                   let rep = NSBitmapImageRep(data: tiff),
                   let png = rep.representation(using: .png, properties: [:]) {
                    try? png.write(to: URL(fileURLWithPath: path))
                    print("snapshot written: \(path) \(image.size)")
                } else {
                    print("snapshot failed: \(String(describing: error))")
                }
            }
        }

        var answered = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 12) {
            if !answered {
                print("{\"error\": \"DOM probe timed out (page main thread busy)\"}")
                exit(3)
            }
        }
        webView?.evaluateJavaScript(js) { value, error in
            answered = true
            if let error { print("probe error: \(error)") }
            if let string = value as? String { print(string) }
            exit(0)
        }
    }
}
