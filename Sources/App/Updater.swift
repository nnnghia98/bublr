import Foundation
import AppKit
import CryptoKit

// MARK: - Version comparison

/// Compares release versions the way a person reads them: `1.10.0` is newer than `1.9.0`, and `2.0.0` is newer
/// than `2.0.0-beta`.
///
/// Deliberately not a full SemVer parser. Release tags here are `v1.0.0`, and a stray suffix must never make an
/// update look newer than it is: anything non-numeric is treated as a prerelease marker, which loses to the
/// release with the same numbers.
enum SemanticVersion {
    static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let a = parts(lhs)
        let b = parts(rhs)
        for index in 0..<max(a.numbers.count, b.numbers.count) {
            let left = index < a.numbers.count ? a.numbers[index] : 0
            let right = index < b.numbers.count ? b.numbers[index] : 0
            if left != right { return left < right ? .orderedAscending : .orderedDescending }
        }
        if a.prerelease == b.prerelease { return .orderedSame }
        // Same numbers: the one with a suffix is the earlier build.
        return a.prerelease ? .orderedAscending : .orderedDescending
    }

    static func isNewer(_ candidate: String, than current: String) -> Bool {
        compare(candidate, current) == .orderedDescending
    }

    private static func parts(_ version: String) -> (numbers: [Int], prerelease: Bool) {
        let trimmed = version.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
        var numbers: [Int] = []
        var prerelease = false
        for (index, chunk) in trimmed.split(separator: ".").enumerated() {
            let digits = chunk.prefix { $0.isNumber }
            if let value = Int(digits), !digits.isEmpty {
                numbers.append(value)
                // `1.0.0-beta` keeps its numbers and only the tail decides.
                if digits.count < chunk.count, index >= 0 { prerelease = true }
            } else {
                prerelease = true
            }
        }
        return (numbers, prerelease)
    }
}

// MARK: - Feed

/// The subset of a GitHub release this app needs.
struct GitHubRelease: Decodable, Equatable {
    struct Asset: Decodable, Equatable {
        let name: String
        let url: URL
        let size: Int

        private enum CodingKeys: String, CodingKey {
            case name
            case url = "browser_download_url"
            case size
        }
    }

    let tag: String
    let body: String?
    let publishedAt: String?
    let assets: [Asset]

    private enum CodingKeys: String, CodingKey {
        case tag = "tag_name"
        case body
        case publishedAt = "published_at"
        case assets
    }
}

/// A release that can actually be installed: the archive, and the checksums that make downloading it safe.
struct UpdateRelease: Equatable {
    let version: String
    let notes: String
    let zipURL: URL
    let checksumsURL: URL?

    static let zipPrefix = "Bublr-"
    static let checksumsName = "SHA256SUMS"
}

enum UpdateDecision: Equatable {
    case upToDate(current: String)
    case available(UpdateRelease)
    /// A newer release exists but cannot be installed safely; the reason is shown to the user as-is.
    case unusable(String)
}

enum UpdateError: LocalizedError, Equatable {
    case noArchive(version: String)
    case noChecksum(version: String)
    case badChecksum(expected: String, actual: String)
    case badArchive(String)
    case versionMismatch(expected: String, actual: String)
    case network(String)

    var errorDescription: String? {
        switch self {
        case .noArchive(let version):
            return "The release \(version) has no Bublr archive to download."
        case .noChecksum(let version):
            return "The release \(version) has no SHA256SUMS, so the download could not be verified. Refusing to install an unverified build."
        case .badChecksum(let expected, let actual):
            return "The download did not match its published checksum. Expected \(expected.prefix(12))…, got \(actual.prefix(12))…."
        case .badArchive(let detail):
            return "The downloaded archive could not be opened: \(detail)"
        case .versionMismatch(let expected, let actual):
            return "The archive contains version \(actual), but the release announced \(expected)."
        case .network(let detail):
            return "Could not reach the update server: \(detail)"
        }
    }
}

// MARK: - Transport

/// Injectable so the whole check-and-verify path can be exercised without a network.
protocol UpdateTransport {
    func data(from url: URL) async throws -> Data
}

struct URLSessionTransport: UpdateTransport {
    func data(from url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue("Bublr", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw UpdateError.network("HTTP \(http.statusCode)")
        }
        return data
    }
}

// MARK: - Service

/// Checks the project's GitHub releases, and turns one into a verified app bundle on disk.
///
/// GitHub hosts the artefacts, so there is no update server to run and no third-party framework to trust: the
/// feed is the same Releases page a person would visit, and the checksum is the same `SHA256SUMS` the release
/// publishes. Anything missing or mismatched is refused rather than installed.
struct UpdateService {
    static let latestReleaseURL = URL(string: "https://api.github.com/repos/nnnghia98/bublr/releases/latest")!

    var transport: UpdateTransport = URLSessionTransport()
    var currentVersion: String

    init(currentVersion: String? = nil, transport: UpdateTransport = URLSessionTransport()) {
        self.currentVersion = currentVersion
            ?? Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
            ?? "0"
        self.transport = transport
    }

    func check() async throws -> UpdateDecision {
        let data: Data
        do {
            data = try await transport.data(from: Self.latestReleaseURL)
        } catch let error as UpdateError {
            throw error
        } catch {
            throw UpdateError.network(error.localizedDescription)
        }

        let release: GitHubRelease
        do {
            release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        } catch {
            throw UpdateError.network("the release feed could not be read")
        }

        let version = release.tag.hasPrefix("v") ? String(release.tag.dropFirst()) : release.tag
        guard SemanticVersion.isNewer(version, than: currentVersion) else {
            return .upToDate(current: currentVersion)
        }
        guard let zip = release.assets.first(where: { $0.name.hasPrefix(UpdateRelease.zipPrefix) && $0.name.hasSuffix(".zip") }) else {
            return .unusable(UpdateError.noArchive(version: version).localizedDescription)
        }
        let checksums = release.assets.first { $0.name == UpdateRelease.checksumsName }
        return .available(UpdateRelease(
            version: version,
            notes: release.body ?? "",
            zipURL: zip.url,
            checksumsURL: checksums?.url
        ))
    }

    /// Downloads the release into `directory`, verifies it, and returns the unpacked app bundle.
    ///
    /// Every failure between here and a runnable bundle throws: a partial or tampered download must never reach
    /// the installer.
    func download(_ release: UpdateRelease, into directory: URL) async throws -> URL {
        guard let checksumsURL = release.checksumsURL else {
            throw UpdateError.noChecksum(version: release.version)
        }

        let archiveData = try await dataOrNetworkError(from: release.zipURL)
        let checksums = String(decoding: try await dataOrNetworkError(from: checksumsURL), as: UTF8.self)
        let archiveName = release.zipURL.lastPathComponent
        guard let expected = UpdateService.checksum(in: checksums, for: archiveName) else {
            throw UpdateError.noChecksum(version: release.version)
        }
        let actual = UpdateService.sha256(of: archiveData)
        guard expected.caseInsensitiveCompare(actual) == .orderedSame else {
            throw UpdateError.badChecksum(expected: expected, actual: actual)
        }

        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let archive = directory.appendingPathComponent(archiveName)
        try archiveData.write(to: archive)

        let unpacked = directory.appendingPathComponent("unpacked", isDirectory: true)
        try? fileManager.removeItem(at: unpacked)
        try fileManager.createDirectory(at: unpacked, withIntermediateDirectories: true)
        try UpdateService.unzip(archive, into: unpacked)

        let bundleName = Bundle.main.bundleURL.lastPathComponent
        let candidate = unpacked.appendingPathComponent(bundleName)
        guard fileManager.fileExists(atPath: candidate.appendingPathComponent("Contents/MacOS").path) else {
            throw UpdateError.badArchive("no \(bundleName) inside \(archiveName)")
        }
        let archivedVersion = NSDictionary(contentsOf: candidate.appendingPathComponent("Contents/Info.plist"))?
            .value(forKey: "CFBundleShortVersionString") as? String ?? "?"
        guard archivedVersion == release.version else {
            throw UpdateError.versionMismatch(expected: release.version, actual: archivedVersion)
        }
        return candidate
    }

    private func dataOrNetworkError(from url: URL) async throws -> Data {
        do {
            return try await transport.data(from: url)
        } catch let error as UpdateError {
            throw error
        } catch {
            throw UpdateError.network(error.localizedDescription)
        }
    }

    // MARK: Pure helpers

    static func sha256(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// `SHA256SUMS` is the output of `shasum -a 256`: "<hash>  <name>" per line.
    static func checksum(in file: String, for name: String) -> String? {
        for line in file.split(separator: "\n") {
            let fields = line.split(separator: " ", omittingEmptySubsequences: true)
            guard fields.count >= 2 else { continue }
            let listed = String(fields[1]).trimmingCharacters(in: CharacterSet(charactersIn: "*"))
            if listed == name { return String(fields[0]) }
        }
        return nil
    }

    static func unzip(_ archive: URL, into directory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", archive.path, directory.path]
        let pipe = Pipe()
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let detail = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            throw UpdateError.badArchive(detail.isEmpty ? "ditto exited \(process.terminationStatus)" : detail)
        }
    }
}

// MARK: - Installing

protocol UpdateInstalling {
    /// Replaces `target` with `candidate` once this process has exited, then relaunches it.
    func install(candidate: URL, replacing target: URL) throws
}

/// Replaces the bundle from a detached shell script.
///
/// A running app cannot overwrite itself — the binary is mapped and the code signature is live — so the swap has
/// to happen after this process is gone. The script waits for the current pid to disappear, replaces the bundle,
/// clears any quarantine flag, and reopens it.
struct ShellUpdateInstaller: UpdateInstalling {
    var scriptDirectory: URL = FileManager.default.temporaryDirectory

    func install(candidate: URL, replacing target: URL) throws {
        let script = scriptDirectory.appendingPathComponent("bublr-update-\(UUID().uuidString).sh")
        let body = """
        #!/bin/sh
        set -eu
        while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.2; done
        rm -rf '\(target.path)'
        ditto '\(candidate.path)' '\(target.path)'
        xattr -dr com.apple.quarantine '\(target.path)' 2>/dev/null || true
        open '\(target.path)'
        rm -f '\(script.path)'
        """
        try body.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [script.path]
        try process.run()
    }
}
