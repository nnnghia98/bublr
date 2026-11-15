import SwiftUI
import AppKit

/// The one place a provider is added and an account is linked.
///
/// Bubbles used to carry this too, in a plus button and a per-account menu. Two doors to the same
/// destructive actions made the bubble a settings pane that also showed chats. Now the bubble carries
/// chats only, and everything that changes *what* is linked lives here — including the provider's own
/// sign-in page, which opens as a sheet over this window.
struct SettingsView: View {
    @EnvironmentObject var workspace: Workspace
    @EnvironmentObject var app: AppDelegate

    private var providers: [ProviderSpec] {
        ProviderCatalog.available.filter { $0.id != .custom }
    }

    /// The selection is the app delegate's, not `@State`: opening settings for a provider from a bubble
    /// or the menu bar has to move it, and a view that has already appeared cannot be re-initialised.
    private var selected: ProviderID {
        app.settingsProvider ?? providers.first?.id ?? .telegram
    }

    var body: some View {
        VStack(spacing: 0) {
            hero
            HStack(spacing: 0) {
                sidebar
                Rectangle()
                    .fill(Color.primary.opacity(0.08))
                    .frame(width: 1)
                detail
            }
            footer
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(item: pendingSignIn) { pending in
            SignInSurface(pending: pending, embedded: true)
                .frame(width: 440, height: 640)
        }
    }

    /// One sign-in at a time: the workspace holds the queue, this shows its head. Dismissing the sheet
    /// any other way — Escape, the red button — cancels it, so a half-finished sign-in cannot come back
    /// on the next open.
    private var pendingSignIn: Binding<Workspace.PendingSignIn?> {
        Binding(
            get: { workspace.pendingSignIns.first },
            set: { value in
                guard value == nil, let current = workspace.pendingSignIns.first else { return }
                app.cancelSignIn(accountID: current.account.id)
            }
        )
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
                    .fill(RadialGradient(
                        colors: [Color(hex: 0x2AABEE).opacity(0.55), Color(hex: 0x2AABEE).opacity(0)],
                        center: .center, startRadius: 0, endRadius: 150
                    ))
                    .frame(width: 300, height: 300)
                    .position(x: geo.size.width * 0.72, y: 60)
                Circle()
                    .fill(RadialGradient(
                        colors: [Color(hex: 0xA033FF).opacity(0.48), Color(hex: 0xA033FF).opacity(0)],
                        center: .center, startRadius: 0, endRadius: 140
                    ))
                    .frame(width: 280, height: 280)
                    .position(x: geo.size.width * 0.92, y: 150)
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
        .mask(Rectangle())
    }

    // MARK: Sidebar

    private var sidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                Text("Providers")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .textCase(.uppercase)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 2)
                ForEach(providers) { spec in
                    ProviderSidebarRow(
                        spec: spec,
                        selected: spec.id == selected,
                        accountCount: workspace.accounts(for: spec.id).count,
                        unread: workspace.unreadTotal(for: spec.id),
                        inOverlay: isInOverlay(spec.id)
                    ) {
                        app.selectSettingsProvider(spec.id)
                    }
                }
            }
            .padding(10)
        }
        .frame(width: 244)
        .background(Color.primary.opacity(0.02))
    }

    // MARK: Detail

    private var detail: some View {
        let spec = selected.spec
        let accounts = workspace.accounts(for: spec.id)
        return VStack(alignment: .leading, spacing: 0) {
            detailHeader(spec, accountCount: accounts.count)
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(height: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if accounts.isEmpty {
                        emptyAccounts(spec)
                    } else {
                        HStack(alignment: .firstTextBaseline) {
                            Text(accounts.count == 1 ? "1 account" : "\(accounts.count) accounts")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("Signing out or removing an account clears its local session.")
                                .font(.system(size: 10, weight: .regular, design: .rounded))
                                .foregroundStyle(.tertiary)
                        }
                        ForEach(accounts) { account in
                            AccountSettingsRow(account: account)
                        }
                    }
                    privacyNote(spec)
                }
                .padding(18)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func detailHeader(_ spec: ProviderSpec, accountCount: Int) -> some View {
        let heads = workspace.bubbles(for: spec.id).count
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                BrandMark(provider: spec.id, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(spec.name)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                    Text(spec.tagline)
                        .font(.system(size: 11, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Button {
                    app.addAccount(spec.id)
                } label: {
                    Label("Add account", systemImage: "plus")
                }
                .buttonStyle(PrimaryButtonStyle(tint: spec.tint))
            }

            HStack(spacing: 8) {
                if heads == 0 {
                    Button {
                        app.addBubble(spec.id)
                    } label: {
                        Label("Add bubble", systemImage: "plus.rectangle.on.rectangle")
                    }
                    .buttonStyle(GhostButtonStyle(tint: spec.tint))
                } else {
                    Button {
                        app.openBubble(spec.id)
                    } label: {
                        Label("Show bubble", systemImage: "macwindow")
                    }
                    .buttonStyle(GhostButtonStyle(tint: spec.tint))

                    Menu {
                        Button("Add another bubble") { app.duplicateBubble(spec.id) }
                        if workspace.isProviderShown(spec.id) {
                            Button("Hide this provider's bubble") {
                                workspace.setProviderVisible(false, for: spec.id)
                            }
                        } else {
                            Button("Show this provider's bubble") {
                                workspace.setProviderVisible(true, for: spec.id)
                            }
                        }
                        Divider()
                        Button("Remove every bubble", role: .destructive) {
                            workspace.removeBubble(for: spec.id)
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .frame(width: 26)
                    .help("Bubble options")
                }

                Spacer(minLength: 8)

                Text(bubbleSummary(heads: heads, accountCount: accountCount))
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
    }

    private func bubbleSummary(heads: Int, accountCount: Int) -> String {
        let accounts = accountCount == 1 ? "1 account" : "\(accountCount) accounts"
        if heads == 0 { return "\(accounts) · not in the overlay" }
        if !workspace.isProviderShown(selected) { return "\(accounts) · bubble hidden" }
        return heads == 1 ? "\(accounts) · one bubble" : "\(accounts) · \(heads) bubbles"
    }

    /// A provider is in the overlay when it has a head *and* that head is not hidden. Either alone would
    /// claim a bubble that is not on screen.
    private func isInOverlay(_ provider: ProviderID) -> Bool {
        !workspace.bubbles(for: provider).isEmpty && workspace.isProviderShown(provider)
    }

    private func emptyAccounts(_ spec: ProviderSpec) -> some View {
        VStack(spacing: 8) {
            BrandMark(provider: spec.id, size: 34)
                .opacity(0.9)
            Text("No accounts yet")
                .font(.bubbleTitle(13))
            Text("Link an account and \(spec.name)'s own sign-in page opens here — QR or password, whichever it supports.")
                .font(.bubbleCaption(10.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)
            Button {
                app.addAccount(spec.id)
            } label: {
                Label("Add account", systemImage: "plus")
            }
            .buttonStyle(PrimaryButtonStyle(tint: spec.tint))
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06))
        )
    }

    private func privacyNote(_ spec: ProviderSpec) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(spec.tint)
            VStack(alignment: .leading, spacing: 3) {
                Text("Sign-in is the provider's own")
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                Text("Bublr opens \(spec.name)'s own sign-in page in an isolated session, one per account. Your password never passes through Bublr.")
                    .font(.system(size: 10.5, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(spec.tint.opacity(0.07)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(spec.tint.opacity(0.14)))
        .padding(.top, 4)
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
            Text("Providers, accounts and sign-in live here. A bubble only carries chats.")
                .font(.system(size: 10.5, weight: .regular, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            Button("Done") { app.closeSettings() }
                .buttonStyle(PrimaryButtonStyle(tint: Color(hex: 0x2AABEE)))
        }
        .padding(.horizontal, 24)
        .frame(height: 62)
        .background(.regularMaterial)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1)
        }
    }
}

// MARK: - Sidebar row

private struct ProviderSidebarRow: View {
    let spec: ProviderSpec
    let selected: Bool
    let accountCount: Int
    let unread: Int
    let inOverlay: Bool
    let action: () -> Void

    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                BrandMark(provider: spec.id, size: 24, muted: !inOverlay)
                VStack(alignment: .leading, spacing: 1) {
                    Text(spec.name)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(status)
                        .font(.system(size: 9.6, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 2)
                if unread > 0 {
                    UnreadBadge(count: unread)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 42)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(selected ? spec.tint.opacity(0.16) : Color.primary.opacity(hover ? 0.05 : 0))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(selected ? spec.tint.opacity(0.35) : .clear, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }

    private var status: String {
        guard accountCount > 0 else { return inOverlay ? "no accounts" : "not in the overlay" }
        let accounts = accountCount == 1 ? "1 account" : "\(accountCount) accounts"
        return inOverlay ? accounts : "\(accounts) · hidden"
    }
}

// MARK: - Account row

private struct AccountSettingsRow: View {
    @EnvironmentObject var workspace: Workspace
    @EnvironmentObject var sessions: WebSessionStore
    @EnvironmentObject var app: AppDelegate

    let account: Account

    @State private var hover = false

    private var spec: ProviderSpec { account.provider.spec }

    var body: some View {
        HStack(spacing: 10) {
            AccountAvatar(account: account, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(account.label)
                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                HStack(spacing: 4) {
                    StatusDot(color: account.status == .needsSignIn ? .orange : .green)
                    Text(account.statusText)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            if account.unread > 0 {
                UnreadBadge(count: account.unread)
            }
            if account.status == .needsSignIn {
                Button("Sign in") { app.signIn(accountID: account.id) }
                    .buttonStyle(GhostButtonStyle(tint: spec.tint))
                    .controlSize(.small)
            }
            actions
        }
        .padding(.horizontal, 12)
        .frame(height: 56)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(hover ? 0.07 : 0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(spec.tint.opacity(hover ? 0.30 : 0.12), lineWidth: 1)
        )
        .onHover { hover = $0 }
        .contextMenu { menuItems }
    }

    private var actions: some View {
        Menu {
            menuItems
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 26, height: 26)
                .contentShape(Circle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 26)
        .help("Account options")
    }

    @ViewBuilder
    private var menuItems: some View {
        if account.status == .needsSignIn {
            Button("Sign in…") { app.signIn(accountID: account.id) }
            Divider()
        }
        Button("Rename…") {
            Prompt.rename(current: account.label) { newName in
                workspace.renameAccount(id: account.id, label: newName)
            }
        }
        Button(account.isFloating ? "Dock into a bubble" : "Pop out as its own bubble") {
            workspace.setFloating(!account.isFloating, for: account.id)
        }
        Divider()
        Button(account.keepsSession ? "Stop keeping me signed in…" : "Keep me signed in on this Mac…") {
            changeKeepSignedIn()
        }
        Button("Sign out and clear session…") { signOut() }
        Divider()
        Button("Remove account…", role: .destructive) { remove() }
    }

    /// Toggling always clears the local session, because the storage mode only applies to a new one.
    private func changeKeepSignedIn() {
        let turningOn = !account.keepsSession
        Prompt.confirm(
            title: turningOn ? "Keep \(account.label) signed in?" : "Stop keeping \(account.label) signed in?",
            message: turningOn
                ? "\(spec.name) will be allowed to store its own session cookies on this Mac, so the account survives a restart. Your password is never stored either way."
                : "This clears the local \(spec.name) session for this account. You'll sign in again, and the session will end when Bublr quits.",
            action: turningOn ? "Keep me signed in" : "Sign out"
        ) {
            workspace.setKeepSignedIn(turningOn, for: account.id)
            sessions.discard(accountID: account.id)
            workspace.signOut(accountID: account.id)
        }
    }

    private func signOut() {
        Prompt.confirm(
            title: "Sign out of \(account.label)?",
            message: "This clears the local \(spec.name) session for this account. Your \(spec.name) account itself is untouched.",
            action: "Sign out"
        ) {
            sessions.discard(accountID: account.id)
            workspace.signOut(accountID: account.id)
        }
    }

    private func remove() {
        Prompt.confirm(
            title: "Remove \(account.label)?",
            message: "The account is unlinked from Bublr and its local session is erased. Your \(spec.name) account itself is untouched.",
            action: "Remove"
        ) {
            sessions.discard(accountID: account.id)
            workspace.removeAccount(id: account.id)
        }
    }
}
