import SwiftUI
import DamSetCore
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Wood-and-iron design tokens: warm birch surfaces with oak-brown accents
/// (wooden training gear) over near-black iron text — instead of gradients
/// and glass chrome. Layout language stays native iOS (Apple UI Kit / Toss).
enum DamSetDesign {
    /// Deep oak — primary accent and CTAs (#96683F).
    static let accent = Color(red: 0.588, green: 0.408, blue: 0.247)
    /// Moss green — success / completed states (#6F8F3F).
    static let moss = Color(red: 0.435, green: 0.561, blue: 0.247)
    /// Warm amber — resting / countdown states (#C77B3B).
    static let amber = Color(red: 0.780, green: 0.480, blue: 0.230)

    /// Screen background: light birch in light mode, dark walnut at night.
    static let screenBackground = dynamic(
        light: Color(red: 0.961, green: 0.937, blue: 0.890),
        dark: Color(red: 0.102, green: 0.090, blue: 0.075)
    )

    /// Card / list-row surface on top of the screen background.
    static let surface = dynamic(
        light: Color(red: 1.0, green: 0.992, blue: 0.973),
        dark: Color(red: 0.149, green: 0.129, blue: 0.102)
    )

    /// Neutral warm fill for controls sitting on a card surface.
    static var controlFill: Color { accent.opacity(0.12) }

    static func routineSymbol(for routine: RoutineTemplate) -> String {
        switch routine.routineId {
        case let id where id.contains("push"):
            return "figure.strengthtraining.traditional"
        case let id where id.contains("pull"):
            return "dumbbell.fill"
        case let id where id.contains("legs"):
            return "figure.run"
        default:
            return "dumbbell.fill"
        }
    }

    static func routineTint(for routine: RoutineTemplate) -> Color {
        switch routine.routineId {
        case let id where id.contains("push"):
            return accent
        case let id where id.contains("pull"):
            return moss
        case let id where id.contains("legs"):
            return amber
        default:
            return accent
        }
    }

    private static func dynamic(light: Color, dark: Color) -> Color {
        #if os(iOS)
        Color(UIColor { trait in
            trait.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
        #else
        Color(NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(dark) : NSColor(light)
        })
        #endif
    }
}

extension DamSetDesign {
    /// Chrome barbell-bar finish: vertical specular banding like light down a
    /// polished steel bar.
    static let steel = LinearGradient(
        stops: [
            .init(color: Color(red: 0.95, green: 0.95, blue: 0.96), location: 0.0),
            .init(color: Color(red: 0.79, green: 0.80, blue: 0.82), location: 0.18),
            .init(color: Color(red: 0.56, green: 0.57, blue: 0.60), location: 0.42),
            .init(color: Color(red: 0.73, green: 0.74, blue: 0.76), location: 0.52),
            .init(color: Color(red: 0.49, green: 0.50, blue: 0.53), location: 0.68),
            .init(color: Color(red: 0.78, green: 0.79, blue: 0.81), location: 0.88),
            .init(color: Color(red: 0.62, green: 0.63, blue: 0.66), location: 1.0)
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    /// Cast-iron plate face: dark radial falloff like the dumbbell discs.
    static let ironPlate = RadialGradient(
        colors: [
            Color(red: 0.27, green: 0.27, blue: 0.29),
            Color(red: 0.13, green: 0.13, blue: 0.14)
        ],
        center: .init(x: 0.35, y: 0.3),
        startRadius: 2,
        endRadius: 46
    )

    static let ironText = Color(red: 0.10, green: 0.10, blue: 0.11)
}

/// Deterministic pseudo-random stream so the wood grain is stable frame to frame.
private struct GrainRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed &* 0x9E3779B97F4A7C15 &+ 1 }
    mutating func next() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double(state >> 11) / Double(UInt64.max >> 11)
    }
    mutating func next(in range: ClosedRange<Double>) -> CGFloat {
        CGFloat(range.lowerBound + next() * (range.upperBound - range.lowerBound))
    }
}

/// Subtle procedural wood grain: long wavy strokes in a darker oak, low
/// opacity, drawn once per card size.
struct WoodGrainOverlay: View {
    var body: some View {
        Canvas { context, size in
            var rng = GrainRandom(seed: 7)
            let spacing: CGFloat = 11
            var y: CGFloat = rng.next(in: 2...8)
            while y < size.height {
                var path = Path()
                var x: CGFloat = -4
                var currentY = y + rng.next(in: -1.5...1.5)
                path.move(to: CGPoint(x: x, y: currentY))
                while x < size.width {
                    let step = rng.next(in: 34...80)
                    let drift = rng.next(in: -2.4...2.4)
                    let control = CGPoint(x: x + step / 2, y: currentY + rng.next(in: -3.2...3.2))
                    x += step
                    currentY += drift
                    path.addQuadCurve(to: CGPoint(x: x, y: currentY), control: control)
                }
                context.stroke(
                    path,
                    with: .color(Color(red: 0.42, green: 0.28, blue: 0.16).opacity(rng.next(in: 0.028...0.062))),
                    lineWidth: rng.next(in: 0.6...1.4)
                )
                y += spacing + rng.next(in: -3...4)
            }
        }
        .allowsHitTesting(false)
    }
}

/// Primary CTA drawn as a chromed steel bar: specular gradient, hairline
/// highlight, iron-black label.
struct SteelBarButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var cornerRadius: CGFloat = 16

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(DamSetDesign.ironText)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(DamSetDesign.steel)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [.white.opacity(0.9), .white.opacity(0.1), .black.opacity(0.25)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 1
                            )
                    )
            )
            .opacity(isEnabled ? (configuration.isPressed ? 0.82 : 1) : 0.45)
    }
}

/// Round control rendered as a cast-iron plate: dark radial face, inner
/// groove ring, white glyph.
struct IronPlateControl: View {
    let symbol: String
    let label: String
    var size: CGFloat = 56
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.34, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(DamSetDesign.ironPlate, in: Circle())
                .overlay(
                    Circle()
                        .inset(by: size * 0.14)
                        .stroke(.white.opacity(0.10), lineWidth: 1)
                )
                .overlay(
                    Circle()
                        .strokeBorder(.white.opacity(0.14), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

extension View {
    /// Standard card row: warm surface with a faint wood grain, continuous
    /// corners, no borders.
    func cardSurface(cornerRadius: CGFloat = 16) -> some View {
        self
            .padding(16)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(DamSetDesign.surface)
                    .overlay {
                        WoodGrainOverlay()
                            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    }
            }
    }
}

extension Int {
    /// Seconds rendered as a zero-padded mm:ss string, e.g. 94 → "01:34".
    var minuteSecondText: String {
        String(format: "%02d:%02d", self / 60, self % 60)
    }
}
