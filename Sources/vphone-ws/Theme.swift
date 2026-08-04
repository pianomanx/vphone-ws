import AppKit
import SwiftUI

private extension NSColor {
    convenience init(hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xff) / 255,
            green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255,
            alpha: 1)
    }
}

enum Theme {
    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        })
    }

    static let bg = dynamic(light: 0xeef0f4, dark: 0x101216)
    static let surface = dynamic(light: 0xffffff, dark: 0x1b1e24)
    static let surface2 = dynamic(light: 0xf6f7f9, dark: 0x21252c)
    static let inset = dynamic(light: 0xeceff3, dark: 0x15181d)
    static let border = dynamic(light: 0xdfe3ea, dark: 0x2b303a)
    static let borderStrong = dynamic(light: 0xc9cfd9, dark: 0x3a404c)
    static let text = dynamic(light: 0x1a1d23, dark: 0xe7eaef)
    static let dim = dynamic(light: 0x5b6472, dark: 0x9aa4b2)
    static let faint = dynamic(light: 0x8a94a3, dark: 0x69727f)
    static let accent = dynamic(light: 0x2f6fe0, dark: 0x5b9bff)
    static let accentInk = dynamic(light: 0xffffff, dark: 0x0b1220)
    static let good = dynamic(light: 0x1f9d40, dark: 0x3fb950)
    static let warn = dynamic(light: 0xb57d00, dark: 0xd29922)
    static let crit = dynamic(light: 0xcf2231, dark: 0xf85149)

    static let radius: CGFloat = 12
    static let radiusSmall: CGFloat = 8

    static let sidebarWidth: CGFloat = 264

    static let logBackground = Color(nsColor: NSColor(hex: 0x0e1013))
    static let logText = Color(nsColor: NSColor(hex: 0xc7d0dc))
}

extension Font {
    static func ws(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }
    static func wsMono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

enum VMStatus { case running, stopped }

struct StatusDot: View {
    let running: Bool
    var body: some View {
        Circle()
            .fill(running ? Theme.good : Theme.faint.opacity(0.7))
            .frame(width: 8, height: 8)
    }
}

struct StatusPill: View {
    enum Kind { case running, stopped, warn }
    let kind: Kind
    let label: String

    private var color: Color {
        switch kind {
        case .running: Theme.good
        case .stopped: Theme.faint
        case .warn: Theme.warn
        }
    }
    private var background: Color {
        switch kind {
        case .stopped: Theme.inset
        default: color.opacity(0.16)
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label).font(.ws(12, weight: .semibold))
        }
        .foregroundStyle(kind == .stopped ? Theme.faint : color)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(background)
        .overlay(
            Capsule().stroke(kind == .stopped ? Theme.border : color.opacity(0.3), lineWidth: 1))
        .clipShape(.capsule)
    }
}

struct StageChip: View {
    enum State { case completed, current, pending }
    let label: String
    let state: State

    private var fg: Color {
        switch state {
        case .completed: Theme.good
        case .current: Theme.accent
        case .pending: Theme.faint
        }
    }
    private var bg: Color {
        switch state {
        case .completed: Theme.good.opacity(0.16)
        case .current: Theme.accent.opacity(0.18)
        case .pending: Color.clear
        }
    }
    private var border: Color {
        switch state {
        case .completed: Theme.good.opacity(0.3)
        case .current: Theme.accent
        case .pending: Theme.border
        }
    }
    private var glyph: String {
        switch state {
        case .completed: "✓ "
        case .current: "▸ "
        case .pending: ""
        }
    }

    var body: some View {
        Text(glyph + label)
            .font(.wsMono(11, weight: state == .current ? .semibold : .regular))
            .foregroundStyle(fg)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(bg)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(border, lineWidth: 1))
            .clipShape(.rect(cornerRadius: 6))
    }
}

enum SpecValue {
    case text(String)
    case mono(String)
    case variantBadge(String)
}

struct VariantBadge: View {
    let variant: String

    private var label: String {
        switch variant {
        case "less": "less"
        case "regular": "regular"
        case "dev": "developer"
        case "jb": "jailbreak"
        case "exp": "experimental"
        default: variant
        }
    }
    private var color: Color {
        switch variant {
        case "less", "regular": Theme.accent
        case "exp": Theme.crit
        default: Theme.warn
        }
    }

    var body: some View {
        Text(label)
            .font(.wsMono(11, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(color.opacity(0.16))
            .clipShape(.rect(cornerRadius: 5))
    }
}

struct SpecTile: View {
    let key: String
    let value: SpecValue

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(key.uppercased())
                .font(.wsMono(10))
                .tracking(0.6)
                .foregroundStyle(Theme.faint)
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.surface)
    }

    @ViewBuilder private var content: some View {
        switch value {
        case .text(let s):
            Text(s).font(.ws(14, weight: .semibold)).foregroundStyle(Theme.text).textSelection(.enabled)
        case .mono(let s):
            Text(s).font(.wsMono(12)).foregroundStyle(Theme.text).textSelection(.enabled)
        case .variantBadge(let v):
            VariantBadge(variant: v)
        }
    }
}

struct SpecGrid: View {
    let specs: [(String, SpecValue)]
    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 150), spacing: 1)], spacing: 1
        ) {
            ForEach(specs, id: \.0) { key, value in
                SpecTile(key: key, value: value)
            }
        }
        .background(Theme.border)
        .clipShape(.rect(cornerRadius: Theme.radiusSmall))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusSmall).stroke(Theme.border, lineWidth: 1))
    }
}

/// Fixed-column spec grid where some keys span two columns (e.g. a long UDID).
/// Column count is chosen so the given specs fill their rows without gaps.
struct SpecGridSpanning: View {
    let specs: [(String, SpecValue)]
    let columns: Int
    var wideKeys: Set<String> = []

    private var rows: [[(key: String, value: SpecValue, span: Int)]] {
        var rows: [[(key: String, value: SpecValue, span: Int)]] = []
        var current: [(key: String, value: SpecValue, span: Int)] = []
        var used = 0
        for (key, value) in specs {
            let span = min(wideKeys.contains(key) ? 2 : 1, columns)
            if used + span > columns { rows.append(current); current = []; used = 0 }
            current.append((key, value, span))
            used += span
        }
        if !current.isEmpty { rows.append(current) }
        return rows
    }

    var body: some View {
        Grid(horizontalSpacing: 1, verticalSpacing: 1) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                GridRow {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, item in
                        SpecTile(key: item.key, value: item.value)
                            .gridCellColumns(item.span)
                    }
                }
            }
        }
        .background(Theme.border)
        .clipShape(.rect(cornerRadius: Theme.radiusSmall))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusSmall).stroke(Theme.border, lineWidth: 1))
    }
}

struct WSStepper: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let format: (Int) -> String

    var body: some View {
        HStack(spacing: 0) {
            Button {
                value = max(range.lowerBound, value - step)
            } label: {
                Text("−").font(.ws(16)).frame(width: 42, height: 34).contentShape(.rect)
            }.buttonStyle(.plain)
            Text(format(Int(value)))
                .font(.wsMono(13, weight: .semibold)).foregroundStyle(Theme.text)
                .frame(minWidth: 90).frame(height: 34)
                .overlay(alignment: .leading) { Rectangle().fill(Theme.borderStrong).frame(width: 1) }
                .overlay(alignment: .trailing) { Rectangle().fill(Theme.borderStrong).frame(width: 1) }
            Button {
                value = min(range.upperBound, value + step)
            } label: {
                Text("＋").font(.ws(15)).frame(width: 42, height: 34).contentShape(.rect)
            }.buttonStyle(.plain)
        }
        .foregroundStyle(Theme.text)
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusSmall).stroke(Theme.borderStrong, lineWidth: 1))
        .clipShape(.rect(cornerRadius: Theme.radiusSmall))
    }
}

struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.wsMono(11))
            .tracking(0.9)
            .foregroundStyle(Theme.faint)
    }
}

struct WSPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.ws(13, weight: .semibold))
            .foregroundStyle(Theme.accentInk)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Theme.accent.opacity(configuration.isPressed ? 0.8 : 1))
            .clipShape(.rect(cornerRadius: Theme.radiusSmall))
    }
}

struct WSSecondaryButtonStyle: ButtonStyle {
    var danger = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.ws(13))
            .foregroundStyle(danger ? Theme.crit : Theme.text)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Theme.surface.opacity(configuration.isPressed ? 0.6 : 1))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusSmall)
                    .stroke(danger ? Theme.crit.opacity(0.4) : Theme.borderStrong, lineWidth: 1))
            .clipShape(.rect(cornerRadius: Theme.radiusSmall))
    }
}

extension ButtonStyle where Self == WSPrimaryButtonStyle {
    static var wsPrimary: WSPrimaryButtonStyle { .init() }
}
extension ButtonStyle where Self == WSSecondaryButtonStyle {
    static var wsSecondary: WSSecondaryButtonStyle { .init() }
    static var wsDanger: WSSecondaryButtonStyle { .init(danger: true) }
}
