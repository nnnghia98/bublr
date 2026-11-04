import SwiftUI
import AppKit
import Foundation

// MARK: - Provider identity

enum ProviderID: String, Codable, CaseIterable, Identifiable {
    case telegram
    case messenger
    case zalo
    case whatsapp
    case discord
    case slack
    case instagram
    case teams
    case custom

    var id: String { rawValue }

    var spec: ProviderSpec { ProviderCatalog.spec(for: self) }
}

enum LoginMethod: String, Codable, Hashable {
    case qr
    case credentials

    var title: String {
        switch self {
        case .qr: return "Scan QR code"
        case .credentials: return "Username & password"
        }
    }

    var icon: String {
        switch self {
        case .qr: return "qrcode"
        case .credentials: return "person.badge.key.fill"
        }
    }
}

/// Everything the app needs to know about one real chat provider.
struct ProviderSpec: Identifiable, Hashable {
    let id: ProviderID
    let name: String
    let shortName: String
    let tagline: String
    let homeURL: URL
    let hosts: [String]
    let loginMethods: [LoginMethod]
    let defaultMethod: LoginMethod
    let tintHex: UInt32
    let tintHex2: UInt32
    /// Elements that only exist behind a successful sign-in.
    let signedInSelectors: [String]
    /// Elements/text that only exist on a sign-in page.
    let loggedOutSelectors: [String]
    let loggedOutPhrases: [String]
    let loggedOutHosts: [String]
    let loginHint: [LoginMethod: String]
    /// JS that switches the provider's own page into the credential form (best effort).
    let credentialsSwitchJS: String?

    /// Whether the provider's own web client actually runs inside WebKit.
    /// WhatsApp's client only boots in Chromium engines — verified against the live page — so the app
    /// stops offering a bubble that could only ever show a blank card.
    var runsInWebKit: Bool = true
    /// Shown when `runsInWebKit` is false, so the limitation is explained instead of hidden.
    var unsupportedNote: String = ""

    /// Runs inside the provider page and reports which of the three states the page is in.
    /// The provider's own DOM is the source of truth; no cookie or URL guessing.
    var authProbeJS: String {
        let signed = ProviderCatalog.json(signedInSelectors)
        let loginSelectors = ProviderCatalog.json(loggedOutSelectors)
        let phrases = ProviderCatalog.json(loggedOutPhrases)
        let loginHosts = ProviderCatalog.json(loggedOutHosts)
        return """
        (function () {
          try {
            var signed = \(signed), loginSelectors = \(loginSelectors), phrases = \(phrases), loginHosts = \(loginHosts);
            var bodyEl = document.body;
            var body = bodyEl ? (bodyEl.innerText || '') : '';
            var compact = body.replace(/\\s+/g, '');
            var ready = compact.length > 12;
            function visible(el) {
              if (!el) return false;
              var r = el.getBoundingClientRect();
              return r.width > 1 && r.height > 1;
            }
            function anyVisible(list) {
              for (var i = 0; i < list.length; i++) { if (visible(document.querySelector(list[i]))) return true; }
              return false;
            }
            var pw = visible(document.querySelector('input[type=password]'));
            var hostLogin = loginHosts.some(function (h) { return location.host === h || location.host.slice(-(h.length + 1)) === '.' + h; });
            var textLogin = phrases.some(function (p) { return body.indexOf(p) !== -1; });
            var selLogin = anyVisible(loginSelectors);
            var signedHit = anyVisible(signed);
            var state = 'unknown';
            if (!ready) state = 'loading';
            else if (signedHit) state = 'signedIn';
            else if (pw || hostLogin || textLogin || selLogin) state = 'signedOut';
            else state = 'app';
            return JSON.stringify({ state: state, host: location.host, title: document.title || '', ready: ready });
          } catch (e) {
            return JSON.stringify({ state: 'error', error: String(e) });
          }
        })()
        """
    }

    var tint: Color { Color(hex: tintHex) }
    var tint2: Color { Color(hex: tintHex2) }

    var gradient: LinearGradient {
        LinearGradient(colors: [tint, tint2], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    func supports(_ method: LoginMethod) -> Bool { loginMethods.contains(method) }
}

enum ProviderCatalog {
    static let all: [ProviderSpec] = [
        telegramSpec,
        messengerSpec,
        zaloSpec,
        whatsappSpec,
        discordSpec,
        slackSpec,
        instagramSpec,
        teamsSpec,
        customSpec
    ]

    /// Providers that can host their real client inside Bublr.
    static var available: [ProviderSpec] { all.filter(\.runsInWebKit) }

    static func spec(for id: ProviderID) -> ProviderSpec {
        all.first { $0.id == id } ?? customSpec
    }

    static func json(_ values: [String]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: values),
              let string = String(data: data, encoding: .utf8) else { return "[]" }
        return string
    }

    static let telegramSpec = ProviderSpec(
        id: .telegram,
        name: "Telegram",
        shortName: "Telegram",
        tagline: "Cloud chats, channels and secret chats",
        homeURL: URL(string: "https://web.telegram.org/a/")!,
        hosts: ["web.telegram.org", "telegram.org"],
        loginMethods: [.qr, .credentials],
        defaultMethod: .qr,
        tintHex: 0x2AABEE,
        tintHex2: 0x1C7FC4,
        signedInSelectors: [".ChatList", ".LeftColumn", ".chat-list", ".tabs-container"],
        loggedOutSelectors: [".auth-form"],
        loggedOutPhrases: ["Log in to Telegram", "Log in by phone number"],
        loggedOutHosts: [],
        loginHint: [
            .qr: "Open Telegram on your phone → Settings → Devices → Link Desktop Device, then point it at this screen.",
            .credentials: "Tap “Log in by phone number” below, then enter the number registered with Telegram."
        ],
        credentialsSwitchJS: """
        (function () {
          try {
            var nodes = Array.from(document.querySelectorAll('button, a, div[role=button]'));
            var target = nodes.find(function (n) { return /phone number/i.test(n.textContent || ''); });
            if (target) { target.click(); return true; }
          } catch (e) {}
          return false;
        })()
        """
    )

    static let messengerSpec = ProviderSpec(
        id: .messenger,
        name: "Messenger",
        shortName: "Messenger",
        tagline: "Facebook Messenger chats and calls",
        homeURL: URL(string: "https://www.messenger.com/")!,
        hosts: ["messenger.com", "facebook.com", "www.messenger.com"],
        loginMethods: [.credentials],
        defaultMethod: .credentials,
        tintHex: 0xA033FF,
        tintHex2: 0x0084FF,
        signedInSelectors: ["[aria-label=\"Chats\"]", "[data-pagelet=\"MWChats\"]", "div[role=\"navigation\"]"],
        loggedOutSelectors: ["input[type=password]"],
        loggedOutPhrases: ["Forgotten password", "Log in to Messenger", "Create new account"],
        loggedOutHosts: [],
        loginHint: [
            .credentials: "Sign in with the Facebook account your Messenger uses. Facebook may ask for a 2FA code."
        ],
        credentialsSwitchJS: nil
    )

    static let zaloSpec = ProviderSpec(
        id: .zalo,
        name: "Zalo",
        shortName: "Zalo",
        tagline: "Zalo messages, calls and groups",
        homeURL: URL(string: "https://chat.zalo.me/")!,
        hosts: ["chat.zalo.me", "id.zalo.me", "zalo.me"],
        loginMethods: [.qr, .credentials],
        defaultMethod: .qr,
        tintHex: 0x0068FF,
        tintHex2: 0x00B2FF,
        signedInSelectors: ["#chat-list", ".chat-list", "[class*=\"chat-list\"]", "[id*=\"chat\"]"],
        loggedOutSelectors: ["input[type=password]"],
        loggedOutPhrases: ["Đăng nhập tài khoản Zalo", "Đăng nhập bằng mật khẩu"],
        loggedOutHosts: ["id.zalo.me"],
        loginHint: [
            .qr: "Open Zalo on your phone → the QR scanner in the top bar → scan this code.",
            .credentials: "Enter the phone number and Zalo password for the account you want to link."
        ],
        credentialsSwitchJS: nil
    )

    static let whatsappSpec = ProviderSpec(
        id: .whatsapp,
        name: "WhatsApp",
        shortName: "WhatsApp",
        tagline: "Personal WhatsApp, linked as a device",
        homeURL: URL(string: "https://web.whatsapp.com/")!,
        hosts: ["web.whatsapp.com"],
        loginMethods: [.qr],
        defaultMethod: .qr,
        tintHex: 0x25D366,
        tintHex2: 0x0E8C6B,
        signedInSelectors: ["#pane-side", "div[aria-label=\"Chat list\"]", "[data-testid=\"chat-list\"]"],
        loggedOutSelectors: [],
        loggedOutPhrases: ["Link with phone number", "Scan the QR code", "link a device"],
        loggedOutHosts: [],
        loginHint: [
            .qr: "On your phone: WhatsApp → Settings → Linked devices → Link a device, then scan."
        ],
        credentialsSwitchJS: nil,
        runsInWebKit: false,
        unsupportedNote: "WhatsApp's web client only runs in Chromium browsers. Inside Bublr it shows its download page instead of the QR code, so open WhatsApp Desktop or your browser for this one."
    )

    static let discordSpec = ProviderSpec(
        id: .discord,
        name: "Discord",
        shortName: "Discord",
        tagline: "Servers, DMs and voice channels",
        homeURL: URL(string: "https://discord.com/app")!,
        hosts: ["discord.com", "discordapp.com"],
        loginMethods: [.qr, .credentials],
        defaultMethod: .qr,
        tintHex: 0x5865F2,
        tintHex2: 0x3B45B8,
        signedInSelectors: ["nav[aria-label=\"Servers sidebar\"]", "[class*=\"guilds\"]"],
        loggedOutSelectors: ["input[type=password]"],
        loggedOutPhrases: ["Welcome back", "Log In"],
        loggedOutHosts: [],
        loginHint: [
            .qr: "Open Discord on your phone → Settings → Scan QR Code, then scan this screen.",
            .credentials: "Sign in with your Discord email and password."
        ],
        credentialsSwitchJS: nil
    )

    static let slackSpec = ProviderSpec(
        id: .slack,
        name: "Slack",
        shortName: "Slack",
        tagline: "Workspace channels and DMs",
        homeURL: URL(string: "https://slack.com/signin")!,
        hosts: ["slack.com", "app.slack.com"],
        loginMethods: [.credentials],
        defaultMethod: .credentials,
        tintHex: 0x611F69,
        tintHex2: 0x36C5F0,
        signedInSelectors: [".p-channel_sidebar", "[data-qa=\"channel_sidebar\"]", "[data-qa=\"top_nav\"]"],
        loggedOutSelectors: ["input[type=password]"],
        loggedOutPhrases: ["Sign in to your workspace", "We suggest using the"],
        loggedOutHosts: [],
        loginHint: [
            .credentials: "Enter your workspace URL, then your Slack email and password."
        ],
        credentialsSwitchJS: nil
    )

    static let instagramSpec = ProviderSpec(
        id: .instagram,
        name: "Instagram",
        shortName: "Instagram",
        tagline: "Direct messages",
        homeURL: URL(string: "https://www.instagram.com/direct/inbox/")!,
        hosts: ["instagram.com", "www.instagram.com"],
        loginMethods: [.credentials],
        defaultMethod: .credentials,
        tintHex: 0xF58529,
        tintHex2: 0xDD2A7B,
        signedInSelectors: ["a[href=\"/direct/inbox/\"]", "svg[aria-label=\"Direct\"]"],
        loggedOutSelectors: ["input[type=password]"],
        loggedOutPhrases: ["Log in", "Sign up"],
        loggedOutHosts: [],
        loginHint: [
            .credentials: "Use your Instagram username and password. Instagram may ask for a code sent to your phone."
        ],
        credentialsSwitchJS: nil
    )

    static let teamsSpec = ProviderSpec(
        id: .teams,
        name: "Microsoft Teams",
        shortName: "Teams",
        tagline: "Work chats and meetings",
        homeURL: URL(string: "https://teams.microsoft.com/v2/")!,
        hosts: ["teams.microsoft.com", "login.microsoftonline.com", "teams.live.com"],
        loginMethods: [.credentials],
        defaultMethod: .credentials,
        tintHex: 0x5059C9,
        tintHex2: 0x7B83EB,
        signedInSelectors: ["[data-tid=\"app-layout\"]", "[data-tid=\"chat-list\"]", "#teams-app-bar"],
        loggedOutSelectors: ["input[type=password]"],
        loggedOutPhrases: ["Sign in", "Pick an account"],
        loggedOutHosts: ["login.microsoftonline.com", "login.live.com"],
        loginHint: [
            .credentials: "Sign in with your Microsoft work account, including any MFA prompt."
        ],
        credentialsSwitchJS: nil
    )

    static let customSpec = ProviderSpec(
        id: .custom,
        name: "Custom web chat",
        shortName: "Custom",
        tagline: "Any chat that runs on the web",
        homeURL: URL(string: "https://web.telegram.org/k/")!,
        hosts: [],
        loginMethods: [.credentials, .qr],
        defaultMethod: .credentials,
        tintHex: 0x8E8E93,
        tintHex2: 0x636366,
        signedInSelectors: [],
        loggedOutSelectors: ["input[type=password]"],
        loggedOutPhrases: ["Log in", "Sign in"],
        loggedOutHosts: [],
        loginHint: [
            .credentials: "Paste the address of any web chat in Settings, then sign in normally.",
            .qr: "Scan the QR code the website shows."
        ],
        credentialsSwitchJS: nil
    )
}

// MARK: - Color helpers

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}
