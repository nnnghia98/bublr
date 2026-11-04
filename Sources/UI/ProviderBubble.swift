import SwiftUI
import AppKit

// MARK: - Root switch

struct ProviderBubbleRoot: View {
    @EnvironmentObject var workspace: Workspace
    let providerID: ProviderID

    var body: some View {
        if !providerID.spec.runsInWebKit {
            UnsupportedProviderCard(provider: providerID)
        } else if let pending = workspace.pendingSignIns.first(where: { $0.account.provider == providerID }) {
            SignInSurface(pending: pending)
                .id(pending.account.id)
        } else if let state = workspace.bubble(for: providerID) {
            if state.collapsed {
                ProviderCollapsedBubble(provider: providerID, unread: workspace.unreadTotal(for: providerID)) {
                    workspace.setCollapsed(false, for: providerID)
                }
            } else if let drill = state.drilledAccountID, workspace.account(id: drill) != nil {
                ChatSurface(accountID: drill, providerID: providerID)
                    .id(drill)
            } else {
                ProviderBubbleList(providerID: providerID)
            }
        } else {
            Color.clear
        }
    }
}

/// Shown for a provider whose web client cannot run inside WebKit (a bubble left over from an older build).
struct UnsupportedProviderCard: View {
    let provider: ProviderID

    var body: some View {
        VStack(spacing: 12) {
            BrandMark(provider: provider, size: 46)
            Text("\(provider.spec.name) needs its own app")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
            Text(provider.spec.unsupportedNote)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                NSWorkspace.shared.open(provider.spec.homeURL)
            } label: {
                Label("Open in browser", systemImage: "safari")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(provider.spec.tint)
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .bubbleBackground()
    }
}

struct FloatingAccountRoot: View {
    @EnvironmentObject var workspace: Workspace
    let accountID: UUID

    var body: some View {
        if let account = workspace.account(id: accountID) {
            if account.floatingCollapsed {
                AccountCollapsedBubble(account: account) {
                    workspace.setFloatingCollapsed(false, for: accountID)
                }
            } else {
                ChatSurface(accountID: accountID, providerID: nil)
            }
        } else {
            Color.clear
        }
    }
}

// MARK: - Collapsed bubbles

struct ProviderCollapsedBubble: View {
    let provider: ProviderID
    let unread: Int
    var onExpand: () -> Void

    @State private var hover = false

    var body: some View {
        ZStack {
            Circle()
                .fill(.regularMaterial)
            Circle()
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.30))
            Circle()
                .strokeBorder(
                    LinearGradient(colors: [.white.opacity(0.5), .white.opacity(0.1)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 1
                )
            BrandMark(provider: provider, size: 40)
                .scaleEffect(hover ? 1.05 : 1)
        }
        .padding(5)
        .overlay(WindowDragHandle(onClick: onExpand))
        .overlay(alignment: .topTrailing) {
            UnreadBadge(count: unread, compact: true)
                .offset(x: 3, y: -1)
        }
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.15), value: hover)
        .help("\(provider.spec.name) — click to open, drag to move")
    }
}

struct AccountCollapsedBubble: View {
    let account: Account
    var onExpand: () -> Void

    var body: some View {
        ZStack {
            Circle().fill(.regularMaterial)
            AccountAvatar(account: account, size: 40)
        }
        .padding(5)
        .overlay(WindowDragHandle(onClick: onExpand))
        .overlay(alignment: .topTrailing) {
            UnreadBadge(count: account.unread, compact: true)
                .offset(x: 3, y: -1)
        }
        .help("\(account.label) — click to open, drag to move")
    }
}

// MARK: - Expanded provider bubble

struct ProviderBubbleList: View {
    @EnvironmentObject var workspace: Workspace
    @EnvironmentObject var sessions: WebSessionStore
    let providerID: ProviderID

    private var spec: ProviderSpec { providerID.spec }
    private var accounts: [Account] { workspace.accounts(for: providerID) }
    private var unread: Int { workspace.unreadTotal(for: providerID) }

    var body: some View {
        VStack(spacing: 0) {
            header
            bodyContent
            footer
        }
        .bubbleBackground(corner: 26, tint: spec.tint)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            DragRegion {
                HStack(spacing: 10) {
                    BrandMark(provider: providerID, size: 36)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 6) {
                            Text(spec.name)
                                .font(.bubbleTitle(15))
                                .lineLimit(1)
                            if unread > 0 { UnreadBadge(count: unread) }
                        }
                        Text(subtitle)
                            .font(.bubbleCaption(10.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
            }
            BubbleIconButton(systemName: "minus.circle", size: 26, help: "Collapse bubble") {
                Feedback.tap()
                workspace.setCollapsed(true, for: providerID)
            }
            BubbleIconButton(systemName: "plus.circle.fill", size: 26, help: "Add another account", tint: spec.tint) {
                addAccount()
            }
        }
        .padding(.horizontal, 12)
        .frame(height: Metrics.header)
    }

    private var subtitle: String {
        if accounts.isEmpty { return "No accounts yet" }
        let base = accounts.count == 1 ? "1 account" : "\(accounts.count) accounts"
        if unread > 0 {
            let unreadText = unread == 1 ? "1 unread" : "\(unread) unread"
            return "\(base) · \(unreadText)"
        }
        return "\(base) · all caught up"
    }

    // MARK: Body

    @ViewBuilder
    private var bodyContent: some View {
        if accounts.isEmpty {
            emptyState
                .padding(.horizontal, Metrics.listPadding)
                .padding(.bottom, 10)
                .padding(.top, 8)
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: Metrics.rowGap) {
                    ForEach(accounts) { account in
                        AccountRow(account: account) {
                            open(account)
                        } onPopOut: {
                            workspace.setFloating(!account.isFloating, for: account.id)
                        } onRename: {
                            Prompt.rename(current: account.label) { newName in
                                workspace.renameAccount(id: account.id, label: newName)
                            }
                        } onKeepSignedIn: {
                            changeKeepSignedIn(for: account)
                        } onSignOut: {
                            signOut(account)
                        } onRemove: {
                            remove(account)
                        }
                    }
                }
                .padding(.horizontal, Metrics.listPadding)
                .padding(.top, 2)
                .padding(.bottom, 4)
            }
            .frame(maxHeight: CGFloat(Metrics.maxVisibleRows) * Metrics.rowHeight
                   + CGFloat(Metrics.maxVisibleRows - 1) * Metrics.rowGap + 6)
            .padding(.bottom, 6)
            .padding(.top, 2)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            BrandMark(provider: providerID, size: 34)
                .opacity(0.9)
            Text("Connect \(spec.shortName)")
                .font(.bubbleTitle(13))
            Text("Link your first account. Bublr opens \(spec.name)'s own sign-in — QR or password, whichever the provider supports.")
                .font(.bubbleCaption(10.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 8)
            Button {
                addAccount()
            } label: {
                Label("Add account", systemImage: "plus")
            }
            .buttonStyle(PrimaryButtonStyle(tint: spec.tint))
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 146)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06))
        )
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 8) {
            Button {
                addAccount()
            } label: {
                Label("Add account", systemImage: "plus")
            }
            .buttonStyle(GhostButtonStyle(tint: spec.tint))

            Spacer()

            Text(accounts.count > 1 ? "\(accounts.count) stacked" : "Drag the top of this bubble")
                .font(.bubbleCaption(9.8))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .frame(height: Metrics.footer)
        .padding(.bottom, 2)
    }

    // MARK: Actions

    private func addAccount() {
        let account = workspace.addAccount(provider: providerID, label: "")
        workspace.beginSignIn(account: account, method: spec.defaultMethod)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func open(_ account: Account) {
        if account.status == .needsSignIn {
            workspace.beginSignIn(account: account, method: spec.defaultMethod)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            workspace.setDrill(account.id, for: providerID)
        }
    }

    /// Toggling always clears the local session, because the storage mode only applies to a new one.
    private func changeKeepSignedIn(for account: Account) {
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

    private func signOut(_ account: Account) {
        Prompt.confirm(
            title: "Sign out of \(account.label)?",
            message: "This clears the local \(spec.name) session for this account. Your \(spec.name) account itself is untouched.",
            action: "Sign out"
        ) {
            sessions.discard(accountID: account.id)
            workspace.signOut(accountID: account.id)
        }
    }

    private func remove(_ account: Account) {
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

// MARK: - Account row

struct AccountRow: View {
    let account: Account
    var onOpen: () -> Void
    var onPopOut: () -> Void
    var onRename: () -> Void
    var onKeepSignedIn: () -> Void
    var onSignOut: () -> Void
    var onRemove: () -> Void

    @State private var hover = false

    private var spec: ProviderSpec { account.provider.spec }

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 10) {
                AccountAvatar(account: account, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(account.label)
                        .font(.bubbleTitle(13))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        StatusDot(color: statusColor)
                        Text(statusText)
                            .font(.bubbleCaption(10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                if account.unread > 0 {
                    UnreadBadge(count: account.unread)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 2)
            }
            .padding(.horizontal, 10)
            .frame(height: Metrics.rowHeight)
            .background(
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .fill(Color.primary.opacity(hover ? 0.09 : 0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .strokeBorder(spec.tint.opacity(hover ? 0.38 : 0.22), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.12), value: hover)
        .contextMenu {
            Button("Open") { onOpen() }
            Button(account.isFloating ? "Dock into \(spec.name)" : "Pop out as bubble") { onPopOut() }
            Button("Rename…") { onRename() }
            Divider()
            Button(account.keepsSession ? "Stop keeping me signed in…" : "Keep me signed in on this Mac…") {
                onKeepSignedIn()
            }
            Button("Sign out and clear session…") { onSignOut() }
            Divider()
            Button("Remove…", role: .destructive) { onRemove() }
        }
    }

    private var statusColor: Color {
        if account.status == .needsSignIn { return .orange }
        return account.unread > 0 ? spec.tint : .green
    }

    private var statusText: String {
        if account.status == .needsSignIn { return "Sign-in needed" }
        if !account.keepsSession { return "Signed in · this session only" }
        if account.unread > 0 { return "\(account.unread) new message\(account.unread == 1 ? "" : "s")" }
        return "Signed in · \(relative(account.lastActivity))"
    }

    private func relative(_ date: Date) -> String {
        let seconds = Date().timeIntervalSince(date)
        if seconds < 60 { return "just now" }
        if seconds < 3600 { return "\(Int(seconds / 60))m ago" }
        if seconds < 86_400 { return "\(Int(seconds / 3600))h ago" }
        return "\(Int(seconds / 86_400))d ago"
    }
}
