import SwiftUI
import DamSetCore
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Wood-and-iron palette expressed through native Liquid Glass materials:
/// warm birch surfaces and oak tints for glass controls — no skeuomorphic
/// textures. Layout language stays native iOS (Apple UI Kit / Toss).
enum DamSetDesign {
    /// Deep oak — primary accent and CTAs (#96683F).
    static let accent = Color(red: 0.588, green: 0.408, blue: 0.247)
    /// Moss green — success / completed states (#6F8F3F).
    static let moss = Color(red: 0.435, green: 0.561, blue: 0.247)
    /// Warm amber — resting / countdown states (#C77B3B).
    static let amber = Color(red: 0.780, green: 0.480, blue: 0.230)

    /// Screen background: light birch in light mode, dark walnut at night.
    static let screenBackground = dynamic(
        light: Color(red: 0.933, green: 0.902, blue: 0.839),
        dark: Color(red: 0.102, green: 0.090, blue: 0.075)
    )

    /// Card / list-row surface on top of the screen background.
    static let surface = dynamic(
        light: Color(red: 1.0, green: 0.992, blue: 0.973),
        dark: Color(red: 0.149, green: 0.129, blue: 0.102)
    )

    /// Neutral warm fill for passive wells sitting on a card surface.
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

/// Round −/+ control: Liquid Glass circle with an oak tint.
struct GlassCircleControl: View {
    let symbol: String
    let label: String
    var size: CGFloat = 56
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.32, weight: .semibold))
                .frame(width: size, height: size)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .tint(DamSetDesign.accent)
        .accessibilityLabel(label)
    }
}

extension View {
    /// Standard card row: warm surface fill, continuous corners, no borders.
    func cardSurface(cornerRadius: CGFloat = 16) -> some View {
        self
            .padding(16)
            .background(DamSetDesign.surface, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

extension Int {
    /// Seconds rendered as a zero-padded mm:ss string, e.g. 94 → "01:34".
    var minuteSecondText: String {
        String(format: "%02d:%02d", self / 60, self % 60)
    }
}
