import AppKit
import Carbon.HIToolbox

// MARK: - Menu bar

final class StatusBarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private unowned let app: AppDelegate

    init(app: AppDelegate) {
        self.app = app
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "bubble.left.and.bubble.right.fill",
                                accessibilityDescription: "Bublr")
            image?.isTemplate = true
            button.image = image
            button.toolTip = "Bublr — every chat, floating above your work"
        }

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let toggle = NSMenuItem(
            title: app.workspace.isVisible ? "Hide bubbles" : "Show bubbles",
            action: #selector(toggleBubbles),
            keyEquivalent: "b"
        )
        toggle.keyEquivalentModifierMask = [.option, .command]
        toggle.target = self
        menu.addItem(toggle)

        let collapseAway = NSMenuItem(
            title: "Collapse bubbles when I click away",
            action: #selector(toggleCollapseAway),
            keyEquivalent: ""
        )
        collapseAway.target = self
        collapseAway.state = app.workspace.collapseOnOutsideClick ? .on : .off
        menu.addItem(collapseAway)

        menu.addItem(.separator())

        // Updates sit above settings: an available version is the one item a person should not have to hunt for.
        let updateTitle = app.updates?.availableVersion.map { "Update to Bublr \($0)…" } ?? "Check for Updates…"
        let checkNow = NSMenuItem(title: updateTitle, action: #selector(checkForUpdates), keyEquivalent: "")
        checkNow.target = self
        checkNow.isEnabled = app.updates?.isWorking != true
        menu.addItem(checkNow)

        let autoCheck = NSMenuItem(
            title: "Check for updates automatically",
            action: #selector(toggleAutoCheck),
            keyEquivalent: ""
        )
        autoCheck.target = self
        autoCheck.state = app.workspace.autoCheckForUpdates ? .on : .off
        menu.addItem(autoCheck)

        menu.addItem(.separator())

        let settings = NSMenuItem(title: "Bublr Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        let reset = NSMenuItem(title: "Reset bubble layout", action: #selector(resetLayout), keyEquivalent: "")
        reset.target = self
        menu.addItem(reset)

        menu.addItem(.separator())

        // Which build is this? A menu-bar-only app with no About window cannot answer that otherwise, and
        // "is this the latest?" has already cost a round of confusion caused by stale copies answering to the
        // same bundle id.
        let identity = NSMenuItem(title: buildIdentity, action: nil, keyEquivalent: "")
        identity.isEnabled = false
        menu.addItem(identity)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Bublr", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    /// `Bublr 1.0.0 · 8c2404a`, or without the hash when built from Xcode rather than `make`.
    private var buildIdentity: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "0"
        let commit = (info?["BublrCommit"] as? String ?? "").trimmingCharacters(in: .whitespaces)
        let dev = (info?["CFBundleIdentifier"] as? String ?? "").hasSuffix(".dev") ? " dev" : ""
        return commit.isEmpty ? "Bublr \(version)\(dev)" : "Bublr \(version)\(dev) · \(commit)"
    }

    @objc private func toggleBubbles() { app.toggleBubbles() }

    @objc private func checkForUpdates() {
        // Menu actions arrive on the main thread; the updater is main-actor isolated.
        MainActor.assumeIsolated { app.updates?.checkInteractively() }
    }

    @objc private func toggleAutoCheck() {
        app.workspace.setAutoCheckForUpdates(!app.workspace.autoCheckForUpdates)
    }

    @objc private func toggleCollapseAway() {
        app.workspace.setCollapseOnOutsideClick(!app.workspace.collapseOnOutsideClick)
    }

    @objc private func showSettings() { app.showSettings() }

    @objc private func resetLayout() { app.resetLayout() }

    @objc private func quit() { app.quit() }
}

// MARK: - Global hotkey

/// Registers ⌥⌘B without requiring Accessibility permission (Carbon hot keys are user-level).
final class GlobalHotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let action: () -> Void

    init(key: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        self.action = action

        var hotKeyID = EventHotKeyID(signature: OSType(0x42424C52), id: 1) // 'BBLR'
        RegisterEventHotKey(key, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let opaqueSelf = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData -> OSStatus in
                guard let userData else { return noErr }
                let instance = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async {
                    instance.action()
                }
                return noErr
            },
            1,
            &eventType,
            opaqueSelf,
            &handlerRef
        )
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}
