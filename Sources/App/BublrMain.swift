import AppKit

final class RenderDelegate: NSObject, NSApplicationDelegate {
    let directory: String
    init(directory: String) { self.directory = directory }
    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.async { UIRenderer.run(directory: self.directory) }
    }
}

@main
struct BublrMain {
    static func main() {
        MainActor.assumeIsolated {
            let application = NSApplication.shared
            application.setActivationPolicy(.accessory)
            if CommandLine.arguments.contains("--selftest") {
                let runner = SelfTestRunner()
                application.delegate = runner
                withExtendedLifetime(runner) { application.run() }
            } else if let renderIndex = CommandLine.arguments.firstIndex(of: "--render-ui") {
                let dir = CommandLine.arguments.count > renderIndex + 1 ? CommandLine.arguments[renderIndex + 1] : "/tmp/bublr-ui"
                let delegate = RenderDelegate(directory: dir)
                application.delegate = delegate
                withExtendedLifetime(delegate) { application.run() }
            } else if let probeIndex = CommandLine.arguments.firstIndex(of: "--probe") {
                let url = CommandLine.arguments.count > probeIndex + 1 ? CommandLine.arguments[probeIndex + 1] : "https://example.com"
                let wait = CommandLine.arguments.count > probeIndex + 2 ? (Double(CommandLine.arguments[probeIndex + 2]) ?? 8) : 8
                let runner = DomProbeRunner(urlString: url, wait: wait)
                application.delegate = runner
                withExtendedLifetime(runner) { application.run() }
            } else {
                let delegate = AppDelegate()
                application.delegate = delegate
                withExtendedLifetime(delegate) { application.run() }
            }
        }
    }
}
