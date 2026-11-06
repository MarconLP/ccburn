import AppKit

let app = NSApplication.shared
let args = CommandLine.arguments

// `ccburn --snapshot out.png [--dark] [--columns N]` renders one panel to PNG and exits.
if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
    let columns = args.firstIndex(of: "--columns").flatMap { $0 + 1 < args.count ? Int(args[$0 + 1]) : nil }
        ?? AppDelegate.columns
    let appearance = NSAppearance(named: args.contains("--dark") ? .darkAqua : .aqua)!
    do {
        let frame = try Engine().runSync(columns: columns, height: AppDelegate.chartHeight).get()
        let view = TerminalView()
        view.columns = columns
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
