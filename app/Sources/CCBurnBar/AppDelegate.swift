import AppKit
import ServiceManagement

/// What the menu bar item shows next to its icon.
enum TitleMetric: String, CaseIterable {
    case rate60 = "rate60"
    case rate5 = "rate5"
    case today = "today"
    case iconOnly = "icon"

    var label: String {
        switch self {
        case .rate60: return "Last 60 min rate"
        case .rate5: return "Last 5 min rate"
        case .today: return "Today so far"
        case .iconOnly: return "Icon only"
        }
    }

    func text(_ f: Frame) -> String {
        switch self {
        case .rate60: return Self.usd(f.rate_60m) + "/h"
        case .rate5: return Self.usd(f.rate_5m) + "/h"
        case .today: return Self.usd(f.today)
        case .iconOnly: return ""
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

/// Opaque panel background. macOS 26 popovers are glass, and text over
/// whatever window sits behind them is hard to read.
final class SolidBackgroundView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        dirtyRect.fill()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    static let chartHeight = 12
    /// Width handed to `ccburn --width`: one column per minute of chart plus its axis,
    /// with the tables stretched to the same right edge.
    static let columns = 68
    static let refreshInterval: TimeInterval = 60
    static let padding: CGFloat = 16

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let terminal = TerminalView()
    private let panel = NSViewController()
    private var engine: Engine?
    private var timer: Timer?
    private var running = false
    private var lastRun = Date.distantPast
    private var lastFrame: Frame?

    private let defaults = UserDefaults.standard

    private var titleMetric: TitleMetric {
        get { TitleMetric(rawValue: defaults.string(forKey: "titleMetric") ?? "") ?? .rate60 }
        set { defaults.set(newValue.rawValue, forKey: "titleMetric") }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let button = statusItem.button {
            let icon = NSImage(systemSymbolName: "flame", accessibilityDescription: "ccburn")
            icon?.isTemplate = true
            button.image = icon
            button.imagePosition = .imageLeading
            button.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        let container = SolidBackgroundView()
        terminal.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(terminal)
        NSLayoutConstraint.activate([
            terminal.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Self.padding),
            terminal.topAnchor.constraint(equalTo: container.topAnchor, constant: Self.padding),
        ])
        panel.view = container
        popover.contentViewController = panel
        popover.behavior = .transient
        popover.animates = false

        terminal.columns = Self.columns
        terminal.menu = makeMenu()
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

        // Development aid: open the panel at launch so it can be screenshotted.
        if CommandLine.arguments.contains("--show-panel") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.togglePopover() }
        }
    }

    // MARK: Refresh

    @objc private func didWake() { refresh() }

    @objc private func refresh() {
        guard let engine, !running else { return }
        running = true
        lastRun = Date()
        engine.run(columns: Self.columns, height: Self.chartHeight) { [weak self] result in
            DispatchQueue.main.async { self?.apply(result) }
        }
    }

    private func apply(_ result: Result<Frame, Error>) {
        running = false
        switch result {
        case .success(let frame):
            lastFrame = frame
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
        terminal.rows = ANSIParser.parse(message)
        resizePanel()
    }

    private func show(error: Error) {
        show(message: "\u{1B}[1mccburn failed\u{1B}[0m\n\n" + error.localizedDescription)
        statusItem.button?.title = lastFrame == nil ? " !" : statusItem.button?.title ?? ""
        statusItem.button?.toolTip = "ccburn: \(error.localizedDescription)"
    }

    private func updateTitle() {
        guard let button = statusItem.button else { return }
        let text = lastFrame.map(titleMetric.text) ?? ""
        button.title = text.isEmpty ? "" : " " + text
    }

    private func resizePanel() {
        let size = terminal.intrinsicContentSize
        let padded = NSSize(width: size.width + 2 * Self.padding, height: size.height + 2 * Self.padding)
        panel.preferredContentSize = padded
        popover.contentSize = padded
    }

    // MARK: Clicks

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showMenu()
        } else {
            togglePopover()
        }
    }

    private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        guard let button = statusItem.button else { return }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        if Date().timeIntervalSince(lastRun) > 5 { refresh() }
    }

    private func showMenu() {
        popover.performClose(nil)
        statusItem.menu = makeMenu()
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    // MARK: Menu

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(item("Refresh", #selector(refresh), key: "r"))
        menu.addItem(.separator())

        let titleMenu = NSMenu()
        for metric in TitleMetric.allCases {
            let it = item(metric.label, #selector(pickTitleMetric(_:)))
            it.representedObject = metric.rawValue
            it.state = metric == titleMetric ? .on : .off
            titleMenu.addItem(it)
        }
        let titleItem = NSMenuItem(title: "Menu Bar Shows", action: nil, keyEquivalent: "")
        titleItem.submenu = titleMenu
        menu.addItem(titleItem)

        let login = item("Launch at Login", #selector(toggleLaunchAtLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        menu.addItem(item("Quit ccburn", #selector(NSApplication.terminate(_:)), key: "q", target: NSApp))
        return menu
    }

    private func item(_ title: String, _ action: Selector, key: String = "", target: AnyObject? = nil) -> NSMenuItem {
        let it = NSMenuItem(title: title, action: action, keyEquivalent: key)
        it.target = target ?? self
        return it
    }

    @objc private func pickTitleMetric(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let metric = TitleMetric(rawValue: raw) else { return }
        titleMetric = metric
        updateTitle()
        terminal.menu = makeMenu()
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Could not change Launch at Login"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
        terminal.menu = makeMenu()
    }
}
