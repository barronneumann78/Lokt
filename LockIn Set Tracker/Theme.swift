import SwiftUI

// Dark athletic minimal: near-black canvas, one volt accent, hairline-separated
// flat surfaces, oversized tabular numbers. No gradients, no glows, no shadows.
enum AppTheme {
    static let screenPadding: CGFloat = 20
    static let cardPadding: CGFloat = 20
    static let rowPadding: CGFloat = 16
    static let cardCornerRadius: CGFloat = 22
    static let rowCornerRadius: CGFloat = 14
    static let controlCornerRadius: CGFloat = 14

    // Surfaces — near-black, flat.
    static let backgroundTop = Color(red: 0.043, green: 0.043, blue: 0.047)    // #0B0B0C
    static let backgroundBottom = Color(red: 0.043, green: 0.043, blue: 0.047) // same → flat
    static let card = Color(red: 0.078, green: 0.078, blue: 0.086)             // #141416
    static let surface = Color(red: 0.078, green: 0.078, blue: 0.086)
    static let surfaceElevated = Color(red: 0.110, green: 0.110, blue: 0.122)  // #1C1C1F
    static let fieldBackground = Color(red: 0.110, green: 0.110, blue: 0.122)
    static let mutedFill = Color.white.opacity(0.06)
    static let cardBorder = Color(red: 0.149, green: 0.149, blue: 0.165)       // #26262A hairline

    // THE accent — volt lime. Primary action + live/active state only.
    static let primary = Color(red: 0.839, green: 1.0, blue: 0.247)    // #D6FF3F volt
    static let secondary = Color(red: 1.0, green: 0.722, blue: 0.302)  // #FFB84D warn/amber
    static let accent = Color(red: 0.839, green: 1.0, blue: 0.247)     // = primary
    static let success = Color(red: 0.247, green: 0.878, blue: 0.541)  // #3FE08A good
    static let danger = Color(red: 1.0, green: 0.361, blue: 0.361)     // #FF5C5C

    static let textPrimary = Color(red: 0.957, green: 0.957, blue: 0.961)   // #F4F4F5
    static let textSecondary = Color(red: 0.604, green: 0.604, blue: 0.635) // #9A9AA2
    static let textTertiary = Color(red: 0.369, green: 0.369, blue: 0.400)  // #5E5E66

    // Categorical chart palette — DATA ENCODING ONLY (series identity), never UI
    // chrome. Six hues laddered by lightness inside the allowed warm→green→teal
    // band (blue/purple stay banned), validated against #141416 for contrast and
    // color-vision separation (worst adjacent pair ΔE 12.3 CVD / 16.6 normal).
    // Slot order: volt, teal, gold, green, orange, coral.
    static let chartCategorical: [Color] = [
        Color(red: 0.839, green: 1.0, blue: 0.247),   // #D6FF3F volt
        Color(red: 0.184, green: 0.710, blue: 0.651), // #2FB5A6 teal
        Color(red: 0.965, green: 0.788, blue: 0.290), // #F6C94A gold
        Color(red: 0.122, green: 0.541, blue: 0.298), // #1F8A4C green
        Color(red: 1.0, green: 0.580, blue: 0.251),   // #FF9440 orange
        Color(red: 0.910, green: 0.282, blue: 0.247)  // #E8483F coral
    ]
    /// Neutral series color for "Other" / folded tails.
    static let chartNeutral = Color(red: 0.557, green: 0.557, blue: 0.588)  // #8E8E96
}

struct AppBackground: View {
    var body: some View {
        AppTheme.backgroundTop
            .ignoresSafeArea()
    }
}

// Flat card one shade lighter than the canvas, separated by a 1px hairline.
// Keeps the `glassCard()` name so call sites don't change — no longer glassy.
struct GlassCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(AppTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous)
                    .stroke(AppTheme.cardBorder, lineWidth: 1)
            }
    }
}

struct SurfaceCardModifier: ViewModifier {
    var cornerRadius: CGFloat = AppTheme.rowCornerRadius
    var border: Color = AppTheme.cardBorder

    func body(content: Content) -> some View {
        content
            .background(AppTheme.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(border, lineWidth: 1)
            }
    }
}

extension View {
    func glassCard() -> some View {
        modifier(GlassCardModifier())
    }

    func surfaceCard(cornerRadius: CGFloat = AppTheme.rowCornerRadius, border: Color = AppTheme.cardBorder) -> some View {
        modifier(SurfaceCardModifier(cornerRadius: cornerRadius, border: border))
    }

    func trackerTextEditorStyle() -> some View {
        self
            .foregroundColor(AppTheme.textPrimary)
            .tint(AppTheme.primary)
            .background(Color.clear)
    }

    /// Uppercase tracked micro-label for card headers and stat captions.
    func microLabel(_ color: Color = AppTheme.textTertiary) -> some View {
        self
            .font(.caption2.weight(.semibold))
            .tracking(1.2)
            .foregroundStyle(color)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    var fill: Color = AppTheme.primary

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.bold))
            .foregroundStyle(labelColor)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(fill.opacity(configuration.isPressed ? 0.82 : 1))
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.rowCornerRadius, style: .continuous))
            .overlay {
                if isDarkFill {
                    RoundedRectangle(cornerRadius: AppTheme.rowCornerRadius, style: .continuous)
                        .stroke(AppTheme.cardBorder, lineWidth: 1)
                }
            }
            .scaleEffect(configuration.isPressed ? 0.99 : 1)
            .animation(.easeOut(duration: 0.18), value: configuration.isPressed)
    }

    // Vivid fills (volt / green / amber) demand a near-black label; dark surface
    // fills keep the light label.
    private var isDarkFill: Bool {
        fill == AppTheme.surfaceElevated || fill == AppTheme.surface ||
        fill == AppTheme.card || fill == AppTheme.fieldBackground
    }

    private var labelColor: Color {
        isDarkFill ? AppTheme.textPrimary : AppTheme.backgroundTop
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(AppTheme.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(AppTheme.surfaceElevated.opacity(configuration.isPressed ? 0.82 : 1))
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .stroke(AppTheme.cardBorder, lineWidth: 1)
            }
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

struct TertiaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(AppTheme.textSecondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(AppTheme.mutedFill.opacity(configuration.isPressed ? 1 : 0.9))
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .stroke(AppTheme.cardBorder, lineWidth: 1)
            }
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

struct TrackerTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<_Label>) -> some View {
        configuration
            .foregroundStyle(AppTheme.textPrimary)
            .monospacedDigit()
            .tint(AppTheme.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(AppTheme.fieldBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous)
                    .stroke(AppTheme.cardBorder, lineWidth: 1)
            }
    }
}

struct TrackerStepper: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    let valueText: String

    var body: some View {
        HStack(spacing: 12) {
            stepperButton(systemName: "minus", disabled: value <= range.lowerBound) {
                value = max(range.lowerBound, value - 1)
            }

            Text(valueText)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(AppTheme.textPrimary)
                .frame(minWidth: 72, alignment: .center)

            stepperButton(systemName: "plus", disabled: value >= range.upperBound) {
                value = min(range.upperBound, value + 1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(AppTheme.fieldBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous)
                .stroke(AppTheme.cardBorder, lineWidth: 1)
        }
    }

    private func stepperButton(systemName: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(disabled ? AppTheme.textTertiary : AppTheme.textPrimary)
                .frame(width: 34, height: 34)
                .background(disabled ? AppTheme.surface : AppTheme.surfaceElevated)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

struct TagChip: View {
    let title: String
    var color: Color = AppTheme.primary

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(AppTheme.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(AppTheme.mutedFill)
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .stroke(AppTheme.cardBorder, lineWidth: 1)
            }
    }
}
