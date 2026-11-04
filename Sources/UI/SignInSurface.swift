import SwiftUI
import AppKit

struct SignInSurface: View {
    @EnvironmentObject var workspace: Workspace
    @EnvironmentObject var sessions: WebSessionStore

    let pending: Workspace.PendingSignIn

    @State private var session: WebSession?
    @State private var method: LoginMethod
    @State private var keepSignedIn: Bool
    @State private var success = false
    @State private var didComplete = false
    @State private var authState: WebSession.AuthState = .unknown

    /// `session` is created on appear, so its state is sampled rather than observed through a wrapper view.
    private let ticker = Timer.publish(every: 0.6, on: .main, in: .common).autoconnect()

    init(pending: Workspace.PendingSignIn) {
        self.pending = pending
        _method = State(initialValue: pending.method)
        _keepSignedIn = State(initialValue: pending.account.keepsSession)
    }

    private var spec: ProviderSpec { pending.account.provider.spec }
    private var providerName: String { spec.name }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                header
                VStack(spacing: 10) {
                    if spec.loginMethods.count > 1 {
                        methodPicker
                    }
                    hintCard
                    keepSignedInRow
                    webCard
                    statusRow
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
                .padding(.top, 8)
            }
            .bubbleBackground(corner: 26, tint: spec.tint)

            if success {
                successOverlay
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .background(WindowAccessor { window in
            if let window {
                NSApp.activate(ignoringOtherApps: true)
                window.makeKey()
            }
        })
        .onAppear(perform: start)
        .onReceive(ticker) { _ in
            authState = session?.authState ?? .unknown
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            SkinnyCloseButton {
                cancel()
            }
            DragRegion {
                HStack(spacing: 10) {
                    BrandMark(provider: pending.account.provider, size: 32)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Link \(providerName)")
                            .font(.bubbleTitle(15))
                        Text("\(pending.account.label) · stays on your Mac")
                            .font(.bubbleCaption(10.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 58)
    }

    // MARK: Method picker

    private var methodPicker: some View {
        HStack(spacing: 6) {
            ForEach(spec.loginMethods, id: \.self) { candidate in
                let selected = candidate == method
                Button {
                    guard !selected else { return }
                    method = candidate
                    workspace.updatePendingSignIn(accountID: pending.account.id, method: candidate)
                    Feedback.tap()
                    session?.beginSignIn(method: candidate)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: candidate.icon)
                            .font(.system(size: 10, weight: .bold))
                        Text(candidate.title)
                            .font(.bubbleCaption(11))
                            .lineLimit(1)
                    }
                    .foregroundStyle(selected ? Color.white : Color.secondary)
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(
                        Capsule().fill(selected ? spec.tint : Color.primary.opacity(0.06))
                    )
                    .overlay(Capsule().strokeBorder(Color.primary.opacity(selected ? 0 : 0.08)))
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }

    /// The only privacy switch in the app: whether the provider's own session cookies are written to disk.
    private var keepSignedInRow: some View {
        VStack(alignment: .leading, spacing: 2) {
            Toggle(isOn: Binding(
                get: { keepSignedIn },
                set: { setKeepSignedIn($0) }
            )) {
                Text("Keep me signed in on this Mac")
                    .font(.bubbleCaption(11))
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            Text(keepSignedIn
                 ? "Bublr saves \(providerName)'s own session cookies — never your password."
                 : "Private session: nothing is written to disk, and you'll sign in again after quitting.")
                .font(.bubbleCaption(9.6))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func setKeepSignedIn(_ value: Bool) {
        keepSignedIn = value
        workspace.setKeepSignedIn(value, for: pending.account.id)
        // Switching storage mode needs a fresh web view, so the page reloads once.
        if !value { sessions.eraseData(accountID: pending.account.id) }
        sessions.drop(accountID: pending.account.id)
        session = nil
        DispatchQueue.main.async { start() }
    }

    private var hintCard: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: method == .qr ? "qrcode.viewfinder" : "lock.shield.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(spec.tint)
                .frame(width: 16)
            Text(spec.loginHint[method] ?? "Sign in using \(providerName)'s own page below.")
                .font(.bubbleCaption(10.8))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(spec.tint.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(spec.tint.opacity(0.16), lineWidth: 1)
        )
    }

    // MARK: Web

    private var webCard: some View {
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
            } else {
                VStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Opening \(providerName)…")
                        .font(.bubbleCaption(10.5))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Status

    private var statusRow: some View {
        HStack(spacing: 8) {
            if success {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.system(size: 12, weight: .bold))
            } else if failed {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.system(size: 11, weight: .bold))
            } else {
                ProgressView()
                    .controlSize(.mini)
            }
            Text(success ? "Signed in" : (failed ? failureText : statusText))
                .font(.bubbleCaption(10.5))
                .foregroundStyle(failed ? Color.orange : Color.secondary)
                .lineLimit(1)
                .help(failed ? failureText : "")
            Spacer(minLength: 4)
            if failed {
                Button("Retry") { session?.reload() }
                    .buttonStyle(.plain)
                    .font(.bubbleCaption(10.5).weight(.semibold))
                    .foregroundStyle(spec.tint)
            } else if !success {
                Button("I've signed in") { complete() }
                    .buttonStyle(.plain)
                    .font(.bubbleCaption(10.5).weight(.semibold))
                    .foregroundStyle(spec.tint)
                    .help("If \(providerName) let you in but Bublr hasn't noticed, continue manually.")
            }
        }
        .frame(height: 18)
    }

    private var failed: Bool { authState == .error }

    private var failureText: String {
        "Can't reach \(providerName) — retry"
    }

    private var statusText: String {
        switch method {
        case .qr:
            return "Waiting for your phone to scan…"
        case .credentials:
            return "Waiting for you to sign in…"
        }
    }

    private var successOverlay: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(spec.tint.opacity(0.16))
                    .frame(width: 64, height: 64)
                Image(systemName: "checkmark")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(spec.tint)
            }
            Text("\(providerName) linked")
                .font(.bubbleTitle(15))
            Text("Opening your chats…")
                .font(.bubbleCaption(11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
    }

    // MARK: Actions

    private func start() {
        guard session == nil else { return }
        let s = sessions.session(for: pending.account, purpose: .signingIn)
        s.onSignedIn = { complete() }
        if s.purpose != .signingIn {
            s.beginSignIn(method: method)
        }
        session = s
        NSApp.activate(ignoringOtherApps: true)
    }

    private func complete() {
        guard !didComplete else { return }
        didComplete = true
        session?.finishSignIn()
        withAnimation(.easeOut(duration: 0.2)) { success = true }
        Feedback.tap()
        workspace.setAccountStatus(id: pending.account.id, status: .connected)
        workspace.clearUnread(accountID: pending.account.id)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.05) {
            workspace.finishSignIn(accountID: pending.account.id)
            if let owner = pending.bubbleID {
                workspace.setDrill(pending.account.id, forBubble: owner)
            } else {
                workspace.setDrill(pending.account.id, for: pending.account.provider)
            }
        }
    }

    private func cancel() {
        session?.purpose = .chatting
        workspace.cancelSignIn(accountID: pending.account.id)
        let owner = pending.bubbleID.flatMap { workspace.bubble(id: $0) }
            ?? workspace.bubble(for: pending.account.provider)
        if let owner, owner.collapsed {
            workspace.setCollapsed(false, forBubble: owner.id)
        }
    }
}

struct SkinnyCloseButton: View {
    var action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(hover ? Color.primary : Color.secondary)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.primary.opacity(hover ? 0.12 : 0.06)))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help("Cancel")
    }
}
