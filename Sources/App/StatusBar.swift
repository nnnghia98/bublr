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

        menu.addItem(.separator())

        let addBubble = NSMenuItem(title: "Add provider bubble", action: nil, keyEquivalent: "")
        let addBubbleMenu = NSMenu()
        for provider in ProviderCatalog.available where provider.id != .custom {
            let item = NSMenuItem(title: provider.name, action: #selector(addBubble(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = provider.id.rawValue
            if app.workspace.bubble(for: provider.id) != nil {
                item.state = .on
            }
            addBubbleMenu.addItem(item)
        }
        addBubble.submenu = addBubbleMenu
        menu.addItem(addBubble)

        let addAccount = NSMenuItem(title: "New account…", action: nil, keyEquivalent: "")
        let addAccountMenu = NSMenu()
        for provider in ProviderCatalog.available {
            let item = NSMenuItem(title: provider.name, action: #selector(addAccount(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = provider.id.rawValue
            addAccountMenu.addItem(item)
        }
        addAccount.submenu = addAccountMenu
        menu.addItem(addAccount)

        menu.addItem(.separator())

        let settings = NSMenuItem(title: "Bublr Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        let reset = NSMenuItem(title: "Reset bubble layout", action: #selector(resetLayout), keyEquivalent: "")
        reset.target = self
        menu.addItem(reset)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Bublr", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    @objc private func toggleBubbles() { app.toggleBubbles() }

    @objc private func addBubble(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let id = ProviderID(rawValue: raw) else { return }
        if app.workspace.bubble(for: id) == nil {
            app.addBubble(id)
        } else {
            app.removeBubble(id)
        }
    }

    @objc private func addAccount(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let id = ProviderID(rawValue: raw) else { return }
        app.addAccount(id)
    }

    @objc private func showSettings() { app.showWelcome() }

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
