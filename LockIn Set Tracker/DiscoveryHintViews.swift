import SwiftUI

/// Tiny text label rendered beside an undiscovered icon button. Neutral gray
/// by design — hints never take volt.
struct DiscoveryHintLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.footnote.weight(.medium))
            .foregroundStyle(AppTheme.textSecondary)
    }
}

/// The `info.circle` link to an exercise profile, with the optional discovery
/// label leading the glyph. Navigation is identical to the bare icon — the
/// hint only decorates it, and the use count rides along without gating
/// anything.
struct ExerciseInfoButton: View {
    let exercise: Exercise
    var hinted: Bool = false

    var body: some View {
        NavigationLink(destination: ExerciseDetailView(exercise: exercise)) {
            HStack(spacing: 5) {
                if hinted {
                    DiscoveryHintLabel(text: "Info")
                }

                Image(systemName: "info.circle")
                    .font(.headline)
                    .foregroundStyle(AppTheme.textPrimary)
            }
        }
        .buttonStyle(.plain)
        .simultaneousGesture(TapGesture().onEnded {
            DiscoveryHints.shared.recordInfoUse()
        })
        .accessibilityLabel("Open \(exercise.name)")
    }
}

/// One-time line above a review exercise list decoding the two icons for new
/// users. Hairline card, gray, dismissible; `DiscoveryHints` guarantees it is
/// offered once ever.
struct DiscoveryNudgeLine: View {
    var onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(Image(systemName: "info.circle")) opens the exercise  ·  \(Image(systemName: "questionmark.bubble")) asks the coach")
                .font(.footnote)
                .foregroundStyle(AppTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.textTertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss hint")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .surfaceCard(cornerRadius: AppTheme.controlCornerRadius)
    }
}
