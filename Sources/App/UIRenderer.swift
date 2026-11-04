import SwiftUI
import AppKit

/// Renders the app's real SwiftUI surfaces into PNGs for offline visual review.
/// Used by `--render-ui <dir>`: no screen recording permission, no visible windows.
enum UIRenderer {
    static func run(directory: String) {
        let dir = URL(fileURLWithPath: directory, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let workspace = Workspace(storeURL: dir.appendingPathComponent("render-state.json"))
        let sessions = WebSessionStore()
        workspace.hasOnboarded = true

        _ = workspace.addBubble(for: .telegram)
        let work = workspace.addAccount(provider: .telegram, label: "Work")
        let personal = workspace.addAccount(provider: .telegram, label: "Personal")
        let design = workspace.addAccount(provider: .telegram, label: "Design team")
        for account in [work, personal, design] {
            workspace.setAccountStatus(id: account.id, status: .connected)
        }
        workspace.setUnread(4, for: work.id)
        workspace.setUnread(12, for: design.id)

        _ = workspace.addBubble(for: .messenger)
        let studio = workspace.addAccount(provider: .messenger, label: "Studio")
        workspace.setAccountStatus(id: studio.id, status: .connected)

        _ = workspace.addBubble(for: .zalo)
        let family = workspace.addAccount(provider: .zalo, label: "Gia đình")
        workspace.setAccountStatus(id: family.id, status: .connected)
        workspace.setUnread(7, for: family.id)

        render(ProviderBubbleList(providerID: .telegram)
                .environmentObject(workspace)
                .environmentObject(sessions),
               size: CGSize(width: 332, height: 290), name: "bubble-telegram", dir: dir)

        render(ProviderCollapsedBubble(provider: .zalo, unread: 7, onExpand: {})
                .environmentObject(workspace)
                .environmentObject(sessions),
               size: CGSize(width: 64, height: 64), name: "bubble-collapsed", dir: dir)

        render(ChatSurface(accountID: work.id, providerID: .telegram)
                .environmentObject(workspace)
                .environmentObject(sessions),
               size: CGSize(width: 396, height: 648), name: "chat-telegram", dir: dir)

        var privateAccount = Account(provider: .telegram, label: "Personal")
        privateAccount.keepSignedIn = false
        workspace.beginSignIn(account: privateAccount, method: .qr)
        if let pending = workspace.pendingSignIns.last {
            render(SignInSurface(pending: pending)
                    .environmentObject(workspace)
                    .environmentObject(sessions),
                   size: CGSize(width: 396, height: 648), name: "signin", dir: dir)
        }

        render(WelcomeView()
                .environmentObject(workspace)
                .environmentObject(AppDelegate())
                .frame(width: 860, height: 660),
               size: CGSize(width: 860, height: 660), name: "welcome", dir: dir)

        for spec in ProviderCatalog.all {
            render(BrandMark(provider: spec.id, size: 44)
                    .frame(width: 72, height: 72)
                    .background(Color(white: 0.09)),
                   size: CGSize(width: 72, height: 72), name: "mark-\(spec.id.rawValue)", dir: dir)
        }

        NSLog("BublrRender done \(dir.path)")
        exit(0)
    }

struct MarkSheet: View {
    let providers = ProviderCatalog.all

    var body: some View {
        HStack(spacing: 18) {
            ForEach(providers) { spec in
                BrandMark(provider: spec.id, size: 44)
            }
        }
        .padding(24)
        .background(Color(white: 0.09))
    }
}

    private static func render<Content: View>(_ content: Content, size: CGSize, name: String, dir: URL) {
        let view = NSHostingView(rootView: AnyView(content.frame(width: size.width, height: size.height)))
        view.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = view
        window.orderBack(nil)
        view.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()

        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: dir.appendingPathComponent("\(name).png"))
        window.orderOut(nil)
    }
}
