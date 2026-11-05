import AppKit
import SwiftUI
import Combine
import Carbon.HIToolbox

final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject, NSWindowDelegate {
    let workspace = Workspace()
    let sessions = WebSessionStore()
    let objectWillChange = ObservableObjectPublisher()

    private(set) var overlay: OverlayController!
    private var statusBar: StatusBarController!
    private var hotKey: GlobalHotKey?
    private var welcomeWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        sessions.unreadHandler = { [weak self] accountID, count in
            self?.workspace.setUnread(count, for: accountID)
        }

        overlay = OverlayController(workspace: workspace, sessions: sessions)
        overlay.start()

        statusBar = StatusBarController(app: self)
        hotKey = GlobalHotKey(key: UInt32(kVK_ANSI_B), modifiers: UInt32(cmdKey | optionKey)) { [weak self] in
            self?.toggleBubbles()
        }

        if let signInIndex = CommandLine.arguments.firstIndex(of: "--demo-signin") {
            let raw = CommandLine.arguments.count > signInIndex + 1 ? CommandLine.arguments[signInIndex + 1] : "telegram"
            demoSignIn(ProviderID(rawValue: raw) ?? .telegram)
        } else if CommandLine.arguments.contains("--seed-demo") {
            seedDemo()
        } else {
            seedFirstRunIfNeeded()
        }

        if !workspace.hasOnboarded {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.showWelcome()
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// Sign-in fixture: one provider bubble with one fresh account, ready for a real sign-in.
    private func demoSignIn(_ provider: ProviderID) {
        workspace.hasOnboarded = true
        let account = workspace.addAccount(provider: provider, label: "")
        workspace.beginSignIn(account: account, method: provider.spec.defaultMethod)
        workspace.saveNow()
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let head = self?.workspace.bubble(for: provider) else { return }
            self?.overlay.focusDetail(bubbleID: head.id)
        }
    }

    /// Layout fixture for visual QA: real provider bubbles with representative accounts.
    private func seedDemo() {
        workspace.hasOnboarded = true
        let fixtures: [(ProviderID, [(String, Int)])] = [
            (.telegram, [("Work", 4), ("Personal", 0), ("Design team", 12)]),
            (.messenger, [("Nghia Nguyen", 2), ("Studio", 0)]),
            (.zalo, [("Gia đình", 7)])
        ]
        for (provider, accounts) in fixtures {
            workspace.addBubble(for: provider)
            for (name, unread) in accounts {
                let account = workspace.addAccount(provider: provider, label: name)
                workspace.setAccountStatus(id: account.id, status: .connected)
                if unread > 0 { workspace.setUnread(unread, for: account.id) }
            }
        }
        workspace.saveNow()
    }

    func applicationWillTerminate(_ notification: Notification) {
        workspace.saveNow()
    }

    // MARK: First run

    private func seedFirstRunIfNeeded() {
        guard workspace.bubbles.isEmpty, workspace.accounts.isEmpty else { return }
        for provider in [ProviderID.telegram, .messenger, .zalo] {
            workspace.addBubble(for: provider)
        }
        workspace.saveNow()
    }

    // MARK: Actions

    func toggleBubbles() {
        workspace.setVisible(!workspace.isVisible)
        overlay.updateVisibility()
    }

    func showBubbles() {
        if !workspace.isVisible { workspace.setVisible(true) }
        overlay.updateVisibility()
    }

    func hideBubbles() {
        workspace.setVisible(false)
        overlay.updateVisibility()
    }

    func addBubble(_ provider: ProviderID) {
        workspace.addBubble(for: provider)
        showBubbles()
        overlay.sync()
    }

    func removeBubble(_ provider: ProviderID) {
        workspace.removeBubble(for: provider)
        overlay.sync()
    }

    func duplicateBubble(_ provider: ProviderID) {
        guard let head = workspace.bubble(for: provider) else { return }
        workspace.duplicateBubble(id: head.id)
        showBubbles()
        overlay.sync()
    }

    func addAccount(_ provider: ProviderID, method: LoginMethod? = nil) {
        let account = workspace.addAccount(provider: provider, label: "")
        workspace.beginSignIn(account: account, method: method ?? provider.spec.defaultMethod)
        workspace.setAccountStatus(id: account.id, status: .needsSignIn)
        showBubbles()
        overlay.sync()
        closeWelcome()
        if let bubble = workspace.bubble(for: provider) {
            if bubble.collapsed { workspace.setCollapsed(false, forBubble: bubble.id) }
            NSApp.activate(ignoringOtherApps: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                self?.overlay.focusDetail(bubbleID: bubble.id)
            }
        }
    }

    func resetLayout() {
        workspace.resetLayout()
        overlay.sync()
    }

    func quit() {
        workspace.saveNow()
        NSApp.terminate(nil)
    }

    // MARK: Welcome

    func showWelcome() {
        if let window = welcomeWindow {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        let root = WelcomeView()
            .environmentObject(workspace)
            .environmentObject(self)
        let hosting = NSHostingController(rootView: root)
        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.title = "Bublr"
        window.isReleasedWhenClosed = false
        window.backgroundColor = .windowBackgroundColor
        window.delegate = self
        window.setContentSize(NSSize(width: 800, height: 660))
        window.center()
        welcomeWindow = window
        overlay.setHiddenByUser(true)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func closeWelcome() {
        welcomeWindow?.close()
    }

    func windowWillClose(_ notification: Notification) {
        guard (notification.object as? NSWindow) === welcomeWindow else { return }
        welcomeWindow = nil
        workspace.markOnboarded()
        overlay.setHiddenByUser(false)
    }
}

// MARK: - Entry point
func runApp() {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
