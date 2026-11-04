import SwiftUI
import WebKit
import AppKit

/// Hosts a persistent `WKWebView` inside SwiftUI without ever recreating it: a chat reloads only
/// when the provider says so, not when the bubble is opened or moved.
struct WebViewContainer: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> WebHostView {
        WebHostView(webView: webView)
    }

    func updateNSView(_ nsView: WebHostView, context: Context) {
        nsView.attach(webView)
        nsView.needsLayout = true
    }
}

/// A real AppKit container that keeps the web view exactly filling its bounds.
/// `NSHostingView` does not drive autoresizing for representable subviews, so a web view added
/// without an explicit layout pass can stay at 0×0 and never paint.
final class WebHostView: NSView {
    private weak var hosted: WKWebView?

    init(webView: WKWebView) {
        super.init(frame: .zero)
        wantsLayer = true
        attach(webView)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func attach(_ web: WKWebView) {
        hosted = web
        if web.superview !== self {
            web.removeFromSuperview()
            web.autoresizingMask = [.width, .height]
            addSubview(web)
        }
        web.frame = bounds
    }

    override func layout() {
        super.layout()
        hosted?.frame = bounds
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        hosted?.frame = bounds
    }
}

enum Prompt {
    static func rename(current: String, completion: @escaping (String) -> Void) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Rename account"
        alert.informativeText = "This name only appears inside Bublr."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = current
        field.placeholderString = "e.g. Personal"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        if alert.runModal() == .alertFirstButtonReturn {
            let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { completion(value) }
        }
    }
    static func confirm(title: String, message: String, action: String, completion: @escaping () -> Void) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: action)
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn { completion() }
    }
}
