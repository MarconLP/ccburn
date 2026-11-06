import AppKit

// MARK: - ANSI parsing

enum TermColor: Equatable {
    case `default`
    case indexed(Int)
    case rgb(Int, Int, Int)
}

struct CellStyle: Equatable {
    var fg: TermColor = .default
    var bold = false
    var dim = false
}

struct Cell {
    var ch: Character
    var style: CellStyle
}

/// Splits text with SGR escape codes into rows of styled cells, one cell per
/// character, the way a terminal lays them out.
enum ANSIParser {
    static func parse(_ text: String) -> [[Cell]] {
        var rows: [[Cell]] = [[]]
        var style = CellStyle()
        var it = Array(text).makeIterator()
        while let ch = it.next() {
            if ch == "\u{1B}" {
                guard let open = it.next(), open == "[" else { continue }
                var params = ""
                var final: Character = "m"
                while let c = it.next() {
                    if let a = c.asciiValue, (0x40...0x7E).contains(a) {
                        final = c
                        break
                    }
                    params.append(c)
                }
                if final == "m" { apply(params, to: &style) }
                continue
            }
            if ch == "\n" {
                rows.append([])
                continue
            }
            rows[rows.count - 1].append(Cell(ch: ch, style: style))
        }
        return rows
    }

    private static func apply(_ params: String, to style: inout CellStyle) {
        let codes = params.split(separator: ";", omittingEmptySubsequences: false).map { Int($0) ?? 0 }
        var i = 0
        while i < codes.count {
            let code = codes[i]
            switch code {
            case 0: style = CellStyle()
            case 1: style.bold = true
            case 2: style.dim = true
            case 22: style.bold = false; style.dim = false
            case 30...37: style.fg = .indexed(code - 30)
            case 90...97: style.fg = .indexed(code - 90 + 8)
            case 39: style.fg = .default
            case 38:
                if i + 2 < codes.count, codes[i + 1] == 5 {
                    style.fg = .indexed(codes[i + 2])
                    i += 2
                } else if i + 4 < codes.count, codes[i + 1] == 2 {
                    style.fg = .rgb(codes[i + 2], codes[i + 3], codes[i + 4])
                    i += 4
                }
            default: break
            }
            i += 1
        }
    }
}

// MARK: - Colors

enum XTerm {
    private static let base: [(Int, Int, Int)] = [
        (0, 0, 0), (205, 49, 49), (13, 188, 121), (229, 229, 16),
        (36, 114, 200), (188, 63, 188), (17, 168, 205), (229, 229, 229),
        (102, 102, 102), (241, 76, 76), (35, 209, 139), (245, 245, 67),
        (59, 142, 234), (214, 112, 214), (41, 184, 219), (255, 255, 255),
    ]
    private static let cube = [0, 95, 135, 175, 215, 255]

    static func color(_ c: TermColor) -> NSColor? {
        switch c {
        case .default:
            return nil
        case .rgb(let r, let g, let b):
            return srgb(r, g, b)
        case .indexed(let n):
            switch n {
            case 0..<16:
                let (r, g, b) = base[n]
                return srgb(r, g, b)
            case 16..<232:
                let v = n - 16
                return srgb(cube[v / 36], cube[(v % 36) / 6], cube[v % 6])
            case 232..<256:
                let g = 8 + 10 * (n - 232)
                return srgb(g, g, g)
            default:
                return nil
            }
        }
    }

    private static func srgb(_ r: Int, _ g: Int, _ b: Int) -> NSColor {
        NSColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
    }
}

// MARK: - View

/// Draws cells on a fixed character grid, like a terminal does, so fallback
/// glyphs (✳, ⬡) never shift a column and the chart's block glyphs fill
/// their cells edge to edge.
final class TerminalView: NSView {
    var rows: [[Cell]] = [] {
        didSet {
            invalidateIntrinsicContentSize()
            needsDisplay = true
        }
    }
    /// Minimum width in columns, so the panel keeps its size while a frame loads.
    var columns: Int = 54 {
        didSet { invalidateIntrinsicContentSize() }
    }
    var chart: ChartData? {
        didSet { needsDisplay = true }
    }
    private let font: NSFont
    private let boldFont: NSFont
    let cellSize: NSSize

    init(fontSize: CGFloat = 12) {
        font = NSFont(name: "Menlo", size: fontSize) ?? .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        boldFont = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
        let w = ("M" as NSString).size(withAttributes: [.font: font]).width
        let h = ceil(font.ascender - font.descender + font.leading)
        cellSize = NSSize(width: w, height: h)
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { true }

    override var intrinsicContentSize: NSSize {
        let cols = max(columns, rows.map(\.count).max() ?? 0)
        return NSSize(width: ceil(CGFloat(cols) * cellSize.width), height: ceil(CGFloat(rows.count) * cellSize.height))
    }

    override func draw(_ dirtyRect: NSRect) {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            drawCells(in: dirtyRect)
            if let chart { drawChart(chart) }
        }
    }

    private func drawCells(in dirtyRect: NSRect) {
        let cw = cellSize.width
        let chh = cellSize.height
        for (y, row) in rows.enumerated() {
            let top = CGFloat(y) * chh
            if top > dirtyRect.maxY || top + chh < dirtyRect.minY { continue }
            for (x, cell) in row.enumerated() where cell.ch != " " {
                let rect = NSRect(x: CGFloat(x) * cw, y: top, width: cw, height: chh)
                let color = foreground(cell.style)
                if let eighths = blockEighths(cell.ch) {
                    // Lower block elements: fill from the bottom, flush with the cell edges.
                    // Pixel-aligned so neighbouring cells meet without an anti-aliased seam.
                    color.setFill()
                    let h = chh * CGFloat(eighths) / 8
                    backingAlignedRect(NSRect(x: rect.minX, y: rect.maxY - h, width: cw, height: h), options: .alignAllEdgesNearest).fill()
                } else if cell.ch == "─" {
                    color.setFill()
                    backingAlignedRect(NSRect(x: rect.minX, y: rect.midY.rounded(.down), width: cw, height: 1), options: .alignAllEdgesNearest).fill()
                } else {
                    let attrs: [NSAttributedString.Key: Any] = [
                        .font: cell.style.bold ? boldFont : font,
                        .foregroundColor: color,
                    ]
                    NSAttributedString(string: String(cell.ch), attributes: attrs).draw(at: rect.origin)
                }
            }
        }
    }

    /// The per-minute chart: same layout, colors and labels as the terminal one, but each
    /// minute gets a 60th of the plot width instead of a whole character column.
    private func drawChart(_ chart: ChartData) {
        let cw = cellSize.width
        let chh = cellSize.height
        let n = chart.labels.count
        guard n > 0 else { return }
        let top = CGFloat(chart.row) * chh
        let plotH = CGFloat(chart.height) * chh
        let plotX = CGFloat(chart.axis_width + 1) * cw
        let plotW = intrinsicContentSize.width - plotX
        let barW = plotW / CGFloat(n)
        let dim = NSColor.secondaryLabelColor

        for a in chart.axis {
            drawText(a.text, at: NSPoint(x: 0, y: top + CGFloat(chart.height - 1 - a.row) * chh), color: dim)
        }

        let value = { (s: ChartData.Series, i: Int) -> Double in s.values.indices.contains(i) ? s.values[i] : 0 }
        let peak = (0..<n).map { i in chart.series.reduce(0) { $0 + value($1, i) } }.max() ?? 0
        if peak > 0 {
            for i in 0..<n {
                var base = top + plotH
                for s in chart.series {
                    let v = value(s, i)
                    guard v > 0 else { continue }
                    let h = plotH * CGFloat(v / peak)
                    (XTerm.color(.indexed(s.color)) ?? .labelColor).setFill()
                    let x0 = plotX + CGFloat(i) * barW
                    backingAlignedRect(NSRect(x: x0, y: base - h, width: barW, height: h), options: .alignAllEdgesNearest).fill()
                    base -= h
                }
            }
        }

        dim.setFill()
        backingAlignedRect(NSRect(x: plotX, y: (top + plotH + chh / 2).rounded(.down), width: plotW, height: 1), options: .alignAllEdgesNearest).fill()

        let labelY = top + plotH + chh
        drawText(chart.labels[0], at: NSPoint(x: plotX, y: labelY), color: dim)
        if n > 2 {
            drawText(chart.labels[n / 2], at: NSPoint(x: plotX + CGFloat(n / 2) * barW, y: labelY), color: dim)
        }
        let last = chart.labels[n - 1]
        drawText(last, at: NSPoint(x: plotX + plotW - CGFloat(last.count) * cw, y: labelY), color: dim)
    }

    private func drawText(_ text: String, at point: NSPoint, color: NSColor) {
        NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color]).draw(at: point)
    }

    private func foreground(_ style: CellStyle) -> NSColor {
        guard let c = XTerm.color(style.fg) else {
            return style.dim ? .secondaryLabelColor : .labelColor
        }
        return style.dim ? c.withAlphaComponent(0.55) : c
    }

    private func blockEighths(_ ch: Character) -> Int? {
        guard let s = ch.unicodeScalars.first, ch.unicodeScalars.count == 1 else { return nil }
        switch s.value {
        case 0x2581...0x2588: return Int(s.value - 0x2580)
        default: return nil
        }
    }

    /// Renders the current grid to PNG (used by `--snapshot`).
    func pngData(appearance: NSAppearance, padding: CGFloat) -> Data? {
        let content = intrinsicContentSize
        let host = NSView(frame: NSRect(x: 0, y: 0, width: content.width + 2 * padding, height: content.height + 2 * padding))
        host.appearance = appearance
        host.wantsLayer = true
        frame = NSRect(x: padding, y: padding, width: content.width, height: content.height)
        host.addSubview(self)
        let bg = NSBox(frame: host.bounds)
        bg.boxType = .custom
        bg.borderWidth = 0
        bg.fillColor = .windowBackgroundColor
        host.addSubview(bg, positioned: .below, relativeTo: self)
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return nil }
        host.cacheDisplay(in: host.bounds, to: rep)
        removeFromSuperview()
        return rep.representation(using: .png, properties: [:])
    }
}
