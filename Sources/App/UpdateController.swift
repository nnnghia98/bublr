import AppKit
import Foundation

/// Drives the update flow: a quiet background check, the menu bar's *Check for Updates…*, and the two alerts a
/// person actually sees.
///
/// The decisions live in `UpdateService`, which is pure apart from its transport. This type only decides when to
/// ask and what to say, so the interesting parts stay testable without a network or a window.
@MainActor
final class UpdateController: ObservableObject {
    /// Set when a newer release is known to exist, so the menu bar can say so without an alert nobody asked for.
    @Published private(set) var availableVersion: String?
    @Published private(set) var isWorking = false

    private let workspace: Workspace
    private var service: UpdateService
    private let installer: UpdateInstalling
    private let relaunch: () -> Void
    private var downloadDirectory: URL

    init(
        workspace: Workspace,
        service: UpdateService? = nil,
        installer: UpdateInstalling = ShellUpdateInstaller(),
        downloadDirectory: URL = FileManager.default.temporaryDirectory,
        relaunch: @escaping () -> Void = { NSApp.terminate(nil) }
    ) {
        self.workspace = workspace
        self.service = service ?? UpdateService()
        self.installer = installer
        self.downloadDirectory = downloadDirectory
        self.relaunch = relaunch
    }

    // MARK: Entry points

    /// The menu item. Always says something: silence after a click reads as a broken menu.
    func checkInteractively() {
        guard !isWorking else { return }
        isWorking = true
        Task { @MainActor in
            defer { isWorking = false }
            do {
                let decision = try await service.check()
                workspace.recordUpdateCheck()
                switch decision {
                case .upToDate(let current):
                    availableVersion = nil
                    alert(title: "Bublr is up to date", message: "\(current) is the newest version.")
                case .unusable(let reason):
                    alert(title: "A newer release cannot be installed", message: reason, style: .warning)
                case .available(let release):
                    availableVersion = release.version
                    offer(release)
                }
            } catch {
                alert(title: "Could not check for updates", message: error.localizedDescription, style: .warning)
            }
        }
    }

    /// The launch check: no alerts, just a menu bar that knows an update exists.
    func checkQuietlyIfDue() {
        guard !isWorking, workspace.shouldCheckForUpdatesQuietly() else { return }
        isWorking = true
        Task { @MainActor in
            defer { isWorking = false }
            guard let decision = try? await service.check() else { return }
            workspace.recordUpdateCheck()
            if case .available(let release) = decision {
                availableVersion = release.version
            } else {
                availableVersion = nil
            }
        }
    }

    // MARK: Flow

    private func offer(_ release: UpdateRelease) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Bublr \(release.version) is available"
        alert.informativeText = Self.summary(release.notes)
        alert.addButton(withTitle: "Install and Relaunch")
        alert.addButton(withTitle: "Later")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        install(release)
    }

    private func install(_ release: UpdateRelease) {
        isWorking = true
        Task { @MainActor in
            defer { isWorking = false }
            do {
                let directory = downloadDirectory.appendingPathComponent("bublr-\(release.version)", isDirectory: true)
                let bundle = try await service.download(release, into: directory)
                try installer.install(candidate: bundle, replacing: Bundle.main.bundleURL)
                // The installer waits for this process to exit before it touches the bundle.
                relaunch()
            } catch {
                availableVersion = release.version
                alert(title: "The update could not be installed", message: error.localizedDescription, style: .warning)
            }
        }
    }

    private func alert(title: String, message: String, style: NSAlert.Style = .informational) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = style
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    /// Release notes are written for GitHub, and an alert is not a web page: keep it readable.
    nonisolated static func summary(_ notes: String, limit: Int = 700) -> String {
        let flattened = notes
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("**Full Changelog**") }
            .map { $0.replacingOccurrences(of: "## ", with: "").replacingOccurrences(of: "- ", with: "• ") }
            .joined(separator: "\n")
        return flattened.count <= limit ? flattened : String(flattened.prefix(limit)) + "…"
    }
}
