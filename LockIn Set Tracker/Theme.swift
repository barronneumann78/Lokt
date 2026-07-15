import SwiftUI

enum AppTheme {
    static let screenPadding: CGFloat = 20
    static let cardPadding: CGFloat = 20
    static let rowPadding: CGFloat = 16
    static let cardCornerRadius: CGFloat = 24
    static let rowCornerRadius: CGFloat = 18
    static let controlCornerRadius: CGFloat = 16

    static let backgroundTop = Color(red: 0.04, green: 0.04, blue: 0.05)
    static let backgroundBottom = Color(red: 0.01, green: 0.01, blue: 0.02)
    static let card = Color(red: 0.09, green: 0.10, blue: 0.11).opacity(0.98)
    static let surface = Color(red: 0.12, green: 0.13, blue: 0.15).opacity(0.98)
    static let surfaceElevated = Color(red: 0.16, green: 0.17, blue: 0.19).opacity(0.98)
    static let fieldBackground = Color(red: 0.11, green: 0.12, blue: 0.14).opacity(0.98)
    static let mutedFill = Color.white.opacity(0.06)
    static let cardBorder = Color.white.opacity(0.08)
    static let primary = Color(red: 0.29, green: 0.62, blue: 1.00)
    static let secondary = Color(red: 0.90, green: 0.55, blue: 0.25)
    static let accent = Color(red: 0.56, green: 0.53, blue: 0.96)
    static let success = Color(red: 0.20, green: 0.61, blue: 0.34)
    static let textPrimary = Color.white
    static let textSecondary = Color(red: 0.70, green: 0.72, blue: 0.76)
}

struct AppBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [AppTheme.backgroundTop, AppTheme.backgroundBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            LinearGradient(
                colors: [Color.white.opacity(0.03), .clear, Color.white.opacity(0.02)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(Color.white.opacity(0.05))
                .frame(width: 180, height: 180)
                .blur(radius: 20)
                .offset(x: 60, y: -40)
        }
        .overlay(alignment: .bottomLeading) {
            Circle()
                .fill(AppTheme.primary.opacity(0.10))
                .frame(width: 220, height: 220)
                .blur(radius: 24)
                .offset(x: -60, y: 80)
        }
        .ignoresSafeArea()
    }
}

struct GlassCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(AppTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous)
                    .stroke(AppTheme.cardBorder, lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.28), radius: 18, x: 0, y: 10)
    }
}

struct SurfaceCardModifier: ViewModifier {
    var cornerRadius: CGFloat = AppTheme.rowCornerRadius
    var border: Color = AppTheme.cardBorder

    func body(content: Content) -> some View {
        content
            .background(AppTheme.surface)
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
            .foregroundColor(.white)
            .tint(AppTheme.primary)
            .background(Color.clear)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    var fill: Color = AppTheme.primary

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(fill.opacity(configuration.isPressed ? 0.82 : 1))
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.rowCornerRadius, style: .continuous))
            .shadow(color: fill.opacity(0.22), radius: 14, x: 0, y: 8)
            .scaleEffect(configuration.isPressed ? 0.99 : 1)
            .animation(.easeOut(duration: 0.18), value: configuration.isPressed)
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
                    .stroke(AppTheme.cardBorder.opacity(0.7), lineWidth: 1)
            }
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

struct TrackerTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<_Label>) -> some View {
        configuration
            .foregroundStyle(AppTheme.textPrimary)
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
                .foregroundStyle(disabled ? AppTheme.textSecondary.opacity(0.45) : AppTheme.textPrimary)
                .frame(width: 34, height: 34)
                .background(disabled ? AppTheme.surface.opacity(0.6) : AppTheme.surfaceElevated)
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
                    .stroke(AppTheme.cardBorder.opacity(0.7), lineWidth: 1)
            }
    }
}
