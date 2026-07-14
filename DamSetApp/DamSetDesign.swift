import SwiftUI
import DamSetCore

/// A dark strength-training palette inspired by powder-coated racks and
/// satin-finished barbells. Red carries actions; steel stays structural.
enum DamSetDesign {
    /// Equipment red — primary actions and the current working state (#E1262F).
    static let accent = Color(red: 1.0, green: 0.271, blue: 0.227)
    static let accentDeep = Color(red: 0.490, green: 0.035, blue: 0.055)

    /// Satin steel — rules, rims, and quiet structural details.
    static let steel = Color(red: 0.720, green: 0.745, blue: 0.775)
    static let steelMuted = Color(red: 0.390, green: 0.420, blue: 0.455)

    /// Reserved semantic colors so state never depends on red alone.
    static let moss = Color(red: 0.380, green: 0.780, blue: 0.530)
    static let amber = Color(red: 0.950, green: 0.660, blue: 0.220)

    static let screenBackground = Color(red: 0.025, green: 0.032, blue: 0.040)
    static let surface = Color(red: 0.060, green: 0.072, blue: 0.084)
    static let raisedSurface = Color(red: 0.088, green: 0.103, blue: 0.118)
    static let chromeBackground = Color(red: 0.035, green: 0.043, blue: 0.052)
    static let controlFill = Color(red: 0.105, green: 0.120, blue: 0.136)

    static let steelGradient = LinearGradient(
        colors: [
            steel.opacity(0.88),
            Color.white.opacity(0.28),
            steelMuted.opacity(0.82)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let redGradient = LinearGradient(
        colors: [accent, accentDeep],
        startPoint: .top,
        endPoint: .bottom
    )

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
            return steel
        case let id where id.contains("legs"):
            return amber
        default:
            return accent
        }
    }
}

/// Angular panel silhouette borrowed from rack uprights and weight plates.
/// It stays subtle enough to remain a practical app surface.
struct ChamferedRectangle: InsettableShape {
    var cut: CGFloat = 14
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let rect = rect.insetBy(dx: insetAmount, dy: insetAmount)
        guard rect.width > 0, rect.height > 0 else { return Path() }
        let cut = max(0, min(cut, min(rect.width, rect.height) * 0.28))

        var path = Path()
        path.move(to: CGPoint(x: rect.minX + cut, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - cut, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + cut))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - cut))
        path.addLine(to: CGPoint(x: rect.maxX - cut, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + cut, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - cut))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + cut))
        path.closeSubpath()
        return path
    }

    func inset(by amount: CGFloat) -> ChamferedRectangle {
        var copy = self
        copy.insetAmount += amount
        return copy
    }
}

/// Carbon-black backdrop with an extremely quiet rubber-grain cue.
struct GymScreenBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.black,
                    DamSetDesign.screenBackground,
                    Color(red: 0.035, green: 0.027, blue: 0.030)
                ],
                startPoint: .top,
                endPoint: .bottomTrailing
            )

            Canvas { context, size in
                var lines = Path()
                let spacing: CGFloat = 18
                var offset: CGFloat = -size.height
                while offset < size.width {
                    lines.move(to: CGPoint(x: offset, y: 0))
                    lines.addLine(to: CGPoint(x: offset + size.height, y: size.height))
                    offset += spacing
                }
                context.stroke(lines, with: .color(.white.opacity(0.014)), lineWidth: 0.5)
            }

            RadialGradient(
                colors: [DamSetDesign.accent.opacity(0.055), .clear],
                center: .bottom,
                startRadius: 0,
                endRadius: 420
            )
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct GymSectionLabel: View {
    let text: String
    var color: Color = DamSetDesign.accent

    var body: some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(color.opacity(0.9))
                .frame(height: 1.5)
            Text(text.uppercased())
                .font(.caption.weight(.bold))
                .fontWidth(.condensed)
                .tracking(1.4)
                .foregroundStyle(color)
                .fixedSize(horizontal: true, vertical: true)
            Rectangle()
                .fill(color.opacity(0.9))
                .frame(height: 1.5)
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .accessibilityElement(children: .combine)
    }
}

/// A restrained barbell cue: steel shaft with a short knurled grip zone.
struct SteelBarDivider: View {
    var accent: Color? = nil

    var body: some View {
        Image("GymBarbellDivider")
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(maxWidth: .infinity)
            .frame(height: 14)
            .clipped()
            .overlay {
                if let accent {
                    Capsule()
                        .fill(accent.opacity(0.16))
                        .frame(width: 72, height: 2)
                        .blendMode(.plusLighter)
                }
            }
            .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Circular −/+ control with a dark rubber face and a slim steel collar.
struct GlassCircleControl: View {
    let symbol: String
    let label: String
    var size: CGFloat = 56
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.32, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
        }
        .buttonStyle(GymMetalControlButtonStyle(shape: .circle))
        .accessibilityLabel(label)
    }
}

/// Imagen-authored black steel skin. Text and controls remain native SwiftUI
/// content above it, so the artwork never compromises Dynamic Type or input.
private struct GymPanelArtwork: View {
    var accent: Color?
    var cut: CGFloat

    var body: some View {
        Image("GymPanelSkin")
            .resizable(
                capInsets: EdgeInsets(top: 32, leading: 32, bottom: 32, trailing: 32),
                resizingMode: .stretch
            )
            .interpolation(.high)
            .clipShape(ChamferedRectangle(cut: cut))
            .overlay {
                if let accent {
                    ChamferedRectangle(cut: cut)
                        .inset(by: 4)
                        .stroke(accent.opacity(0.72), lineWidth: 0.8)
                }
            }
            .shadow(color: .black.opacity(0.50), radius: 10, y: 6)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// Imagen-authored red powder-coated CTA skin with native label behavior.
private struct GymPrimaryButtonArtwork: View {
    var isPressed: Bool

    var body: some View {
        Image("GymPrimaryButtonSkin")
            .resizable(
                capInsets: EdgeInsets(top: 20, leading: 20, bottom: 20, trailing: 20),
                resizingMode: .stretch
            )
            .interpolation(.high)
            .clipShape(ChamferedRectangle(cut: 12))
            .brightness(isPressed ? -0.09 : 0)
            .shadow(color: DamSetDesign.accent.opacity(0.20), radius: 12, y: 5)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// Imagen-authored rubber-and-steel control face. The live SF Symbol remains
/// separate so disabled, pressed, and accessibility states keep working.
private struct GymRoundControlArtwork: View {
    var isPressed: Bool

    var body: some View {
        Image("GymRoundControlSkin")
            .resizable()
            .scaledToFill()
            .scaleEffect(1.02)
            .clipShape(Circle())
            .brightness(isPressed ? -0.10 : 0)
            .shadow(color: .black.opacity(0.42), radius: 6, y: 3)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

struct GymPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .frame(minHeight: 56)
            .background {
                GymPrimaryButtonArtwork(isPressed: configuration.isPressed)
            }
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(isEnabled ? (configuration.isPressed ? 0.86 : 1) : 0.45)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct GymMetalControlButtonStyle: ButtonStyle {
    enum Shape {
        case circle
        case roundedRectangle
    }

    @Environment(\.isEnabled) private var isEnabled
    var shape: Shape = .roundedRectangle

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .background { background(configuration: configuration) }
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(isEnabled ? 1 : 0.38)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    @ViewBuilder
    private func background(configuration: Configuration) -> some View {
        switch shape {
        case .circle:
            GymRoundControlArtwork(isPressed: configuration.isPressed)
        case .roundedRectangle:
            GymPanelArtwork(accent: nil, cut: 8)
                .brightness(configuration.isPressed ? -0.08 : 0)
        }
    }
}

/// Compact setup-screen stepper: a 36pt visual face inside a 44pt tap target.
/// It deliberately avoids the large Imagen panel skin, whose bevel and shadow
/// are too dense when six controls sit side by side.
struct GymCompactStepperButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                ChamferedRectangle(cut: 7)
                    .fill(configuration.isPressed ? DamSetDesign.surface : DamSetDesign.controlFill)
                    .overlay {
                        ChamferedRectangle(cut: 7)
                            .stroke(DamSetDesign.steel.opacity(0.62), lineWidth: 1)
                    }
                    .padding(4)
            }
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .opacity(isEnabled ? 1 : 0.38)
            .animation(.easeOut(duration: 0.10), value: configuration.isPressed)
    }
}

extension View {
    /// Powder-coated card with a quiet steel rim. An optional color marks the
    /// current interactive card without turning the entire surface bright.
    func cardSurface(cornerRadius: CGFloat = 16, accent: Color? = nil) -> some View {
        self
            .padding(16)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [DamSetDesign.raisedSurface, DamSetDesign.surface],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(
                                accent ?? DamSetDesign.steel.opacity(0.34),
                                lineWidth: accent == nil ? 0.75 : 1.25
                            )
                    }
                    .shadow(color: .black.opacity(0.24), radius: 8, y: 4)
            }
    }

    /// Premium strength-training panel used on the active workout surfaces.
    func gymPanel(
        accent: Color? = nil,
        cut: CGFloat = 14,
        padding: CGFloat = 16
    ) -> some View {
        self
            .padding(padding)
            .background {
                GymPanelArtwork(accent: accent, cut: cut)
            }
    }
}

extension Int {
    /// Seconds rendered as a zero-padded mm:ss string, e.g. 94 → "01:34".
    var minuteSecondText: String {
        String(format: "%02d:%02d", self / 60, self % 60)
    }
}
