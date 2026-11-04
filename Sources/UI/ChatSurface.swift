import SwiftUI
import AppKit

struct ChatSurface: View {
    @EnvironmentObject var workspace: Workspace
    @EnvironmentObject var sessions: WebSessionStore

    let accountID: UUID
    /// `nil` when the chat lives in its own popped-out bubble.
    let providerID: ProviderID?

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
    }

    // MARK: Toolbar

    private func toolbar(_ account: Account, spec: ProviderSpec) -> some View {
        HStack(spacing: 8) {
            if providerID != nil {
                BubbleIconButton(systemName: "chevron.left", size: 26, help: "Back to accounts") {
                    workspace.setDrill(nil, for: account.provider)
                }
            }
            DragRegion {
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
                if let providerID {
                    workspace.setCollapsed(true, for: providerID)
                } else {
                    workspace.setFloatingCollapsed(true, for: account.id)
                }
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 54)
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
        .overlay(alignment: .bottomTrailing) {
            WindowResizeHandle(
                onResize: { _ in },
                onResizeEnd: { size in
                    if let providerID {
                        workspace.setChatSize(size, for: providerID)
                    } else {
                        workspace.setFloatingSize(size, for: account.id)
                    }
                }
            )
            .frame(width: 18, height: 18)
            .padding(4)
            .opacity(0.55)
        }
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
                workspace.beginSignIn(account: account, method: method)
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
