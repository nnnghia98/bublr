import SwiftUI
import AppKit

// MARK: - Root switch

struct ProviderBubbleRoot: View {
    @EnvironmentObject var workspace: Workspace
    let providerID: ProviderID
    /// The head this panel shows. `nil` means the provider's first head, which is what older call
    /// sites and the offline renderer expect.
    var bubbleID: UUID? = nil

    private var headID: UUID? { bubbleID ?? workspace.bubble(for: providerID)?.id }
    private var state: BubbleState? { headID.flatMap { workspace.bubble(id: $0) } }

    var body: some View {
        if !providerID.spec.runsInWebKit {
            UnsupportedProviderCard(provider: providerID)
        } else if let state, let headID {
            if state.collapsed {
                ProviderCollapsedBubble(provider: providerID, unread: workspace.unreadTotal(for: providerID)) {
                    workspace.setCollapsed(false, forBubble: headID)
                }
            } else {
                ProviderBubbleList(providerID: providerID, bubbleID: headID)
            }
        } else {
            Color.clear
        }
    }
}

/// The panel beside the head: a chat, and only a chat.
///
/// Separate from `ProviderBubbleRoot` on purpose. The head used to grow into the chat and shrink back,
/// which cost it its own identity — badge, name, the thing you were dragging — for as long as a chat was
/// open. Now the head stays put and this opens next to it.
///
/// Sign-in used to borrow this panel too. It lives in the settings window now, so a half-finished sign-in
/// can never take over a bubble that is meant to show conversations.
struct ChatPanelRoot: View {
    @EnvironmentObject var workspace: Workspace
    let providerID: ProviderID
    let bubbleID: UUID

    var body: some View {
        if !providerID.spec.runsInWebKit {
            UnsupportedProviderCard(provider: providerID)
        } else if let drill = workspace.bubble(id: bubbleID)?.drilledAccountID,
                  workspace.account(id: drill) != nil {
            ChatSurface(accountID: drill, providerID: providerID, bubbleID: bubbleID)
                .id(drill)
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
        .collapsedBubbleAccessibility(name: provider.spec.name, unread: unread, open: onExpand)
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
        .collapsedBubbleAccessibility(name: account.label, unread: account.unread, open: onExpand)
    }
}

// MARK: - Expanded provider bubble

struct ProviderBubbleList: View {
    @EnvironmentObject var workspace: Workspace
    let providerID: ProviderID
    var bubbleID: UUID? = nil

    private var headID: UUID? { bubbleID ?? workspace.bubble(for: providerID)?.id }
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
        // Any edge, live: the panel grows as the pointer moves and the size is stored when the drag ends.
        .overlay(EdgeResizeHandle(
            minSize: CGSize(width: 292, height: Metrics.expandedHeight(accountCount: 0)),
            maxSize: CGSize(width: 980, height: 1500)
        ))
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
                if let headID { workspace.setCollapsed(true, forBubble: headID) }
            }
        }
        .padding(.horizontal, 12)
        .frame(height: Metrics.header)
        .contextMenu {
            Button("Duplicate bubble") { duplicateHead() }
            Button("Collapse bubble") {
                if let headID { workspace.setCollapsed(true, forBubble: headID) }
            }
            Divider()
            Menu("Chat opens") {
                ForEach(ChatAnchor.allCases, id: \.self) { option in
                    Button {
                        if let headID { workspace.setAnchor(option, forBubble: headID) }
                    } label: {
                        Text(currentAnchor == option ? "✓ \(option.title)" : option.title)
                    }
                }
            }
            Divider()
            Button("Manage accounts in Settings…") { openSettings() }
            // Hiding and removing providers belong to Settings, where a provider is added. What is left
            // here is the pair of window actions a second head needs: make one, retire one.
            if workspace.bubbles(for: providerID).count > 1 {
                Button("Remove this bubble", role: .destructive) { removeHead() }
            }
        }
    }

    private var currentAnchor: ChatAnchor {
        headID.flatMap { workspace.bubble(id: $0)?.anchor } ?? .automatic
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

    /// A bubble with nothing to show says where accounts come from now, instead of opening a sign-in page
    /// in a window that is meant to carry conversations.
    private var emptyState: some View {
        VStack(spacing: 8) {
            BrandMark(provider: providerID, size: 34)
                .opacity(0.9)
            Text("No \(spec.shortName) chats yet")
                .font(.bubbleTitle(13))
            Text("Add an account in Bublr Settings. Its chats appear here, and the provider's own sign-in page opens there.")
                .font(.bubbleCaption(10.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 8)
            Button {
                openSettings()
            } label: {
                Label("Open Bublr Settings", systemImage: "gearshape")
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
                openSettings()
            } label: {
                Label("Manage in Settings…", systemImage: "gearshape")
            }
            .buttonStyle(GhostButtonStyle(tint: spec.tint))

            Spacer()

            Text(accounts.count > 1 ? "\(accounts.count) accounts" : "Drag the top of this bubble")
                .font(.bubbleCaption(9.8))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .frame(height: Metrics.footer)
        .padding(.bottom, 2)
    }

    // MARK: Actions

    /// A row that has nothing to show yet goes to the one place that can sign it in.
    private func open(_ account: Account) {
        if account.status == .needsSignIn {
            AppDelegate.presentSignIn(accountID: account.id)
        } else if let headID {
            workspace.setDrill(account.id, forBubble: headID)
        }
    }

    private func openSettings() {
        AppDelegate.presentSettings(provider: providerID)
    }

    /// Retires this head only. The accounts and the duplicate's siblings are untouched.
    private func removeHead() {
        guard let headID else { return }
        workspace.removeBubble(id: headID)
    }

    /// A second head over the same accounts, for watching two chats side by side.
    private func duplicateHead() {
        guard let headID, workspace.duplicateBubble(id: headID) != nil else { return }
        Feedback.tap()
    }
}

// MARK: - Account row

/// One chat, as the bubble lists it. Opening and popping out are the only things a bubble does with an
/// account; everything that changes the account lives in Settings.
struct AccountRow: View {
    let account: Account
    var onOpen: () -> Void
    var onPopOut: () -> Void

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
                        Text(account.statusText)
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
        }
    }

    private var statusColor: Color {
        if account.status == .needsSignIn { return .orange }
        return account.unread > 0 ? spec.tint : .green
    }
}
