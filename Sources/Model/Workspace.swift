import Foundation
import CoreGraphics
import AppKit

// MARK: - Account

enum AccountStatus: String, Codable {
    case needsSignIn
    case connected

    var title: String {
        switch self {
        case .needsSignIn: return "Sign-in needed"
        case .connected: return "Connected"
        }
    }
}

struct Account: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var provider: ProviderID
    var label: String
    var status: AccountStatus = .needsSignIn
    var unread: Int = 0
    var isFloating: Bool = false
    var floatingCollapsed: Bool = false
    var floatingOrigin: CGPoint?
    var floatingSize: CGSize?
    var createdAt: Date = Date()
    var lastActivity: Date = Date()
    var customURL: String?

    /// Opt-in session persistence. When false the provider's cookies live only in memory and are gone
    /// when Bublr quits. `nil` is an account from an older build, which behaved as `true`.
    /// Bublr itself never stores a password, a 2FA code or a QR token either way.
    var keepSignedIn: Bool?

    var keepsSession: Bool { keepSignedIn ?? true }

    var initial: String {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "?" : String(trimmed.prefix(1)).uppercased()
    }
}

// MARK: - Provider bubble

/// One floating head over a provider's account list. A provider can own several heads: they share the
/// same accounts and the same unread count, but each keeps its own geometry, its own collapse state and
/// its own drill target. Only one head at a time may be drilled into a given account, because an
/// account has exactly one `WKWebView` and a view can only live in one window.
struct BubbleState: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var provider: ProviderID
    var origin: CGPoint
    var collapsed: Bool = false
    var drilledAccountID: UUID?
    var width: CGFloat = Metrics.bubbleWidth
    var height: CGFloat = Metrics.expandedHeight(accountCount: 0)
    var chatSize: CGSize = CGSize(width: Metrics.chatWidth, height: Metrics.chatHeight)

    init(provider: ProviderID, origin: CGPoint) {
        self.provider = provider
        self.origin = origin
    }

    private enum CodingKeys: String, CodingKey {
        case id, provider, origin, collapsed, drilledAccountID, width, height, chatSize
    }

    /// State files written when a provider could own only one bubble stored the provider itself in `id`.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let provider = try container.decodeIfPresent(ProviderID.self, forKey: .provider) {
            self.provider = provider
            self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        } else {
            self.provider = try container.decode(ProviderID.self, forKey: .id)
            self.id = UUID()
        }
        origin = try container.decodeIfPresent(CGPoint.self, forKey: .origin) ?? .zero
        collapsed = try container.decodeIfPresent(Bool.self, forKey: .collapsed) ?? false
        drilledAccountID = try container.decodeIfPresent(UUID.self, forKey: .drilledAccountID)
        width = try container.decodeIfPresent(CGFloat.self, forKey: .width) ?? Metrics.bubbleWidth
        height = try container.decodeIfPresent(CGFloat.self, forKey: .height)
            ?? Metrics.expandedHeight(accountCount: 0)
        chatSize = try container.decodeIfPresent(CGSize.self, forKey: .chatSize)
            ?? CGSize(width: Metrics.chatWidth, height: Metrics.chatHeight)
    }
}

// MARK: - Metrics

enum Metrics {
    static let bubbleWidth: CGFloat = 332
    static let chatWidth: CGFloat = 396
    static let chatHeight: CGFloat = 648
    static let collapsedSide: CGFloat = 64
    static let header: CGFloat = 56
    static let listPadding: CGFloat = 10
    static let rowHeight: CGFloat = 62
    static let rowGap: CGFloat = 8
    static let footer: CGFloat = 44

    /// At most five child bubbles are shown at once; more accounts scroll inside the bubble.
    static let maxVisibleRows = 5

    static func expandedHeight(accountCount: Int) -> CGFloat {
        let visible = min(accountCount, maxVisibleRows)
        let body: CGFloat = visible == 0
            ? 152
            : CGFloat(visible) * rowHeight + CGFloat(max(0, visible - 1)) * rowGap
        return listPadding + header + 8 + body + 10 + footer + listPadding
    }

    static func signInHeight() -> CGFloat { 648 }
}

// MARK: - Motion

/// Timing for the overlay's own transitions. Asymmetric on purpose: a bubble that expands slower than it
/// collapses reads as deliberate, where an even 200ms both ways reads as laggy in one direction.
///
/// `duration(from:to:reduceMotion:)` is pure so the policy is testable without a window: the caller passes
/// the accessibility flag rather than this type reading it, because `SelfTest` runs headless.
enum Motion {
    static let expandDuration: TimeInterval = 0.20
    static let collapseDuration: TimeInterval = 0.14

    /// Zero means "do not animate" — the caller sets the frame directly.
    static func duration(from: CGSize, to: CGSize, reduceMotion: Bool) -> TimeInterval {
        guard !reduceMotion else { return 0 }
        let shrinking = to.width * to.height < from.width * from.height
        return shrinking ? collapseDuration : expandDuration
    }

    /// The system setting behind System Settings → Accessibility → Display → Reduce motion.
    static var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
}

// MARK: - Snapshot

struct WorkspaceSnapshot: Codable {
    var accounts: [Account] = []
    var bubbles: [BubbleState] = []
    var visible: Bool = true
    var hasOnboarded: Bool = false
}

// MARK: - Workspace

final class Workspace: ObservableObject {
    @Published private(set) var accounts: [Account] = []
    @Published private(set) var bubbles: [BubbleState] = []
    @Published var isVisible: Bool = true
    @Published var hasOnboarded: Bool = false

    /// Accounts whose sign-in surface is currently open (not yet persisted with a session).
    @Published var pendingSignIns: [PendingSignIn] = []

    private var saveWorkItem: DispatchWorkItem?
    private let storeURL: URL

    struct PendingSignIn: Identifiable, Equatable {
        var id: UUID { account.id }
        var account: Account
        var method: LoginMethod
        var showsChooser: Bool
        /// The head that opened the sign-in. Sibling heads stay out of the way, so one web view can
        /// never be shown twice. `nil` means the provider's first head.
        var bubbleID: UUID?
    }

    init(storeURL: URL? = nil) {
        self.storeURL = storeURL ?? Workspace.defaultStoreURL()
        load()
    }

    nonisolated static func defaultStoreURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Bublr", isDirectory: true).appendingPathComponent("state.json")
    }

    // MARK: Queries

    func accounts(for provider: ProviderID) -> [Account] {
        accounts.filter { $0.provider == provider }
    }

    func bubbles(for provider: ProviderID) -> [BubbleState] {
        bubbles.filter { $0.provider == provider }
    }

    func bubble(id: UUID) -> BubbleState? {
        bubbles.first { $0.id == id }
    }

    /// The provider's first head. The menu bar, the welcome sheet and the sign-in flow act on a
    /// provider rather than on a particular head, so they act here.
    func bubble(for provider: ProviderID) -> BubbleState? {
        bubbles.first { $0.provider == provider }
    }

    func account(id: UUID) -> Account? {
        accounts.first { $0.id == id }
    }

    func accountIndex(id: UUID) -> Int? {
        accounts.firstIndex { $0.id == id }
    }

    func unreadTotal(for provider: ProviderID) -> Int {
        accounts(for: provider).reduce(0) { $0 + $1.unread }
    }

    var totalUnread: Int { accounts.reduce(0) { $0 + $1.unread } }

    var floatingAccounts: [Account] { accounts.filter(\.isFloating) }

    // MARK: Bubbles

    @discardableResult
    func addBubble(for provider: ProviderID) -> BubbleState {
        if let existing = bubble(for: provider) {
            if !isVisible { isVisible = true }
            return existing
        }
        let state = BubbleState(provider: provider, origin: defaultOrigin(index: bubbles.count))
        bubbles.append(state)
        if !isVisible { isVisible = true }
        scheduleSave()
        return state
    }

    /// A second head over the same accounts. It keeps the source geometry, nudged so it does not hide
    /// the original, but starts without a drill: the account's web view stays with the head that owns it.
    @discardableResult
    func duplicateBubble(id: UUID) -> BubbleState? {
        guard let source = bubble(id: id) else { return nil }
        var twin = BubbleState(
            provider: source.provider,
            origin: CGPoint(x: source.origin.x + 28, y: source.origin.y - 28)
        )
        twin.collapsed = source.collapsed
        twin.width = source.width
        twin.height = source.height
        twin.chatSize = source.chatSize
        bubbles.append(twin)
        if !isVisible { isVisible = true }
        scheduleSave()
        return twin
    }

    /// Removes one head. The provider keeps its accounts until its last head goes.
    func removeBubble(id: UUID) {
        guard let state = bubble(id: id) else { return }
        bubbles.removeAll { $0.id == id }
        if bubbles(for: state.provider).isEmpty { forget(provider: state.provider) }
        scheduleSave()
    }

    func removeBubble(for provider: ProviderID) {
        bubbles.removeAll { $0.provider == provider }
        forget(provider: provider)
        scheduleSave()
    }

    private func forget(provider: ProviderID) {
        accounts.removeAll { $0.provider == provider }
        pendingSignIns.removeAll { $0.account.provider == provider }
    }

    func setCollapsed(_ collapsed: Bool, forBubble bubbleID: UUID) {
        guard let idx = bubbles.firstIndex(where: { $0.id == bubbleID }) else { return }
        bubbles[idx].collapsed = collapsed
        if collapsed { bubbles[idx].drilledAccountID = nil }
        scheduleSave()
    }

    func setCollapsed(_ collapsed: Bool, for provider: ProviderID) {
        guard let head = bubble(for: provider) else { return }
        setCollapsed(collapsed, forBubble: head.id)
    }

    func toggleCollapsed(forBubble bubbleID: UUID) {
        guard let bubble = bubble(id: bubbleID) else { return }
        setCollapsed(!bubble.collapsed, forBubble: bubbleID)
    }

    func toggleCollapsed(for provider: ProviderID) {
        guard let bubble = bubble(for: provider) else { return }
        setCollapsed(!bubble.collapsed, forBubble: bubble.id)
    }

    /// Drill is exclusive per account: the account has one web view, so a sibling head that was showing
    /// the same account steps back to its list instead of stealing the view.
    func setDrill(_ accountID: UUID?, forBubble bubbleID: UUID) {
        guard let idx = bubbles.firstIndex(where: { $0.id == bubbleID }) else { return }
        if let accountID {
            let provider = bubbles[idx].provider
            for other in bubbles.indices where other != idx && bubbles[other].drilledAccountID == accountID
                && bubbles[other].provider == provider {
                bubbles[other].drilledAccountID = nil
            }
        }
        bubbles[idx].drilledAccountID = accountID
        if accountID != nil { bubbles[idx].collapsed = false }
        if let id = accountID { clearUnread(accountID: id) }
        scheduleSave()
    }

    func setDrill(_ accountID: UUID?, for provider: ProviderID) {
        guard let head = bubble(for: provider) else { return }
        setDrill(accountID, forBubble: head.id)
    }

    func setOrigin(_ origin: CGPoint, forBubble bubbleID: UUID) {
        guard let idx = bubbles.firstIndex(where: { $0.id == bubbleID }) else { return }
        guard abs(bubbles[idx].origin.x - origin.x) > 0.5 || abs(bubbles[idx].origin.y - origin.y) > 0.5 else { return }
        bubbles[idx].origin = origin
        scheduleSave()
    }

    func setSize(_ size: CGSize, forBubble bubbleID: UUID) {
        guard let idx = bubbles.firstIndex(where: { $0.id == bubbleID }) else { return }
        bubbles[idx].width = size.width
        bubbles[idx].height = size.height
        scheduleSave()
    }

    func setChatSize(_ size: CGSize, forBubble bubbleID: UUID) {
        guard let idx = bubbles.firstIndex(where: { $0.id == bubbleID }) else { return }
        guard abs(bubbles[idx].chatSize.width - size.width) > 0.5 || abs(bubbles[idx].chatSize.height - size.height) > 0.5 else { return }
        bubbles[idx].chatSize = size
        scheduleSave()
    }

    func setFloatingCollapsed(_ collapsed: Bool, for accountID: UUID) {
        guard let idx = accountIndex(id: accountID) else { return }
        accounts[idx].floatingCollapsed = collapsed
        scheduleSave()
    }

    func resetLayout() {
        bubbles = bubbles.enumerated().map { index, state in
            var s = state
            s.origin = defaultOrigin(index: index)
            s.width = Metrics.bubbleWidth
            s.height = Metrics.expandedHeight(accountCount: accounts(for: state.provider).count)
            return s
        }
        for idx in accounts.indices {
            accounts[idx].isFloating = false
            accounts[idx].floatingOrigin = nil
        }
        isVisible = true
        scheduleSave()
    }

    func setVisible(_ visible: Bool) {
        isVisible = visible
        scheduleSave()
    }

    /// Bubbles arrive in a row along the top-right edge and wrap downwards, never covering
    /// each other on first launch.
    private func defaultOrigin(index: Int) -> CGPoint {
        let screen = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let stride = Metrics.bubbleWidth + 16
        let perRow = max(1, Int((screen.width - 60) / stride))
        let row = index / perRow
        let column = index % perRow
        let height = Metrics.expandedHeight(accountCount: 1)
        let x = screen.maxX - Metrics.bubbleWidth - 18 - CGFloat(column) * stride
        let y = screen.maxY - height - 24 - CGFloat(row) * (height + 16)
        return CGPoint(x: x, y: max(screen.minY + 20, y))
    }

    // MARK: Accounts

    @discardableResult
    func addAccount(provider: ProviderID, label: String, customURL: String? = nil) -> Account {
        let existing = accounts(for: provider).count
        let cleaned = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalLabel = cleaned.isEmpty ? "\(provider.spec.shortName) \(existing + 1)" : cleaned
        var account = Account(provider: provider, label: finalLabel)
        account.customURL = customURL
        account.status = .needsSignIn
        accounts.append(account)
        addBubble(for: provider)
        scheduleSave()
        return account
    }

    func updateAccount(_ account: Account) {
        guard let idx = accountIndex(id: account.id) else { return }
        accounts[idx] = account
        scheduleSave()
    }

    func renameAccount(id: UUID, label: String) {
        guard let idx = accountIndex(id: id) else { return }
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        accounts[idx].label = trimmed
        scheduleSave()
    }

    func setKeepSignedIn(_ keep: Bool, for accountID: UUID) {
        guard let index = accountIndex(id: accountID) else { return }
        accounts[index].keepSignedIn = keep
        scheduleSave()
    }

    /// Drops the account back to "sign in again" without unlinking it from the bubble.
    func signOut(accountID: UUID) {
        guard let index = accountIndex(id: accountID) else { return }
        accounts[index].status = .needsSignIn
        accounts[index].unread = 0
        pendingSignIns.removeAll { $0.account.id == accountID }
        bubbles = bubbles.map { state in
            var s = state
            if s.drilledAccountID == accountID { s.drilledAccountID = nil }
            return s
        }
        scheduleSave()
    }

    func setAccountStatus(id: UUID, status: AccountStatus) {
        guard let idx = accountIndex(id: id) else { return }
        accounts[idx].status = status
        if status == .connected { accounts[idx].lastActivity = Date() }
        scheduleSave()
    }

    func setUnread(_ count: Int, for accountID: UUID) {
        guard let idx = accountIndex(id: accountID) else { return }
        guard accounts[idx].unread != count else { return }
        accounts[idx].unread = count
        if count > 0 { accounts[idx].lastActivity = Date() }
        scheduleSave()
    }

    func clearUnread(accountID: UUID) {
        guard let idx = accountIndex(id: accountID) else { return }
        guard accounts[idx].unread != 0 else { return }
        accounts[idx].unread = 0
        scheduleSave()
    }

    func removeAccount(id: UUID) {
        accounts.removeAll { $0.id == id }
        pendingSignIns.removeAll { $0.account.id == id }
        bubbles = bubbles.map { state in
            var s = state
            if s.drilledAccountID == id { s.drilledAccountID = nil }
            return s
        }
        scheduleSave()
    }

    func moveAccount(id: UUID, to provider: ProviderID) {
        guard let idx = accountIndex(id: id) else { return }
        accounts[idx].provider = provider
        accounts[idx].isFloating = false
        addBubble(for: provider)
        scheduleSave()
    }

    // MARK: Floating child bubbles

    func setFloating(_ floating: Bool, for accountID: UUID, origin: CGPoint? = nil) {
        guard let idx = accountIndex(id: accountID) else { return }
        accounts[idx].isFloating = floating
        if floating {
            let base = origin ?? defaultFloatingOrigin()
            accounts[idx].floatingOrigin = base
            accounts[idx].floatingSize = CGSize(width: Metrics.chatWidth, height: Metrics.chatHeight)
            // Every head showing this account has to let go of it: the popped-out panel owns the view now.
            for bubbleIdx in bubbles.indices where bubbles[bubbleIdx].drilledAccountID == accountID {
                bubbles[bubbleIdx].drilledAccountID = nil
            }
        }
        scheduleSave()
    }

    func setFloatingOrigin(_ origin: CGPoint, for accountID: UUID) {
        guard let idx = accountIndex(id: accountID) else { return }
        guard accounts[idx].floatingOrigin != origin else { return }
        accounts[idx].floatingOrigin = origin
        scheduleSave()
    }

    func setFloatingSize(_ size: CGSize, for accountID: UUID) {
        guard let idx = accountIndex(id: accountID) else { return }
        accounts[idx].floatingSize = size
        scheduleSave()
    }

    private func defaultFloatingOrigin() -> CGPoint {
        let screen = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let offset = CGFloat(accounts.filter(\.isFloating).count) * 28
        return CGPoint(
            x: max(screen.minX + 24, screen.midX - Metrics.chatWidth / 2 + offset),
            y: max(screen.minY + 24, screen.midY - Metrics.chatHeight / 2 - offset)
        )
    }

    // MARK: Pending sign-in

    func beginSignIn(account: Account, method: LoginMethod, bubbleID: UUID? = nil) {
        pendingSignIns.removeAll { $0.account.id == account.id }
        pendingSignIns.append(
            PendingSignIn(account: account, method: method, showsChooser: false, bubbleID: bubbleID)
        )
    }

    func updatePendingSignIn(accountID: UUID, method: LoginMethod? = nil, showsChooser: Bool? = nil) {
        guard let idx = pendingSignIns.firstIndex(where: { $0.account.id == accountID }) else { return }
        if let method { pendingSignIns[idx].method = method }
        if let showsChooser { pendingSignIns[idx].showsChooser = showsChooser }
    }

    func finishSignIn(accountID: UUID) {
        pendingSignIns.removeAll { $0.account.id == accountID }
    }

    func cancelSignIn(accountID: UUID) {
        finishSignIn(accountID: accountID)
    }

    // MARK: Persistence

    private func load() {
        guard let data = try? Data(contentsOf: storeURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let snapshot = try? decoder.decode(WorkspaceSnapshot.self, from: data) else { return }
        accounts = snapshot.accounts
        bubbles = snapshot.bubbles
        isVisible = snapshot.visible
        hasOnboarded = snapshot.hasOnboarded
        // Recover any bubble that lost its geometry.
        for (index, state) in bubbles.enumerated() where state.origin == .zero {
            bubbles[index].origin = defaultOrigin(index: index)
        }
    }

    func saveNow() {
        saveWorkItem?.cancel()
        let snapshot = WorkspaceSnapshot(
            accounts: accounts,
            bubbles: bubbles,
            visible: isVisible,
            hasOnboarded: hasOnboarded
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let url = storeURL
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try encoder.encode(snapshot)
            try data.write(to: url, options: .atomic)
        } catch {
            NSLog("Bublr: could not save state — \(error)")
        }
    }

    private func scheduleSave() {
        saveWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            Task { @MainActor in self?.saveNow() }
        }
        saveWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: item)
    }

    // MARK: Onboarding

    func markOnboarded() {
        hasOnboarded = true
        scheduleSave()
    }
}
