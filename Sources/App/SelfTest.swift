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

        // Per-provider visibility: an empty provider is not on the overlay, and the user can override either way.
        let visURL = temporaryStoreURL("visibility")
        let vis = Workspace(storeURL: visURL)
        vis.addBubble(for: .discord)
        check("asking for a bubble shows it even when empty", vis.isProviderShown(.discord) == true)
        vis.clearProviderVisibility(for: .discord)
        check("an empty provider with no override is hidden", vis.isProviderShown(.discord) == false)
        let visAccount = vis.addAccount(provider: .discord, label: "Gaming")
        check("adding an account brings the provider back", vis.isProviderShown(.discord) == true)
        vis.setProviderVisible(false, for: .discord)
        check("hiding a provider with accounts sticks", vis.isProviderShown(.discord) == false)
        vis.saveNow()
        check("the override survives relaunch",
              Workspace(storeURL: visURL).isProviderShown(.discord) == false)
        vis.setProviderVisible(true, for: .discord)
        vis.removeAccount(id: visAccount.id)
        check("an override keeps an empty provider visible", vis.isProviderShown(.discord) == true)
        vis.clearProviderVisibility(for: .discord)
        check("clearing the override returns to the default", vis.isProviderShown(.discord) == false)
        check("an account added to a hidden provider unhides it",
              { vis.setProviderVisible(false, for: .discord)
                vis.addAccount(provider: .discord, label: "Second")
                return vis.isProviderShown(.discord) }())
        try? FileManager.default.removeItem(at: visURL.deletingLastPathComponent())

        // Clicking away collapses everything at once, and a click that changes nothing is not a change.
        // Uses its own workspace: the checks below count this one's bubbles, and this file's author has
        // already been caught once by leaving a provider behind in shared state.
        let awayURL = temporaryStoreURL("collapse-all")
        let away = Workspace(storeURL: awayURL)
        away.addBubble(for: .telegram)
        away.addBubble(for: .zalo)
        let awayAccount = away.addAccount(provider: .telegram, label: "Work")
        away.setDrill(awayAccount.id, for: .telegram)
        away.setFloating(true, for: awayAccount.id)
        check("collapse all reports the change", away.collapseAll() == true)
        check("collapse all collapses every head",
              away.bubbles.allSatisfy { $0.collapsed },
              "\(away.bubbles.map(\.collapsed))")
        check("collapse all clears the drill",
              away.bubbles.allSatisfy { $0.drilledAccountID == nil })
        check("collapse all collapses a popped-out account",
              away.account(id: awayAccount.id)?.floatingCollapsed == true)
        check("collapse all is idempotent", away.collapseAll() == false)
        try? FileManager.default.removeItem(at: awayURL.deletingLastPathComponent())

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
        check("removing every head of a provider keeps its accounts",
              workspace.bubbles(for: .messenger).isEmpty
                && workspace.accounts(for: .messenger).count == 1,
              "bubbles=\(workspace.bubbles(for: .messenger).count) accounts=\(workspace.accounts(for: .messenger).count)")
        check("adding the provider back returns the same accounts",
              { workspace.addBubble(for: .messenger)
                return workspace.accounts(for: .messenger).count }() == 1)

        // One provider, several heads: same accounts and unread, but never the same web view.
        let head = workspace.addBubble(for: .telegram)
        let twin = workspace.duplicateBubble(id: head.id)
        check("duplicate adds a second head", workspace.bubbles(for: .telegram).count == 2)
        check("duplicate keeps the shared account list", workspace.accounts(for: .telegram).count == 1)
        check("duplicate is offset from its source", twin.map { $0.origin != head.origin } ?? false)
        check("duplicate starts un-drilled", twin?.drilledAccountID == nil)
        if let twin {
            workspace.setDrill(account.id, forBubble: head.id)
            check("head drills its own account", workspace.bubble(id: head.id)?.drilledAccountID == account.id)
            workspace.setDrill(account.id, forBubble: twin.id)
            check("drilling in the twin releases the source head",
                  workspace.bubble(id: head.id)?.drilledAccountID == nil
                    && workspace.bubble(id: twin.id)?.drilledAccountID == account.id)
            workspace.setCollapsed(true, forBubble: twin.id)
            check("collapse is per head",
                  workspace.bubble(id: twin.id)?.collapsed == true
                    && workspace.bubble(id: head.id)?.collapsed == false)
            workspace.removeBubble(id: twin.id)
            check("removing a duplicate keeps the provider and its accounts",
                  workspace.bubbles(for: .telegram).count == 1
                    && workspace.accounts(for: .telegram).count == 1)
            check("removing a duplicate leaves the surviving head as it was",
                  workspace.bubble(id: head.id) != nil
                    && workspace.bubble(id: head.id)?.drilledAccountID == nil)
            // The last head can go too: the accounts outlive it, so the provider can be brought back.
            workspace.removeBubble(id: head.id)
            check("removing the last head keeps the accounts",
                  workspace.bubbles(for: .telegram).isEmpty
                    && workspace.accounts(for: .telegram).count == 1)
            check("the removed head is really gone", workspace.bubble(id: head.id) == nil)
        }

        let catalog = ProviderCatalog.all
        check("catalog covers Telegram, Messenger, Zalo",
              catalog.contains { $0.id == .telegram } && catalog.contains { $0.id == .messenger } && catalog.contains { $0.id == .zalo })
        check("telegram allows QR and password",
              ProviderCatalog.telegramSpec.loginMethods.contains(.qr) && ProviderCatalog.telegramSpec.loginMethods.contains(.credentials))
        check("zalo allows QR", ProviderCatalog.zaloSpec.loginMethods.contains(.qr))
        check("whatsapp is QR-only", ProviderCatalog.whatsappSpec.loginMethods == [.qr])
        check("whatsapp is browser-only", !ProviderCatalog.whatsappSpec.runsInWebKit)
        check("browser-only providers stay out of the catalog", !ProviderCatalog.available.contains { $0.id == .whatsapp })
        // The onboarding copy promised WhatsApp sign-in long after the catalogue dropped it, because the
        // sentence was written by hand. It is derived from the catalogue now.
        let hostable = ProviderCatalog.hostableNames()
        check("the onboarding copy names only hostable providers",
              !hostable.contains("WhatsApp"), hostable)
        check("the onboarding copy counts the rest",
              hostable == "Telegram, Messenger, Zalo, Discord and 3 more", hostable)
        check("every named provider really runs in WebKit",
              ProviderCatalog.available.allSatisfy { $0.id != .whatsapp || !$0.runsInWebKit })
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

        let head = CGSize(width: Metrics.collapsedSide, height: Metrics.collapsedSide)
        let panel = CGSize(width: Metrics.bubbleWidth, height: Metrics.expandedHeight(accountCount: 3))
        check("expanding animates", Motion.duration(from: head, to: panel, reduceMotion: false) == Motion.expandDuration)
        check("collapsing animates", Motion.duration(from: panel, to: head, reduceMotion: false) == Motion.collapseDuration)
        check("collapse is quicker than expand", Motion.collapseDuration < Motion.expandDuration)
        check("Reduce Motion skips the transition",
              Motion.duration(from: head, to: panel, reduceMotion: true) == 0
                && Motion.duration(from: panel, to: head, reduceMotion: true) == 0)
        check("zoom starts at actual size", Zoom.clamped(1) == 1 && Zoom.label(1) == "100%")
        check("zoom clamps at both ends", Zoom.clamped(0.1) == Zoom.min && Zoom.clamped(9) == Zoom.max)
        check("zoom steps by a tenth", Zoom.bigger(1) == 1.1 && Zoom.smaller(1) == 0.9)
        check("a step does not accumulate float dust", Zoom.bigger(1.1) == 1.2 && Zoom.bigger(1.9) == 2.0)
        check("zoom steps stop at the bounds", Zoom.bigger(Zoom.max) == Zoom.max && Zoom.smaller(Zoom.min) == Zoom.min)
        check("zoom reads back as a percentage", Zoom.label(0.95) == "95%" && Zoom.label(Zoom.max) == "200%")
        check("an account from an older file zooms at 100%",
              Account(provider: .telegram, label: "Old").zoom == 1)
        check("growth inside one direction still animates",
              Motion.duration(from: panel,
                             to: CGSize(width: panel.width, height: Metrics.expandedHeight(accountCount: 5)),
                             reduceMotion: false) == Motion.expandDuration)

        anchoringTests()
        resizeTests()
    }

    // MARK: Anchoring

    /// Pure geometry: a 1000x700 screen, a 332x290 head, a 396x648 chat.
    private func anchoringTests() {
        // Room for a 396x648 chat on every side of a 332x290 head, which no real screen has: the point is
        // to check each side on its own before the clamp is allowed to interfere.
        let screen = CGRect(x: 0, y: 0, width: 1600, height: 1700)
        let size = CGSize(width: 396, height: 648)
        let centered = CGRect(x: 600, y: 700, width: 332, height: 290)

        let right = Anchoring.rect(head: centered, size: size, anchor: .right, screen: screen)
        check("a fixed right anchor sits just right of the head",
              right.minX == centered.maxX + Anchoring.gap)
        check("a fixed anchor centres the chat on the head",
              abs(right.midY - centered.midY) < 0.5)

        let left = Anchoring.rect(head: centered, size: size, anchor: .left, screen: screen)
        check("a fixed left anchor sits just left of the head",
              left.maxX == centered.minX - Anchoring.gap)

        let below = Anchoring.rect(head: centered, size: size, anchor: .bottom, screen: screen)
        check("a fixed bottom anchor sits under the head",
              below.maxY == centered.minY - Anchoring.gap)
        check("a fixed anchor is centred across the head",
              abs(below.midX - centered.midX) < 0.5)

        let above = Anchoring.rect(head: centered, size: size, anchor: .top, screen: screen)
        check("a fixed top anchor sits over the head", above.minY == centered.maxY + Anchoring.gap)

        // Automatic: a head parked against the right edge has no room to its right, so it goes left.
        let atRightEdge = CGRect(x: 1268, y: 700, width: 332, height: 290)
        let autoRight = Anchoring.rect(head: atRightEdge, size: size, anchor: .automatic, screen: screen)
        check("automatic avoids a side with no room",
              autoRight.maxX <= atRightEdge.minX && autoRight.maxX > 0)

        // A head with room on both sides prefers the left, which is where `automaticOrder` starts.
        let autoCentered = Anchoring.rect(head: centered, size: size, anchor: .automatic, screen: screen)
        check("automatic prefers the first side that fits",
              autoCentered.maxX == centered.minX - Anchoring.gap)

        // No horizontal room either side: it should go below or above, not off-screen.
        let tallScreen = CGRect(x: 0, y: 0, width: 480, height: 1600)
        let wideHead = CGRect(x: 74, y: 700, width: 332, height: 290)
        let stacked = Anchoring.rect(head: wideHead, size: size, anchor: .automatic, screen: tallScreen)
        check("automatic falls back to above or below",
              (stacked.maxY <= wideHead.minY || stacked.minY >= wideHead.maxY))
        check("...and stays on screen",
              stacked.minX >= tallScreen.minX && stacked.maxX <= tallScreen.maxX
                && stacked.minY >= tallScreen.minY && stacked.maxY <= tallScreen.maxY)

        // A fixed side is honoured even when it clips, then clamped back onto the screen.
        let smallScreen = CGRect(x: 0, y: 0, width: 1000, height: 700)
        let edgeHead = CGRect(x: 668, y: 200, width: 332, height: 290)
        let clipped = Anchoring.rect(head: edgeHead, size: size, anchor: .right, screen: smallScreen)
        check("a fixed side survives clamping", clipped.maxX == smallScreen.maxX)
        check("a fixed side is not swapped for one that fits",
              Anchoring.rect(head: edgeHead, size: size, anchor: .right, screen: smallScreen).maxX
                > edgeHead.maxX - 1)
        check("clamping keeps the chat on screen", clipped.minX >= smallScreen.minX)

        check("a chat taller than the screen is pinned, not shrunk",
              Anchoring.clamp(CGRect(x: -50, y: -50, width: 396, height: 900), to: screen).size.height == 900)
        check("every anchor has a label", ChatAnchor.allCases.allSatisfy { !$0.title.isEmpty })
        check("automatic tries all four sides", Set(ChatAnchor.automaticOrder) == Set([.left, .right, .bottom, .top]))
    }

    // MARK: Resizing

    private func resizeTests() {
        let frame = CGRect(x: 400, y: 300, width: 396, height: 648)
        let minSize = CGSize(width: 360, height: 460)
        let maxSize = CGSize(width: 980, height: 1500)

        let wider = ResizeGeometry.resized(frame, edges: [.right], by: CGSize(width: 60, height: 0),
                                           min: minSize, max: maxSize)
        check("dragging the right edge grows rightwards",
              wider.width == 456 && wider.minX == frame.minX)

        let fromLeft = ResizeGeometry.resized(frame, edges: [.left], by: CGSize(width: -60, height: 0),
                                              min: minSize, max: maxSize)
        check("dragging the left edge keeps the right edge planted",
              fromLeft.width == 456 && fromLeft.maxX == frame.maxX)

        let fromBottom = ResizeGeometry.resized(frame, edges: [.bottom], by: CGSize(width: 0, height: -40),
                                                min: minSize, max: maxSize)
        check("dragging the bottom edge keeps the top edge planted",
              fromBottom.height == 688 && fromBottom.maxY == frame.maxY)

        let fromTop = ResizeGeometry.resized(frame, edges: [.top], by: CGSize(width: 0, height: 40),
                                             min: minSize, max: maxSize)
        check("dragging the top edge keeps the bottom edge planted",
              fromTop.height == 688 && fromTop.minY == frame.minY)

        let corner = ResizeGeometry.resized(frame, edges: [.left, .top], by: CGSize(width: -10, height: 10),
                                           min: minSize, max: maxSize)
        check("a corner drag resizes both axes",
              corner.width == 406 && corner.height == 658 && corner.maxX == frame.maxX && corner.minY == frame.minY)

        let tiny = ResizeGeometry.resized(frame, edges: [.left, .bottom], by: CGSize(width: 900, height: 900),
                                          min: minSize, max: maxSize)
        check("a drag past the floor stops at the minimum",
              tiny.size == minSize && tiny.maxX == frame.maxX && tiny.maxY == frame.maxY)

        let huge = ResizeGeometry.resized(frame, edges: [.right, .top], by: CGSize(width: 4000, height: 4000),
                                          min: minSize, max: maxSize)
        check("a drag past the ceiling stops at the maximum", huge.size == maxSize)

        let rect = CGRect(x: 0, y: 0, width: 400, height: 600)
        check("the middle of a panel is not an edge", ResizeGeometry.edges(at: CGPoint(x: 200, y: 300), in: rect).isEmpty)
        check("a corner grabs two edges",
              ResizeGeometry.edges(at: CGPoint(x: 347, y: 65), in: rect) == [])
        check("the top-left corner grabs both of its edges",
              ResizeGeometry.edges(at: CGPoint(x: 3, y: 597), in: rect) == [.left, .top])
        check("the right edge is grabbable anywhere along it",
              ResizeGeometry.edges(at: CGPoint(x: 397, y: 123), in: rect) == [.right])
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

        // A state file written before `collapseOnOutsideClick` existed must still load, with the new
        // preference taking its default. Synthesised decoding would throw on the missing key, and
        // `Workspace.load()` swallows that — so the failure mode is a silent wipe of every account.
        let oldURL = temporaryStoreURL("old-snapshot")
        let old = Workspace(storeURL: oldURL)
        old.addBubble(for: .telegram)
        old.addAccount(provider: .telegram, label: "Old")
        old.saveNow()
        if let data = try? Data(contentsOf: oldURL),
           var root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            root.removeValue(forKey: "collapseOnOutsideClick")
            try? JSONSerialization.data(withJSONObject: root).write(to: oldURL)
        }
        let upgraded = Workspace(storeURL: oldURL)
        check("state file without the new key still loads", upgraded.accounts.count == 1)
        check("missing preference takes its default", upgraded.collapseOnOutsideClick == true)
        try? FileManager.default.removeItem(at: oldURL.deletingLastPathComponent())

        // Older state files stored the provider itself in a bubble's `id`, because a provider could
        // only ever own one bubble. Those files must still load.
        let legacyURL = temporaryStoreURL("legacy")
        let legacy = Workspace(storeURL: legacyURL)
        legacy.addBubble(for: .discord)
        legacy.addAccount(provider: .discord, label: "Gaming")
        legacy.saveNow()
        if let data = try? Data(contentsOf: legacyURL),
           var root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
           var bubbles = root["bubbles"] as? [[String: Any]], !bubbles.isEmpty {
            bubbles[0]["id"] = "discord"
            bubbles[0].removeValue(forKey: "provider")
            root["bubbles"] = bubbles
            try? JSONSerialization.data(withJSONObject: root).write(to: legacyURL)
        }
        // Anchoring and list height are new keys on `BubbleState`; a file without them must default rather
        // than fail to decode, which `load()` would swallow into an empty workspace.
        let anchorURL = temporaryStoreURL("anchor")
        let anchored = Workspace(storeURL: anchorURL)
        let anchorHead = anchored.addBubble(for: .slack)
        anchored.addAccount(provider: .slack, label: "Work")
        check("a fresh bubble anchors automatically", anchorHead.anchor == .automatic)
        check("a fresh bubble has no dragged height", anchored.bubble(id: anchorHead.id)?.listHeight == nil)
        anchored.setAnchor(.bottom, forBubble: anchorHead.id)
        anchored.setListSize(CGSize(width: 420, height: 560), forBubble: anchorHead.id)
        anchored.saveNow()
        let anchorReloaded = Workspace(storeURL: anchorURL)
        check("the chosen side survives relaunch", anchorReloaded.bubble(id: anchorHead.id)?.anchor == .bottom)
        check("the dragged list height survives relaunch",
              anchorReloaded.bubble(id: anchorHead.id)?.listHeight == 560)
        check("the list width survives relaunch", anchorReloaded.bubble(id: anchorHead.id)?.width == 420)
        check("an old build still sees the resized height",
              anchorReloaded.bubble(id: anchorHead.id)?.height == 560)
        try? FileManager.default.removeItem(at: anchorURL.deletingLastPathComponent())

        let missingURL = temporaryStoreURL("missing-keys")
        let missing = Workspace(storeURL: missingURL)
        missing.addBubble(for: .telegram)
        missing.saveNow()
        if let data = try? Data(contentsOf: missingURL),
           var root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
           var bubbles = root["bubbles"] as? [[String: Any]], !bubbles.isEmpty {
            bubbles[0].removeValue(forKey: "anchor")
            bubbles[0].removeValue(forKey: "listHeight")
            root["bubbles"] = bubbles
            try? JSONSerialization.data(withJSONObject: root).write(to: missingURL)
        }
        let missingLoaded = Workspace(storeURL: missingURL)
        check("a bubble written before anchoring existed still loads",
              missingLoaded.bubbles.count == 1
                && missingLoaded.bubbles[0].anchor == .automatic
                && missingLoaded.bubbles[0].listHeight == nil)
        try? FileManager.default.removeItem(at: missingURL.deletingLastPathComponent())

        // A Debug build must not share the release app's file: both can run at once.
        let releaseURL = Workspace.defaultStoreURL(bundleID: "com.nnnghia.bublr")
        let devURL = Workspace.defaultStoreURL(bundleID: "com.nnnghia.bublr.dev")
        check("release and dev builds keep separate state",
              releaseURL.lastPathComponent == "state.json" && devURL.lastPathComponent == "state.dev.json")

        let migrated = Workspace(storeURL: legacyURL)
        check("legacy bubble id migrates into a provider", migrated.bubbles(for: .discord).count == 1)
        check("migrated bubble keeps its provider's accounts",
              migrated.accounts(for: .discord).count == 1,
              "\(migrated.accounts.count) accounts")
        try? FileManager.default.removeItem(at: legacyURL.deletingLastPathComponent())
    }

    // MARK: Overlay

    private func overlayTests() {
        let workspace = Workspace(storeURL: temporaryStoreURL("overlay"))
        let head = workspace.addBubble(for: .telegram)
        workspace.addAccount(provider: .telegram, label: "QA")
        let sessions = WebSessionStore()
        let overlay = OverlayController(workspace: workspace, sessions: sessions)
        overlay.start()
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))

        let panel = overlay.panel(for: .provider(head.id))
        check("overlay creates one panel per provider bubble", panel != nil)

        // A duplicated head is a real panel of its own, over the same accounts.
        if let twin = workspace.duplicateBubble(id: head.id) {
            overlay.sync(animated: false)
            RunLoop.current.run(until: Date().addingTimeInterval(0.4))
            let twinPanel = overlay.panel(for: .provider(twin.id))
            check("duplicate head gets its own panel", twinPanel != nil && twinPanel !== panel)
            check("duplicate panel uses the bubble geometry",
                  twinPanel.map { abs($0.frame.width - Metrics.bubbleWidth) < 1 } ?? false)
            workspace.removeBubble(id: twin.id)
            overlay.sync(animated: false)
            RunLoop.current.run(until: Date().addingTimeInterval(0.4))
            check("removing the duplicate closes its panel", overlay.panel(for: .provider(twin.id)) == nil)
        }
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

            // #10: the chat is a panel of its own beside the head, not a size the head grows into.
            if let account = workspace.accounts(for: .telegram).first {
                let headBefore = panel.frame
                workspace.setDrill(account.id, forBubble: head.id)
                overlay.sync(animated: false)
                RunLoop.current.run(until: Date().addingTimeInterval(0.5))
                let chat = overlay.panel(for: .chat(head.id))
                check("opening a chat opens a second panel", chat != nil)
                check("the head keeps its size while a chat is open",
                      abs(panel.frame.width - headBefore.width) < 1 && abs(panel.frame.height - headBefore.height) < 1,
                      "head=\(panel.frame.size) was=\(headBefore.size)")
                check("the head stays where it was", abs(panel.frame.origin.x - headBefore.origin.x) < 1)

                if let chat {
                    check("the chat does not overlap its head", !chat.frame.intersects(panel.frame),
                          "head=\(panel.frame) chat=\(chat.frame)")
                    if let visible = NSScreen.screens.first(where: { $0.visibleFrame.intersects(chat.frame) })?.visibleFrame {
                        check("the chat lands on screen",
                              visible.contains(CGPoint(x: chat.frame.minX, y: chat.frame.minY))
                                && visible.contains(CGPoint(x: chat.frame.maxX - 1, y: chat.frame.maxY - 1)))
                    }
                    check("the chat is chat-sized", chat.frame.width >= 360 && chat.frame.height >= 460,
                          "\(chat.frame.size)")

                    // Drag the head: the chat must come with it, on the same side.
                    var movedHead = panel.frame
                    movedHead.origin.x -= 140
                    panel.setFrame(movedHead, display: true)
                    RunLoop.current.run(until: Date().addingTimeInterval(0.3))
                    check("the chat follows its head", !chat.frame.intersects(panel.frame),
                          "head=\(panel.frame) chat=\(chat.frame)")

                    // An edge drag reports a size; the workspace keeps it for the head that owns the chat.
                    NotificationCenter.default.post(name: .bublrBeginDrag, object: chat)
                    var resized = chat.frame
                    resized.size = CGSize(width: 520, height: 700)
                    chat.setFrame(resized, display: true)
                    NotificationCenter.default.post(name: .bublrResizeEnded, object: chat,
                                                    userInfo: ["size": resized.size])
                    NotificationCenter.default.post(name: .bublrEndDrag, object: chat, userInfo: ["moved": true])
                    RunLoop.current.run(until: Date().addingTimeInterval(0.3))
                    check("a resized chat remembers its size",
                          workspace.bubble(id: head.id)?.chatSize == CGSize(width: 520, height: 700),
                          "\(String(describing: workspace.bubble(id: head.id)?.chatSize))")

                    // The web view must follow the frame, not be rebuilt: a resize that reloaded the page
                    // would lose whatever the user was typing.
                    RunLoop.current.run(until: Date().addingTimeInterval(0.5))
                    let liveSession = sessions.existing(accountID: account.id)
                    check("the chat keeps one web view across a resize",
                          liveSession != nil && liveSession?.webView.window === chat,
                          liveSession == nil ? "no session" : "window=\(String(describing: liveSession?.webView.window))")

                    // Same for the account list, which had no handle at all before.
                    NotificationCenter.default.post(name: .bublrBeginDrag, object: panel)
                    var listFrame = panel.frame
                    listFrame.size = CGSize(width: 400, height: 480)
                    panel.setFrame(listFrame, display: true)
                    NotificationCenter.default.post(name: .bublrResizeEnded, object: panel,
                                                    userInfo: ["size": listFrame.size])
                    NotificationCenter.default.post(name: .bublrEndDrag, object: panel, userInfo: ["moved": true])
                    RunLoop.current.run(until: Date().addingTimeInterval(0.3))
                    check("a resized account list remembers its size",
                          workspace.bubble(id: head.id)?.listHeight == 480
                            && workspace.bubble(id: head.id)?.width == 400,
                          "\(String(describing: workspace.bubble(id: head.id)?.listHeight))")
                }

                workspace.setCollapsed(true, forBubble: head.id)
                overlay.sync(animated: false)
                RunLoop.current.run(until: Date().addingTimeInterval(0.4))
                check("collapsing the head closes its chat", overlay.panel(for: .chat(head.id)) == nil)
                workspace.setCollapsed(false, forBubble: head.id)
                overlay.sync(animated: false)
                RunLoop.current.run(until: Date().addingTimeInterval(0.4))
            }
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

        resizeHandleTests()

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

    // MARK: Edge resize gesture

    /// Drives the real `EdgeResizeView`, so the hit-testing, the live frame updates and the notification
    /// that carries the final size are all exercised together.
    private func resizeHandleTests() {
        let frame = NSRect(x: 400, y: 400, width: 396, height: 648)
        let window = NSWindow(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                              backing: .buffered, defer: false)
        let view = EdgeResizeView(frame: NSRect(origin: .zero, size: frame.size))
        view.minSize = CGSize(width: 360, height: 460)
        view.maxSize = CGSize(width: 980, height: 1500)
        window.contentView = view
        window.orderBack(nil)
        view.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))

        check("the middle of a panel is not a resize grip", view.hitTest(NSPoint(x: 198, y: 324)) == nil)
        check("the left edge is a resize grip", view.hitTest(NSPoint(x: 2, y: 324)) === view)

        var reported: CGSize?
        let observer = NotificationCenter.default.addObserver(
            forName: .bublrResizeEnded, object: window, queue: .main
        ) { note in
            reported = note.userInfo?["size"] as? NSSize
        }

        // Grab the left edge and pull it 60pt left: the window grows, its right edge stays put.
        let rightEdge = window.frame.maxX
        view.beginResize(at: NSPoint(x: 2, y: 324), screenPoint: NSPoint(x: frame.minX, y: frame.midY))
        view.continueResize(to: NSPoint(x: frame.minX - 60, y: frame.midY))
        check("the panel grows while the pointer moves",
              abs(window.frame.width - 456) < 1, "\(window.frame.size)")
        check("the opposite edge stays planted",
              abs(window.frame.maxX - rightEdge) < 1, "\(window.frame)")
        view.finishResize()
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        check("the finished size is reported once", reported.map { abs($0.width - 456) < 1 } ?? false,
              String(describing: reported))
        check("a resize with no pointer travel reports nothing new",
              { reported = nil
                view.beginResize(at: NSPoint(x: 2, y: 324), screenPoint: NSPoint(x: 100, y: 100))
                view.finishResize()
                return reported == nil }())
        NotificationCenter.default.removeObserver(observer)
        window.orderOut(nil)
    }

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
