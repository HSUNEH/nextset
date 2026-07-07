import SwiftUI
import DamSetCore

enum DamSetDesign {
    static let accent = Color(red: 0.20, green: 0.48, blue: 1.0)
    static let mint = Color(red: 0.24, green: 0.78, blue: 0.63)
    static let orange = Color(red: 1.0, green: 0.58, blue: 0.22)
    static let pink = Color(red: 1.0, green: 0.33, blue: 0.58)
    static var appGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.08, green: 0.10, blue: 0.16),
                Color(red: 0.10, green: 0.16, blue: 0.24),
                Color(red: 0.03, green: 0.04, blue: 0.07)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var activeGradient: LinearGradient {
        LinearGradient(
            colors: [accent.opacity(0.95), mint.opacity(0.82)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var warningGradient: LinearGradient {
        LinearGradient(
            colors: [orange.opacity(0.95), pink.opacity(0.82)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

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
            return mint
        case let id where id.contains("legs"):
            return orange
        default:
            return .purple
        }
    }
}

extension View {
    func cardSurface(cornerRadius: CGFloat = 28) -> some View {
        self
            .padding(18)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(.white.opacity(0.16), lineWidth: 1)
            )
    }
}

extension Int {
    /// Seconds rendered as a zero-padded mm:ss string, e.g. 94 → "01:34".
    var minuteSecondText: String {
        String(format: "%02d:%02d", self / 60, self % 60)
    }
}
