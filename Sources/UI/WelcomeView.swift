import SwiftUI
import AppKit

struct WelcomeView: View {
    @EnvironmentObject var workspace: Workspace
    @EnvironmentObject var app: AppDelegate

    private let columns = [GridItem(.flexible(), spacing: 12),
                           GridItem(.flexible(), spacing: 12),
                           GridItem(.flexible(), spacing: 12)]

    private var providers: [ProviderSpec] {
        ProviderCatalog.available.filter { $0.id != .custom }
    }

    var body: some View {
        VStack(spacing: 0) {
            hero
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    sectionHeader
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(providers) { spec in
                            ProviderCard(
                                spec: spec,
                                bubbleExists: workspace.bubble(for: spec.id) != nil,
                                accountCount: workspace.accounts(for: spec.id).count,
                                unread: workspace.unreadTotal(for: spec.id),
                                onOpen: { openBubble(spec.id) },
                                onAddAccount: { app.addAccount(spec.id) }
                            )
                        }
                    }
                    callout
                }
                .padding(.horizontal, 24)
                .padding(.top, 18)
                .padding(.bottom, 20)
            }
            footer
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: Hero

    private var hero: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: 0x11233A), Color(hex: 0x1B1440), Color(hex: 0x0C1524)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            GeometryReader { geo in
                Circle()
                    .fill(Color(hex: 0x2AABEE).opacity(0.35))
                    .frame(width: 220, height: 220)
                    .blur(radius: 60)
                    .offset(x: geo.size.width * 0.62, y: -60)
                Circle()
                    .fill(Color(hex: 0xA033FF).opacity(0.30))
                    .frame(width: 200, height: 200)
                    .blur(radius: 70)
                    .offset(x: geo.size.width * 0.85, y: 70)
            }
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(
                            LinearGradient(colors: [Color(hex: 0x63C7FF), Color(hex: 0x7C5CFF)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .frame(width: 64, height: 64)
                        .shadow(color: Color(hex: 0x2AABEE).opacity(0.5), radius: 18, y: 8)
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.system(size: 27, weight: .semibold))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text("Bublr")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Every chat, floating above your work.")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.72))
                }
                Spacer()
                HStack(spacing: 6) {
                    Image(systemName: "keyboard")
                    Text("⌥⌘B hides all")
                }
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(Capsule().fill(.white.opacity(0.12)))
                .overlay(Capsule().strokeBorder(.white.opacity(0.18)))
            }
            .padding(.horizontal, 26)
        }
        .frame(height: 150)
    }

    // MARK: Sections

    private var sectionHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Your bubbles")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                Text("Each provider gets one bubble in the overlay. Open it to stack as many accounts as you need.")
                    .font(.system(size: 11.5, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                workspace.setVisible(!workspace.isVisible)
            } label: {
                Label(workspace.isVisible ? "Hide overlay" : "Show overlay", systemImage: workspace.isVisible ? "eye.slash" : "eye")
            }
            .buttonStyle(GhostButtonStyle())
        }
    }

    private var callout: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color(hex: 0x2AABEE))
            VStack(alignment: .leading, spacing: 3) {
                Text("Sign-in is the provider's own")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                Text("Bublr opens the real Telegram, Messenger, Zalo, WhatsApp or Discord sign-in page in an isolated session per account. QR codes work wherever the provider supports them, and your password never passes through Bublr.")
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(hex: 0x2AABEE).opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color(hex: 0x2AABEE).opacity(0.16))
        )
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
            Text("Drag a bubble by its header. Click a collapsed bubble to expand it. Right-click an account for more.")
                .font(.system(size: 10.5, weight: .regular, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            Button("Done") { app.closeWelcome() }
                .buttonStyle(PrimaryButtonStyle(tint: Color(hex: 0x2AABEE)))
        }
        .padding(.horizontal, 24)
        .frame(height: 62)
        .background(.regularMaterial)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1)
        }
    }

    // MARK: Actions

    private func openBubble(_ provider: ProviderID) {
        app.addBubble(provider)
        workspace.setCollapsed(false, for: provider)
        workspace.setVisible(true)
        app.closeWelcome()
    }
}

private struct ProviderCard: View {
    let spec: ProviderSpec
    let bubbleExists: Bool
    let accountCount: Int
    let unread: Int
    let onOpen: () -> Void
    let onAddAccount: () -> Void

    @State private var hover = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                BrandMark(provider: spec.id, size: 26)
                VStack(alignment: .leading, spacing: 0) {
                    Text(spec.name)
                        .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                    Text(statusText)
                        .font(.system(size: 9.8, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if bubbleExists {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(spec.tint)
                }
            }

            Text(spec.tagline)
                .font(.system(size: 10.2, weight: .regular, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(height: 28, alignment: .topLeading)

            HStack(spacing: 6) {
                Button(bubbleExists ? "Open" : "Add bubble") { onOpen() }
                    .buttonStyle(GhostButtonStyle(tint: spec.tint))
                    .controlSize(.small)
                if bubbleExists {
                    Button {
                        onAddAccount()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(GhostButtonStyle(tint: spec.tint))
                    .help("Link another account")
                }
                Spacer(minLength: 0)
            }
        }
        .padding(11)
        .frame(height: 132)
        .background(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(Color.primary.opacity(hover ? 0.075 : 0.045))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(spec.tint.opacity(hover ? 0.35 : 0.16), lineWidth: 1)
        )
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.12), value: hover)
    }

    private var statusText: String {
        if !bubbleExists { return "not in overlay" }
        if accountCount == 0 { return "bubble · no accounts" }
        if unread > 0 {
            let accountsText = accountCount == 1 ? "1 account" : "\(accountCount) accounts"
            let unreadText = unread == 1 ? "1 unread" : "\(unread) unread"
            return "\(accountsText) · \(unreadText)"
        }
        return accountCount == 1 ? "1 account linked" : "\(accountCount) accounts linked"
    }
}
