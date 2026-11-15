import AppKit
import SwiftUI
import TraceCore

/// Colours and metrics of the design, each with a light and a dark value.
enum Theme {
    private static func dyn(_ light: UInt32, _ dark: UInt32, alpha: (CGFloat, CGFloat) = (1, 1)) -> Color {
        func make(_ hex: UInt32, _ a: CGFloat) -> NSColor {
            NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                    blue: CGFloat(hex & 0xFF) / 255, alpha: a)
        }
        return Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? make(dark, alpha.1) : make(light, alpha.0)
        })
    }

    static let bg = dyn(0xF5F5F7, 0x1C1C1E)
    static let panel = dyn(0xFFFFFF, 0x2A2A2D)
    static let side = dyn(0xE9E9EB, 0x242426)
    static let ink = dyn(0x1D1D1F, 0xF5F5F7)
    static let muted = dyn(0x636366, 0xA8A8AE)
    static let line = dyn(0x000000, 0xFFFFFF, alpha: (0.10, 0.12))
    static let hover = dyn(0x000000, 0xFFFFFF, alpha: (0.07, 0.09))
    static let accent = dyn(0x0A6CE0, 0x4DA3FF)
    static let onAccent = dyn(0xFFFFFF, 0x04213F)
    static let soft = dyn(0xE3EEFD, 0x1B3350)
    static let ok = dyn(0x2DA44E, 0x30D158)
    static let shadow = dyn(0x000000, 0x000000, alpha: (0.06, 0.25))

    static let palette: [Color] = [
        dyn(0x007AFF, 0x0A84FF), dyn(0xA550D8, 0xBF5AF2), dyn(0x2DA44E, 0x30D158), dyn(0xDB7A00, 0xFF9F0A),
        dyn(0xF0284F, 0xFF375F), dyn(0x8E8E93, 0x98989D), dyn(0x1E9BB3, 0x40C8E0), dyn(0xA2845E, 0xAC8E68),
    ]

    static let mono = Font.system(size: 12, design: .monospaced)
}

enum Palette {
    static var colors: [Color] { Theme.palette }

    static func color(_ index: Int) -> Color {
        colors[((index % colors.count) + colors.count) % colors.count]
    }

    /// Untagged activity is drawn in a quiet neutral.
    static func color(_ tag: Tag?) -> Color {
        tag.map { color($0.colorIndex) } ?? Theme.muted.opacity(0.45)
    }
}

// MARK: Surfaces

/// A system material behind a view: the translucent sidebar of a window, or
/// the near-white sheet of a menu.
struct MaterialBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.state = .active
        view.material = material
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
    }
}

/// The rounded panel every section sits on.
struct Card<Content: View>: View {
    var padding: EdgeInsets = EdgeInsets(top: 16, leading: 20, bottom: 16, trailing: 20)
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.line.opacity(0.6)))
            .shadow(color: Theme.shadow, radius: 6, y: 2)
    }
}

extension EdgeInsets {
    static func all(_ v: CGFloat) -> EdgeInsets { EdgeInsets(top: v, leading: v, bottom: v, trailing: v) }
    static func hv(_ h: CGFloat, _ v: CGFloat) -> EdgeInsets { EdgeInsets(top: v, leading: h, bottom: v, trailing: h) }
}

/// Title row at the top of each page.
struct PageHeader<Leading: View, Trailing: View>: View {
    let title: String
    var subtitle: String = ""
    /// What the page is for; shown when the pointer rests on the title.
    var hint: String = ""
    /// A short highlighted note after the title, e.g. "Today".
    var pill: String = ""
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            leading
            Text(title).font(.system(size: 20, weight: .bold)).tracking(-0.2).lineLimit(1).help(hint)
            if !pill.isEmpty {
                Text(pill)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Theme.soft, in: Capsule())
            }
            if !subtitle.isEmpty {
                Text(subtitle).foregroundStyle(Theme.muted).lineLimit(1)
            }
            Spacer(minLength: 12)
            trailing
        }
        .frame(minHeight: 30)
    }
}

extension PageHeader where Leading == EmptyView {
    init(title: String, subtitle: String = "", hint: String = "", pill: String = "",
         @ViewBuilder trailing: () -> Trailing) {
        self.init(title: title, subtitle: subtitle, hint: hint, pill: pill, leading: { EmptyView() }, trailing: trailing)
    }
}

struct SectionTitle: View {
    let title: String
    var note: String = ""

    var body: some View {
        // The note explains the section; it shows when the pointer rests on
        // the title rather than taking up a line of its own.
        Text(title).font(.system(size: 14, weight: .semibold))
            .help(note)
    }
}

// MARK: Controls

/// The pill-shaped segmented control used for view and period switches.
struct Segmented<Value: Hashable>: View {
    let options: [(value: Value, title: String)]
    @Binding var selection: Value
    @Namespace private var thumb

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options.indices, id: \.self) { index in
                let option = options[index]
                let isOn = option.value == selection
                Button { selection = option.value } label: {
                    Text(option.title)
                        .fontWeight(isOn ? .semibold : .regular)
                        .foregroundStyle(isOn ? Theme.ink : Theme.muted)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 26)
                        .background {
                            if isOn {
                                RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Theme.panel)
                                    .shadow(color: Theme.shadow, radius: 1.5, y: 1)
                                    .matchedGeometryEffect(id: "thumb", in: thumb)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .padding(2)
        .background(Theme.hover, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .fixedSize()
        .animation(.snappy(duration: 0.22), value: selection)
    }
}

struct SearchField: View {
    @Binding var text: String
    let placeholder: String
    var width: CGFloat = 170

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.muted)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .frame(width: width)
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.muted)
                    .accessibilityLabel(L("Clear search"))
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.line))
    }
}

/// Accent-filled, outlined, or text-only buttons at the design's sizes.
struct TRButtonStyle: ButtonStyle {
    enum Kind { case prominent, bordered, link }
    var kind: Kind = .bordered
    var height: CGFloat = 30
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        Hoverable(style: self, configuration: configuration)
    }

    /// Brightens slightly under the pointer, as system buttons do.
    private struct Hoverable: View {
        let style: TRButtonStyle
        let configuration: Configuration
        @State private var hovering = false

        var body: some View {
            style.label(configuration)
                .brightness(hovering && style.kind != .link ? (style.kind == .prominent ? 0.06 : -0.03) : 0)
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.12), value: hovering)
        }
    }

    fileprivate func label(_ configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        return configuration.label
            .fontWeight(kind == .bordered ? .medium : .semibold)
            .lineLimit(1)
            .padding(.horizontal, kind == .link ? 0 : 12)
            .frame(minHeight: height)
            .foregroundStyle(foreground)
            .background(background, in: shape)
            .overlay(shape.strokeBorder(kind == .bordered ? Theme.line : .clear))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(shape)
    }

    private var foreground: Color {
        guard isEnabled else { return Theme.muted }
        switch kind {
        case .prominent: return Theme.onAccent
        case .bordered: return Theme.ink
        case .link: return Theme.accent
        }
    }

    private var background: Color {
        switch kind {
        case .prominent: return isEnabled ? Theme.accent : Theme.bg
        case .bordered: return Theme.panel
        case .link: return .clear
        }
    }
}

extension ButtonStyle where Self == TRButtonStyle {
    static var trProminent: TRButtonStyle { TRButtonStyle(kind: .prominent) }
    static var trBordered: TRButtonStyle { TRButtonStyle(kind: .bordered) }
    static var trLink: TRButtonStyle { TRButtonStyle(kind: .link, height: 20) }
}

/// A 28-point square button holding one symbol.
struct IconButton: View {
    let symbol: String
    let label: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .frame(width: 28, height: 28)
                .background(Theme.panel, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Theme.line))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }
}

// MARK: Small pieces

/// A tag's colour as a dot or a rounded square.
struct Swatch: View {
    let color: Color
    var size: CGFloat = 10
    var radius: CGFloat? = 3

    init(_ tag: Tag?, size: CGFloat = 10, round: Bool = false) {
        color = Palette.color(tag)
        self.size = size
        radius = round ? nil : max(2, size * 0.3)
    }

    init(color: Color, size: CGFloat = 10, round: Bool = false) {
        self.color = color
        self.size = size
        radius = round ? nil : max(2, size * 0.3)
    }

    var body: some View {
        RoundedRectangle(cornerRadius: radius ?? size / 2, style: .continuous)
            .fill(color)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// A tag as an outlined capsule.
struct TagChip: View {
    let tag: Tag?
    var round = false

    var body: some View {
        HStack(spacing: 5) {
            Swatch(tag, size: 7, round: round)
            Text(tagName(tag)).font(.system(size: 12)).lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(Theme.panel, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.line))
        .fixedSize()
    }
}

/// The real icon of an installed app, looked up by bundle identifier.
struct AppIcon: View {
    let bundleID: String
    var size: CGFloat = 20

    private static var cache: [String: NSImage] = [:]

    var body: some View {
        Image(nsImage: Self.icon(for: bundleID))
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }

    private static func icon(for bundleID: String) -> NSImage {
        if let cached = cache[bundleID] { return cached }
        let image: NSImage
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            image = NSWorkspace.shared.icon(forFile: url.path)
        } else {
            image = NSWorkspace.shared.icon(for: .application)
        }
        cache[bundleID] = image
        return image
    }
}

/// A thin proportion bar.
struct Meter: View {
    let fraction: Double
    let color: Color
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.bg)
                Capsule().fill(color).frame(width: max(height, geo.size.width * min(max(fraction, 0), 1)))
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

/// A vertical capsule filled from the bottom with stacked segments.
struct PillColumn: View {
    /// Fractions of the full height, bottom first.
    let segments: [(fraction: Double, color: Color)]
    var width: CGFloat = 18
    var height: CGFloat = 150

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            ForEach(Array(segments.enumerated().reversed()), id: \.offset) { _, segment in
                Rectangle().fill(segment.color)
                    .frame(height: height * min(max(segment.fraction, 0), 1))
            }
        }
        .frame(width: width, height: height)
        .background(Theme.bg)
        .clipShape(RoundedRectangle(cornerRadius: width / 2, style: .continuous))
        .accessibilityHidden(true)
    }
}

/// One horizontal lane of a day: blocks placed by start and length.
struct Lane: View {
    struct Piece: Identifiable {
        let id: Int
        let start: Double
        let length: Double
        let color: Color
        let tip: String
        var opacity: Double = 1
    }

    let pieces: [Piece]
    var height: CGFloat = 26
    var radius: CGFloat = 6
    /// Called with a piece's id when it is clicked.
    var onSelect: ((Int) -> Void)?

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                ForEach(pieces) { piece in
                    RoundedRectangle(cornerRadius: min(radius, 4), style: .continuous)
                        .fill(piece.color.opacity(piece.opacity))
                        .frame(width: max(2, geo.size.width * piece.length - 1.5), height: height)
                        .offset(x: geo.size.width * piece.start)
                        .help(piece.tip)
                        .onTapGesture { onSelect?(piece.id) }
                }
            }
        }
        .frame(height: height)
        .background(Theme.bg)
        .clipShape(RoundedRectangle(cornerRadius: radius + 1, style: .continuous))
    }
}

struct Legend: View {
    let tags: [Tag?]

    var body: some View {
        HStack(spacing: 12) {
            ForEach(Array(tags.enumerated()), id: \.offset) { _, tag in
                HStack(spacing: 6) {
                    Swatch(tag, size: 8)
                    Text(tagName(tag)).font(.system(size: 12)).foregroundStyle(Theme.muted)
                }
            }
        }
    }
}

/// Small grey label, e.g. the kind of a record.
struct Badge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(Theme.muted)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(Theme.bg, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .fixedSize()
    }
}

struct Hairline: View {
    var body: some View { Rectangle().fill(Theme.line).frame(height: 1) }
}

struct EmptyState: View {
    let title: String
    let note: String
    var symbol = "waveform.path.ecg"

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 30, weight: .light)).foregroundStyle(Theme.muted)
            Text(title).font(.system(size: 15, weight: .semibold))
            Text(note).foregroundStyle(Theme.muted).multilineTextAlignment(.center).frame(maxWidth: 380)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The pulse line of the app icon, on a 24-point grid.
struct PulseShape: Shape {
    func path(in rect: CGRect) -> Path {
        let points: [(CGFloat, CGFloat)] = [(2, 12), (6, 12), (9, 4), (14, 20), (17, 12), (22, 12)]
        let unit = min(rect.width, rect.height) / 24
        var path = Path()
        for (index, p) in points.enumerated() {
            let point = CGPoint(x: rect.minX + p.0 * unit, y: rect.minY + p.1 * unit)
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }
}

/// The app's mark: the icon's pulse line on an accent tile.
struct BrandMark: View {
    var size: CGFloat = 28

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(Theme.accent)
            .frame(width: size, height: size)
            .overlay(
                PulseShape()
                    .stroke(Theme.onAccent, style: StrokeStyle(lineWidth: size * 0.085, lineCap: .round, lineJoin: .round))
                    .frame(width: size * 0.66, height: size * 0.66)
            )
            .accessibilityHidden(true)
    }
}

// MARK: Event helpers

extension ActivityEvent {
    /// Second line of a record: file path, URL without scheme, or nothing.
    var detail: String? {
        if let path, !path.isEmpty { return Analyzer.abbreviate(path) }
        if let url, !url.isEmpty {
            return url.replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: "")
        }
        return nil
    }

    var headline: String {
        title.isEmpty || title == appName ? appName : "\(appName) · \(title)"
    }

    var kindName: String {
        if let path, !path.isEmpty { return L("File") }
        if let url, !url.isEmpty { return L("Web page") }
        return title.isEmpty ? L("App") : L("Window")
    }
}

extension Sample {
    var headline: String {
        title.isEmpty || title == appName ? appName : "\(appName) · \(title)"
    }
}

/// Position of a moment inside a span of hours, as a fraction from 0 to 1.
struct DayScale {
    let start: Date
    let hours: ClosedRange<Int>

    /// Covers 08:00 to 20:00, widened to include every record of the day.
    init(day: Date, first: Date?, last: Date?) {
        let calendar = Calendar.current
        let lower = min(8, first.map { calendar.component(.hour, from: $0) } ?? 8)
        var upper = 20
        if let last {
            let hour = calendar.component(.hour, from: last) + 1
            upper = calendar.isDate(last, inSameDayAs: day) ? max(20, hour) : 24
        }
        hours = lower...min(24, upper)
        start = calendar.date(byAdding: .hour, value: lower, to: day) ?? day
    }

    var seconds: Double { Double(hours.count - 1) * 3600 }
    func fraction(_ date: Date) -> Double { date.timeIntervalSince(start) / seconds }
    func length(_ duration: TimeInterval) -> Double { duration / seconds }
    func date(at fraction: Double) -> Date { start.addingTimeInterval(fraction * seconds) }
    /// Hour labels spread evenly, at most `count` of them.
    func labels(step: Int = 2) -> [Int] { Array(stride(from: hours.lowerBound, through: hours.upperBound, by: step)) }
}
