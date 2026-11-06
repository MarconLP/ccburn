import AppKit
import ServiceManagement

let app = NSApplication.shared
let args = CommandLine.arguments

// `ccburn --login-item on|off|status` sets Launch at Login without the menu, then exits.
// It is the same setting as the menu's checkbox.
if let i = args.firstIndex(of: "--login-item") {
    let service = SMAppService.mainApp
    let action = i + 1 < args.count ? args[i + 1] : "status"
    do {
        switch action {
        case "on": try service.register()
        case "off": try service.unregister()
        case "status": break
        default:
            fputs("usage: --login-item on|off|status\n", stderr)
            exit(2)
        }
    } catch {
        fputs("login item: \(error.localizedDescription)\n", stderr)
        exit(1)
    }
    switch service.status {
    case .enabled: print("enabled")
    case .requiresApproval: print("requires approval in System Settings > General > Login Items")
    case .notRegistered: print("off")
    case .notFound: print("not found")
    @unknown default: print("unknown")
    }
    exit(0)
}

// `ccburn --snapshot out.png [--dark]` renders one panel to PNG and exits.
if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
    let appearance = NSAppearance(named: args.contains("--dark") ? .darkAqua : .aqua)!
    do {
        let frame = try Engine().runSync(height: AppDelegate.chartHeight).get()
        let view = TerminalView()
        view.columns = frame.width
        view.chart = frame.chart
        view.rows = ANSIParser.parse(frame.frame)
        guard let png = view.pngData(appearance: appearance, padding: AppDelegate.padding) else {
            fputs("snapshot: render failed\n", stderr)
            exit(1)
        }
        try png.write(to: URL(fileURLWithPath: args[i + 1]))
        exit(0)
    } catch {
        fputs("snapshot: \(error.localizedDescription)\n", stderr)
        exit(1)
    }
}

let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
