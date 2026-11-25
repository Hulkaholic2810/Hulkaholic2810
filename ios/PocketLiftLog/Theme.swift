import SwiftUI
import UIKit

// MARK: - Palettes: strictly monochrome, warm paper and charcoal ink

struct Palette: Equatable {
    let paper, ink, slate, hair, dot: Color
    let night: Bool

    static let day = Palette(paper: Color(hex: 0xF9F8F6), ink: Color(hex: 0x1A1A1A), slate: Color(hex: 0x7A7872),
                             hair: Color(hex: 0xE2E0D8), dot: Color(hex: 0xD3D1C9), night: false)
    static let night = Palette(paper: Color(hex: 0x161614), ink: Color(hex: 0xECEAE4), slate: Color(hex: 0x8F8D86),
                               hair: Color(hex: 0x2D2C28), dot: Color(hex: 0x3A3934), night: true)

    static func of(_ tone: Tone) -> Palette { tone == .night ? .night : .day }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

private struct PaletteKey: EnvironmentKey { static let defaultValue = Palette.day }
private struct PaperKey: EnvironmentKey { static let defaultValue = Paper.grain }

extension EnvironmentValues {
    var palette: Palette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
    var paper: Paper {
        get { self[PaperKey.self] }
        set { self[PaperKey.self] = newValue }
    }
}

// MARK: - Type: JetBrains Mono for numbers and dates, Newsreader for names (bundled, registered at launch)

extension Font {
    static func mono(_ size: CGFloat, medium: Bool = false) -> Font {
        .custom(medium ? "JetBrainsMono-Medium" : "JetBrainsMono-Regular", size: size)
    }
    static func serif(_ size: CGFloat, medium: Bool = false, italic: Bool = false) -> Font {
        .custom(italic ? "Newsreader-Italic" : (medium ? "Newsreader-Medium" : "Newsreader-Regular"), size: size)
    }
}

// MARK: - Paper textures

/// Fine fibre grain, drawn once per tone and tiled.
enum Grain {
    private static var cache: [Bool: UIImage] = [:]

    static func image(night: Bool) -> UIImage {
        if let img = cache[night] { return img }
        let side: CGFloat = 180
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        let base = night ? UIColor(white: 0.95, alpha: 1) : UIColor(red: 0.30, green: 0.27, blue: 0.22, alpha: 1)
        let img = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { ctx in
            var rng = SeededRandom(seed: 7)
            for _ in 0..<26_000 {
                let x = CGFloat(rng.next() % 540) / 3, y = CGFloat(rng.next() % 540) / 3
                let alpha = CGFloat(rng.next() % 1000) / 1000 * (night ? 0.07 : 0.10)
                base.withAlphaComponent(alpha).setFill()
                ctx.fill(CGRect(x: x, y: y, width: 1 / 3, height: 1 / 3))
            }
        }
        cache[night] = img
        return img
    }
}

struct SeededRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return state >> 33
    }
}

struct PaperTexture: View {
    let paper: Paper
    let palette: Palette
    var dotSpacing: CGFloat = 20
    /// Ruled lines are drawn per writing line on the page; swatches pass a spacing to preview them.
    var ruleSpacing: CGFloat?

    var body: some View {
        ZStack {
            palette.paper
            switch paper {
            case .grain:
                Image(uiImage: Grain.image(night: palette.night)).resizable(resizingMode: .tile)
            case .dots:
                Canvas { ctx, size in
                    var y = dotSpacing / 2
                    while y < size.height {
                        var x = dotSpacing / 2
                        while x < size.width {
                            ctx.fill(Path(ellipseIn: CGRect(x: x - 0.9, y: y - 0.9, width: 1.8, height: 1.8)), with: .color(palette.dot))
                            x += dotSpacing
                        }
                        y += dotSpacing
                    }
                }
            case .ruled:
                if let step = ruleSpacing {
                    Canvas { ctx, size in
                        var y = step
                        while y < size.height {
                            ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)), with: .color(palette.hair))
                            y += step
                        }
                    }
                }
            case .plain:
                EmptyView()
            }
        }
    }
}

extension View {
    /// On ruled paper each writing line gets its own rule, so entries sit on the lines.
    func ruledLine(_ on: Bool, _ color: Color) -> some View {
        background(alignment: .bottom) {
            if on { Rectangle().fill(color).frame(height: 1).padding(.bottom, 8) }
        }
    }
}

/// The bracketed choice row used in Settings: [ KG ]  LB
struct Choice<V: Hashable>: View {
    let options: [(V, String)]
    let selection: V
    let pick: (V) -> Void
    @Environment(\.palette) private var pal

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 66), spacing: 0, alignment: .leading)], alignment: .leading, spacing: 0) {
            ForEach(options.indices, id: \.self) { i in
                let option = options[i]
                let on = option.0 == selection
                Button { pick(option.0) } label: {
                    Text(on ? "[ \(option.1) ]" : option.1)
                        .font(.mono(13, medium: on))
                        .foregroundStyle(on ? pal.ink : pal.slate)
                        .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}
