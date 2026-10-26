import SwiftUI

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
        canvas: Color(red: 0.953, green: 0.949, blue: 0.937),
        surface: .white,
        ink: Color(red: 0.078, green: 0.078, blue: 0.078),
        secondary: Color(red: 0.369, green: 0.369, blue: 0.361),
        tertiary: Color(red: 0.557, green: 0.557, blue: 0.541),
        line: Color(red: 0.894, green: 0.890, blue: 0.871),
        fill: Color(red: 0.925, green: 0.922, blue: 0.902),
        fillStrong: Color(red: 0.886, green: 0.882, blue: 0.859),
        inverse: Color(red: 0.086, green: 0.086, blue: 0.086),
        onInverse: Color(red: 0.969, green: 0.965, blue: 0.953)
    )

    static let dark = Palette(
        canvas: Color(red: 0.055, green: 0.055, blue: 0.051),
        surface: Color(red: 0.090, green: 0.090, blue: 0.086),
        ink: Color(red: 0.957, green: 0.953, blue: 0.941),
        secondary: Color(red: 0.690, green: 0.686, blue: 0.663),
        tertiary: Color(red: 0.486, green: 0.486, blue: 0.463),
        line: Color(red: 0.165, green: 0.165, blue: 0.153),
        fill: Color(red: 0.141, green: 0.141, blue: 0.133),
        fillStrong: Color(red: 0.180, green: 0.180, blue: 0.169),
        inverse: Color(red: 0.957, green: 0.953, blue: 0.941),
        onInverse: Color(red: 0.078, green: 0.078, blue: 0.078)
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
    }
}
