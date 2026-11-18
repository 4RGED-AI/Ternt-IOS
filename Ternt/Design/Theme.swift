import CoreText
import SwiftUI
import UIKit

enum InterFont {
    static func register() {
        guard let url = Bundle.main.url(forResource: "InterVariable", withExtension: "ttf") else { return }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }

    static func uiFont(size: CGFloat, weight: CGFloat) -> UIFont {
        let candidates = ["Inter", "InterVariable", "Inter-Regular"]
        let base = candidates.compactMap { UIFont(name: $0, size: size) }.first
            ?? .systemFont(ofSize: size, weight: .semibold)
        let descriptor = base.fontDescriptor.addingAttributes([
            kCTFontVariationAttribute as UIFontDescriptor.AttributeName: [
                NSNumber(value: 0x77676874): weight
            ]
        ])
        return UIFont(descriptor: descriptor, size: size)
    }

    static func font(size: CGFloat, weight: CGFloat) -> Font {
        Font(uiFont(size: size, weight: weight))
    }

    static func size(of text: String, size: CGFloat, weight: CGFloat, tracking: CGFloat) -> CGSize {
        let measured = (text as NSString).size(withAttributes: [
            .font: uiFont(size: size, weight: weight),
            .kern: tracking
        ])
        return CGSize(width: ceil(measured.width), height: ceil(measured.height * 1.05))
    }
}

enum ThemeChoice: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var preferred: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var interfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .system: .unspecified
        case .light: .light
        case .dark: .dark
        }
    }
}

extension WorkerKind {
    var pill: Color {
        switch self {
        case .driver: Color(red: 0.29, green: 0.46, blue: 0.70)
        case .maid: Color(red: 0.33, green: 0.52, blue: 0.40)
        case .housekeeper: Color(red: 0.20, green: 0.48, blue: 0.50)
        case .nanny: Color(red: 0.58, green: 0.38, blue: 0.56)
        case .cook: Color(red: 0.72, green: 0.46, blue: 0.24)
        }
    }
}

struct Palette: Equatable {
    let canvas: Color
    let surface: Color
    let ink: Color
    let secondary: Color
    let tertiary: Color
    let line: Color
    let fill: Color
    let fillStrong: Color
    let inverse: Color
    let onInverse: Color

    static let light = Palette(
        canvas: Color(white: 0.965),
        surface: .white,
        ink: Color(white: 0.09),
        secondary: Color(white: 0.38),
        tertiary: Color(white: 0.56),
        line: Color(white: 0.86),
        fill: Color(white: 0.94),
        fillStrong: Color(white: 0.89),
        inverse: Color(white: 0.09),
        onInverse: .white
    )

    static let dark = Palette(
        canvas: Color(white: 0.07),
        surface: Color(white: 0.12),
        ink: Color(white: 0.96),
        secondary: Color(white: 0.68),
        tertiary: Color(white: 0.50),
        line: Color(white: 0.28),
        fill: Color(white: 0.16),
        fillStrong: Color(white: 0.22),
        inverse: Color(white: 0.96),
        onInverse: Color(white: 0.09)
    )

    static func resolve(_ scheme: ColorScheme) -> Palette {
        scheme == .dark ? .dark : .light
    }
}

private struct PaletteKey: EnvironmentKey {
    static let defaultValue = Palette.light
}

extension EnvironmentValues {
    var palette: Palette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
}

struct AgentBubble: ViewModifier {
    @Environment(\.palette) private var palette

    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(palette.surface, in: UnevenRoundedRectangle(
                topLeadingRadius: 20,
                bottomLeadingRadius: 6,
                bottomTrailingRadius: 20,
                topTrailingRadius: 20
            ))
            .overlay {
                UnevenRoundedRectangle(
                    topLeadingRadius: 20,
                    bottomLeadingRadius: 6,
                    bottomTrailingRadius: 20,
                    topTrailingRadius: 20
                )
                .stroke(palette.line, lineWidth: 1)
            }
    }
}

struct OwnBubble: ViewModifier {
    @Environment(\.palette) private var palette

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .foregroundStyle(palette.onInverse)
            .background(palette.inverse, in: UnevenRoundedRectangle(
                topLeadingRadius: 20,
                bottomLeadingRadius: 20,
                bottomTrailingRadius: 6,
                topTrailingRadius: 20
            ))
    }
}

extension View {
    func agentBubble() -> some View { modifier(AgentBubble()) }
    func ownBubble() -> some View { modifier(OwnBubble()) }

    func ternField() -> some View {
        modifier(TernFieldChrome())
    }
}

private struct TernFieldChrome: ViewModifier {
    @Environment(\.palette) private var palette

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 14)
            .frame(minHeight: 48)
            .background(palette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(palette.line, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

enum Aurora {
    static let arc: [Color] = [
        Color(red: 1.00, green: 0.30, blue: 0.60),
        Color(red: 0.95, green: 0.27, blue: 0.78),
        Color(red: 0.78, green: 0.32, blue: 0.98),
        Color(red: 0.55, green: 0.40, blue: 1.00),
        Color(red: 0.30, green: 0.52, blue: 1.00),
        Color(red: 0.16, green: 0.70, blue: 0.98),
        Color(red: 0.13, green: 0.84, blue: 0.86),
        Color(red: 0.22, green: 0.90, blue: 0.62),
        Color(red: 0.29, green: 0.93, blue: 0.42)
    ]

    /// The wheel runs pink to green, then the last slice eases green back into pink.
    static var loop: Gradient {
        let count = arc.count
        var stops: [Gradient.Stop] = arc.enumerated().map { index, color in
            .init(color: color, location: Double(index) / Double(count) * 0.9)
        }
        stops.append(.init(color: arc[arc.count - 1], location: 0.9))
        stops.append(.init(color: arc[0], location: 1))
        return Gradient(stops: stops)
    }

    static func color(_ amount: Double) -> Color {
        let span = Double(arc.count - 1)
        let scaled = min(1, max(0, amount)) * span
        let index = min(arc.count - 2, Int(scaled))
        let fraction = scaled - Double(index)
        return arc[index].mix(with: arc[index + 1], by: fraction)
    }
}

/// TRYTERN filled with the northern lights, sweeping from the start of the word to the end.
struct NorthernWord: View {
    var size: CGFloat
    var tracking: CGFloat
    var weight: CGFloat = 560
    var reveal: CGFloat = 1
    var period: Double = 4

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
            let span = max(period, 0.1)
            let cycle = context.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: span) / span
            word
                .foregroundStyle(Color.black.opacity(0.16))
                .overlay {
                    GeometryReader { geo in
                        let width = max(geo.size.width, 1)
                        let colors = Aurora.arc + [Aurora.arc[0]]
                        HStack(spacing: 0) {
                            LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)
                                .frame(width: width, height: geo.size.height)
                            LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)
                                .frame(width: width, height: geo.size.height)
                        }
                        .frame(width: width * 2, height: geo.size.height, alignment: .leading)
                        .fixedSize(horizontal: true, vertical: false)
                        .offset(x: -width * (1 - cycle))
                    }
                    .mask(word)
                }
                .mask(alignment: .leading) {
                    Rectangle()
                        .frame(
                            width: max(0.001, InterFont.size(of: "TRYTERN", size: size, weight: weight, tracking: tracking).width * reveal),
                            height: size * 1.6
                        )
                }
        }
        .fixedSize()
    }

    private var word: some View {
        Text("TRYTERN")
            .font(InterFont.font(size: size, weight: weight))
            .tracking(tracking)
    }
}
