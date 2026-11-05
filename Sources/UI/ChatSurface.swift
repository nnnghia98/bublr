import SwiftUI
import AppKit

struct ChatSurface: View {
    @EnvironmentObject var workspace: Workspace
    @EnvironmentObject var sessions: WebSessionStore

    let accountID: UUID
    /// `nil` when the chat lives in its own popped-out bubble.
    let providerID: ProviderID?
    /// The head showing this chat, so back/collapse/size land on that head and not on a sibling.
    var bubbleID: UUID? = nil

    private var headID: UUID? {
        if let bubbleID { return bubbleID }
        guard let providerID else { return nil }
        return workspace.bubble(for: providerID)?.id
    }

    @State private var session: WebSession?

    var body: some View {
        Group {
            if let account = workspace.account(id: accountID) {
                content(account)
            } else {
                Color.clear
            }
        }
        .onAppear(perform: prepare)
    }

    private func prepare() {
        guard session == nil, let account = workspace.account(id: accountID) else { return }
        let s = sessions.session(for: account, purpose: .chatting)
        s.onSessionLost = { [workspace] in
            Task { @MainActor in
                workspace.setAccountStatus(id: accountID, status: .needsSignIn)
            }
        }
        session = s
    }

    @ViewBuilder
    private func content(_ account: Account) -> some View {
        let spec = account.provider.spec
        VStack(spacing: 0) {
            toolbar(account, spec: spec)
            webArea(account, spec: spec)
        }
        .bubbleBackground(corner: 26, tint: spec.tint)
        // Any edge, live. A popped-out account answers to a slightly smaller floor than an anchored chat,
        // whose provider pages break well before 360pt.
        .overlay(EdgeResizeHandle(
            minSize: providerID == nil ? CGSize(width: 340, height: 430) : CGSize(width: 360, height: 460),
            maxSize: CGSize(width: 980, height: 1500)
        ))
    }

    // MARK: Toolbar

    private func toolbar(_ account: Account, spec: ProviderSpec) -> some View {
        HStack(spacing: 8) {
            if providerID != nil {
                BubbleIconButton(systemName: "chevron.left", size: 26, help: "Back to accounts") {
                    if let headID {
                        workspace.setDrill(nil, forBubble: headID)
                    } else {
                        workspace.setDrill(nil, for: account.provider)
                    }
                }
            }
            DragRegion(movesHead: headID) {
                HStack(spacing: 8) {
                    AccountAvatar(account: account, size: 28)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(account.label)
                            .font(.bubbleTitle(13))
                            .lineLimit(1)
                        HStack(spacing: 4) {
                            StatusDot(color: account.status == .connected ? .green : .orange)
                            Text(session?.displayHost ?? spec.name)
                                .font(.bubbleCaption(10))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            zoomControls(account)
            BubbleIconButton(systemName: "arrow.clockwise", help: "Reload") {
                session?.reload()
            }
            BubbleIconButton(systemName: "safari", help: "Open in browser") {
                session?.openInBrowser()
            }
            if providerID == nil {
                BubbleIconButton(systemName: "arrow.down.right.and.arrow.up.left", help: "Dock back into \(spec.name)") {
                    workspace.setFloating(false, for: account.id)
                }
            } else {
                BubbleIconButton(systemName: "arrow.up.right.and.arrow.down.left", help: "Pop out as its own bubble") {
                    workspace.setFloating(true, for: account.id)
                }
            }
            BubbleIconButton(systemName: "minus", help: "Collapse to a bubble") {
                if let headID {
                    workspace.setCollapsed(true, forBubble: headID)
                } else if providerID != nil {
                    workspace.setCollapsed(true, for: account.provider)
                } else {
                    workspace.setFloatingCollapsed(true, for: account.id)
                }
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 54)
    }

    /// Three controls rather than a stepper: the percentage in the middle is both the readout and the way
    /// back to 100%, which is the move people actually want after overshooting.
    private func zoomControls(_ account: Account) -> some View {
        HStack(spacing: 2) {
            BubbleIconButton(systemName: "minus.magnifyingglass", size: 24, help: "Zoom out") {
                applyZoom(Zoom.smaller(account.zoom))
            }
            Button {
                applyZoom(1)
            } label: {
                Text(Zoom.label(account.zoom))
                    .font(.bubbleCaption(10).monospacedDigit())
                    .foregroundStyle(account.zoom == 1 ? Color.secondary : Color.primary)
                    .frame(minWidth: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Actual size")
            BubbleIconButton(systemName: "plus.magnifyingglass", size: 24, help: "Zoom in") {
                applyZoom(Zoom.bigger(account.zoom))
            }
        }
    }

    private func applyZoom(_ value: Double) {
        workspace.setPageZoom(value, for: accountID)
        session?.setZoom(value)
    }

    // MARK: Web area

    private func webArea(_ account: Account, spec: ProviderSpec) -> some View {
        ZStack {
            if let session {
                WebViewContainer(webView: session.webView)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
                    )
                    .overlay(alignment: .top) {
                        if session.isLoading {
                            ProgressView(value: max(0.05, session.progress))
                                .progressViewStyle(.linear)
                                .tint(spec.tint)
                                .scaleEffect(x: 1, y: 0.7, anchor: .top)
                        }
                    }
                    .overlay(alignment: .top) {
                        if account.status == .needsSignIn {
                            sessionBanner(account)
                        }
                    }
                    .overlay {
                        if let error = session.loadError, !session.isLoading {
                            errorCard(error, spec: spec)
                        }
                    }
            } else {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 10)
        .padding(.top, 2)
    }

    private func sessionBanner(_ account: Account) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.orange)
            Text("Your session ended")
                .font(.bubbleCaption(11))
                .foregroundStyle(.primary)
            Spacer()
            Button("Sign in again") {
                let method = account.provider.spec.defaultMethod
                sessions.existing(accountID: account.id)?.purpose = .signingIn
                workspace.beginSignIn(account: account, method: method, bubbleID: headID)
            }
            .buttonStyle(.borderless)
            .font(.bubbleCaption(11))
            .foregroundStyle(account.provider.spec.tint)
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.regularMaterial))
        .padding(8)
    }

    private func errorCard(_ message: String, spec: ProviderSpec) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(spec.tint)
            Text("The page didn't load")
                .font(.bubbleTitle(13))
            Text(message)
                .font(.bubbleCaption(10.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .padding(.horizontal, 24)
            Button("Try again") { session?.reload() }
                .buttonStyle(PrimaryButtonStyle(tint: spec.tint))
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.regularMaterial))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
        .padding(20)
    }
}
