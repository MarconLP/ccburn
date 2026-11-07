import AppKit
import ServiceManagement

/// What the menu bar item shows. It is text only, no icon. There is no menu for it;
/// `defaults write com.github.marconlp.ccburn titleMetric rate5|rate60|today` sets it.
enum TitleMetric: String, CaseIterable {
    case rate60 = "rate60"
    case rate5 = "rate5"
    case today = "today"

    func text(_ f: Frame) -> String {
        switch self {
        case .rate60: return Self.usd(f.rate_60m) + "/h"
        case .rate5: return Self.usd(f.rate_5m) + "/h"
        case .today: return Self.usd(f.today)
        }
    }

    static func usd(_ v: Double) -> String {
        let fmt = NumberFormatter()
        fmt.numberStyle = .decimal
        fmt.minimumFractionDigits = 2
        fmt.maximumFractionDigits = 2
        fmt.locale = Locale(identifier: "en_US")
        return "$" + (fmt.string(from: NSNumber(value: v)) ?? String(format: "%.2f", v))
    }
}

/// The menu bar item opens a native menu whose only item is the burn-rate panel.
/// Clicking works like any system menu bar extra (Wi-Fi, Battery): the menu drops
/// from the menu bar on mouse-down, with the system's menu glass behind it.
/// It has no settings: the panel refreshes by itself, and the app turns Launch at
/// Login on at its first launch from /Applications.
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    static let chartHeight = 12
    static let refreshInterval: TimeInterval = 60
    /// Padding around the panel in `--snapshot` PNGs.
    static let padding: CGFloat = 16
    /// Insets of the panel inside the menu.
    static let menuInsets = NSEdgeInsets(top: 8, left: 14, bottom: 8, right: 14)

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let terminal = TerminalView()
    private let panelItem = NSMenuItem()
    private let panelView = NSView()
    private var engine: Engine?
    private var timer: Timer?
    private var running = false
    private var lastRun = Date.distantPast
    private var lastFrame: Frame?

    private let defaults = UserDefaults.standard

    private var titleMetric: TitleMetric {
        TitleMetric(rawValue: defaults.string(forKey: "titleMetric") ?? "") ?? .rate60
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let button = statusItem.button {
            button.title = "ccburn"
            button.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        }

        panelView.addSubview(terminal)
        panelItem.view = panelView
        menu.delegate = self
        menu.addItem(panelItem)
        statusItem.menu = menu
        enableLaunchAtLoginOnce()
        show(message: "\u{1B}[2mloading…\u{1B}[0m")

        do {
            engine = try Engine()
        } catch {
            show(error: error)
        }

        timer = Timer(timeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(timer!, forMode: .common)
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
        refresh()

        // Development aid: open the menu at launch so it can be screenshotted.
        if CommandLine.arguments.contains("--show-panel") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.statusItem.button?.performClick(nil) }
        }
    }

    // MARK: Refresh

    @objc private func didWake() { refresh() }

    @objc private func refresh() {
        guard let engine, !running else { return }
        running = true
        lastRun = Date()
        engine.run(height: Self.chartHeight) { [weak self] result in
            DispatchQueue.main.async { self?.apply(result) }
        }
    }

    private func apply(_ result: Result<Frame, Error>) {
        running = false
        switch result {
        case .success(let frame):
            lastFrame = frame
            terminal.columns = frame.width
            terminal.chart = frame.chart
            terminal.rows = ANSIParser.parse(frame.frame)
            updateTitle()
            // "2026-11-06T20:46:01+01:00" -> "20:46:01"
            let time = frame.updated.split(separator: "T").last.map { String($0.prefix(8)) } ?? frame.updated
            statusItem.button?.toolTip = "ccburn · updated \(time)"
            resizePanel()
        case .failure(let error):
            show(error: error)
        }
    }

    private func show(message: String) {
        terminal.chart = nil
        terminal.rows = ANSIParser.parse(message)
        resizePanel()
    }

    private func show(error: Error) {
        show(message: "\u{1B}[1mccburn failed\u{1B}[0m\n\n" + error.localizedDescription)
        statusItem.button?.title = lastFrame == nil ? "ccburn !" : statusItem.button?.title ?? ""
        statusItem.button?.toolTip = "ccburn: \(error.localizedDescription)"
    }

    private func updateTitle() {
        guard let button = statusItem.button else { return }
        button.title = lastFrame.map(titleMetric.text) ?? "ccburn"
    }

    /// Sizes the panel item to the text. An open menu follows the new size.
    private func resizePanel() {
        let size = terminal.intrinsicContentSize
        let i = Self.menuInsets
        terminal.frame = NSRect(x: i.left, y: i.bottom, width: size.width, height: size.height)
        panelView.setFrameSize(NSSize(width: size.width + i.left + i.right, height: size.height + i.top + i.bottom))
    }

    // MARK: Menu

    func menuWillOpen(_ menu: NSMenu) {
        if Date().timeIntervalSince(lastRun) > 5 { refresh() }
    }

    // MARK: Launch at Login

    /// Turns Launch at Login on the first time the installed app starts. Only once, so
    /// `--login-item off` sticks. A build run from elsewhere (build/) is not registered.
    private func enableLaunchAtLoginOnce() {
        let key = "launchAtLoginDefaulted"
        guard !defaults.bool(forKey: key), Bundle.main.bundlePath.hasPrefix("/Applications/") else { return }
        defaults.set(true, forKey: key)
        if SMAppService.mainApp.status != .enabled {
            try? SMAppService.mainApp.register()
        }
    }
}
