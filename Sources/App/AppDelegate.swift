import AppKit
import SwiftUI
import Combine
import Carbon.HIToolbox

final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject, NSWindowDelegate {
    let workspace = Workspace()
    let sessions = WebSessionStore()
    let objectWillChange = ObservableObjectPublisher()

    private(set) var overlay: OverlayController!
    private(set) var updates: UpdateController!
    private var statusBar: StatusBarController!
    private var hotKey: GlobalHotKey?
    private var settingsWindow: NSWindow?
    /// The provider the settings window shows. Kept here rather than in the view's `@State` because a
    /// bubble or the chat banner may ask for a provider while the window is already open.
    private(set) var settingsProvider: ProviderID?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        sessions.unreadHandler = { [weak self] accountID, count in
            self?.workspace.setUnread(count, for: accountID)
        }

        overlay = OverlayController(workspace: workspace, sessions: sessions)
        overlay.start()

        updates = UpdateController(workspace: workspace)

        statusBar = StatusBarController(app: self)
        hotKey = GlobalHotKey(key: UInt32(kVK_ANSI_B), modifiers: UInt32(cmdKey | optionKey)) { [weak self] in
            self?.toggleBubbles()
        }

        // Quiet check, at most once a day: no alert, just a menu bar entry that knows an update exists.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.updates.checkQuietlyIfDue()
        }

        if let signInIndex = CommandLine.arguments.firstIndex(of: "--demo-signin") {
            let raw = CommandLine.arguments.count > signInIndex + 1 ? CommandLine.arguments[signInIndex + 1] : "telegram"
            demoSignIn(ProviderID(rawValue: raw) ?? .telegram)
        } else if CommandLine.arguments.contains("--seed-demo") {
            seedDemo()
        }

        if !workspace.hasOnboarded {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.showSettings()
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// Sign-in fixture: settings open on one provider with a fresh account waiting for the real page.
    private func demoSignIn(_ provider: ProviderID) {
        workspace.hasOnboarded = true
        let account = workspace.addAccount(provider: provider, label: "")
        workspace.beginSignIn(account: account, method: provider.spec.defaultMethod)
        workspace.saveNow()
        NSApp.activate(ignoringOtherApps: true)
        showSettings(provider: provider)
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

    /// Reveal a provider's bubble and get out of its way: the settings window is where it was arranged.
    func openBubble(_ provider: ProviderID) {
        workspace.addBubble(for: provider)
        workspace.setCollapsed(false, for: provider)
        showBubbles()
        overlay.sync()
        if let head = workspace.bubble(for: provider) {
            overlay.focusDetail(bubbleID: head.id)
        }
        closeSettings()
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

    /// The one way to link an account: add it, then let the settings sheet run the provider's own sign-in.
    func addAccount(_ provider: ProviderID, method: LoginMethod? = nil) {
        let account = workspace.addAccount(provider: provider, label: "")
        workspace.beginSignIn(account: account, method: method ?? provider.spec.defaultMethod)
        showSettings(provider: provider)
    }

    /// Sign an existing account in again — a lapsed session, or a row that never finished signing in.
    func signIn(accountID: UUID) {
        guard let account = workspace.account(id: accountID) else { return }
        workspace.beginSignIn(account: account, method: account.provider.spec.defaultMethod)
        showSettings(provider: account.provider)
    }

    func cancelSignIn(accountID: UUID) {
        sessions.existing(accountID: accountID)?.purpose = .chatting
        workspace.cancelSignIn(accountID: accountID)
    }

    func selectSettingsProvider(_ provider: ProviderID?) {
        guard settingsProvider != provider else { return }
        settingsProvider = provider
        objectWillChange.send()
    }

    func resetLayout() {
        workspace.resetLayout()
        overlay.sync()
    }

    func quit() {
        workspace.saveNow()
        NSApp.terminate(nil)
    }

    /// A bubble panel is hosted with the workspace and sessions only, so its SwiftUI views have no
    /// `AppDelegate` in the environment. These two entry points are how a bubble reaches Settings.
    static func presentSettings(provider: ProviderID? = nil) {
        (NSApp.delegate as? AppDelegate)?.showSettings(provider: provider)
    }

    static func presentSignIn(accountID: UUID) {
        (NSApp.delegate as? AppDelegate)?.signIn(accountID: accountID)
    }

    // MARK: Settings

    func showSettings(provider: ProviderID? = nil) {
        if let provider { selectSettingsProvider(provider) }
        if let window = settingsWindow {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        let root = SettingsView()
            .environmentObject(workspace)
            .environmentObject(sessions)
            .environmentObject(self)
        let hosting = NSHostingController(rootView: root)
        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.title = "Bublr Settings"
        window.isReleasedWhenClosed = false
        window.backgroundColor = .windowBackgroundColor
        window.delegate = self
        window.setContentSize(NSSize(width: 900, height: 660))
        window.center()
        settingsWindow = window
        overlay.setHiddenByUser(true)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func closeSettings() {
        settingsWindow?.close()
    }

    func windowWillClose(_ notification: Notification) {
        guard (notification.object as? NSWindow) === settingsWindow else { return }
        // A sheet cannot outlive its window, so whatever was half-signed-in is cancelled with it.
        for pending in workspace.pendingSignIns {
            cancelSignIn(accountID: pending.account.id)
        }
        settingsWindow = nil
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
