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

/// One floating bubble per provider. Its geometry lives here so the overlay can be restored
/// exactly where the user left it.
struct BubbleState: Identifiable, Codable, Equatable {
    var id: ProviderID
    var origin: CGPoint
    var collapsed: Bool = false
    var drilledAccountID: UUID?
    var width: CGFloat = Metrics.bubbleWidth
    var height: CGFloat = Metrics.expandedHeight(accountCount: 0)
    var chatSize: CGSize = CGSize(width: Metrics.chatWidth, height: Metrics.chatHeight)
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

    func bubble(for provider: ProviderID) -> BubbleState? {
        bubbles.first { $0.id == provider }
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
        let index = bubbles.count
        let origin = defaultOrigin(index: index)
        let state = BubbleState(id: provider, origin: origin)
        bubbles.append(state)
        if !isVisible { isVisible = true }
        scheduleSave()
        return state
    }

    func removeBubble(for provider: ProviderID) {
        bubbles.removeAll { $0.id == provider }
        accounts.removeAll { $0.provider == provider }
        pendingSignIns.removeAll { $0.account.provider == provider }
        scheduleSave()
    }

    func setCollapsed(_ collapsed: Bool, for provider: ProviderID) {
        guard let idx = bubbles.firstIndex(where: { $0.id == provider }) else { return }
        bubbles[idx].collapsed = collapsed
        if collapsed { bubbles[idx].drilledAccountID = nil }
        scheduleSave()
    }

    func toggleCollapsed(for provider: ProviderID) {
        guard let bubble = bubble(for: provider) else { return }
        setCollapsed(!bubble.collapsed, for: provider)
    }

    func setDrill(_ accountID: UUID?, for provider: ProviderID) {
        guard let idx = bubbles.firstIndex(where: { $0.id == provider }) else { return }
        bubbles[idx].drilledAccountID = accountID
        if accountID != nil { bubbles[idx].collapsed = false }
        if let id = accountID { clearUnread(accountID: id) }
        scheduleSave()
    }

    func setOrigin(_ origin: CGPoint, for provider: ProviderID) {
        guard let idx = bubbles.firstIndex(where: { $0.id == provider }) else { return }
        guard abs(bubbles[idx].origin.x - origin.x) > 0.5 || abs(bubbles[idx].origin.y - origin.y) > 0.5 else { return }
        bubbles[idx].origin = origin
        scheduleSave()
    }

    func setSize(_ size: CGSize, for provider: ProviderID) {
        guard let idx = bubbles.firstIndex(where: { $0.id == provider }) else { return }
        bubbles[idx].width = size.width
        bubbles[idx].height = size.height
        scheduleSave()
    }

    func setChatSize(_ size: CGSize, for provider: ProviderID) {
        guard let idx = bubbles.firstIndex(where: { $0.id == provider }) else { return }
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
            s.height = Metrics.expandedHeight(accountCount: accounts(for: state.id).count)
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
            if let bubbleIdx = bubbles.firstIndex(where: { $0.id == accounts[idx].provider }),
               bubbles[bubbleIdx].drilledAccountID == accountID {
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

    func beginSignIn(account: Account, method: LoginMethod) {
        pendingSignIns.removeAll { $0.account.id == account.id }
        pendingSignIns.append(PendingSignIn(account: account, method: method, showsChooser: false))
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
