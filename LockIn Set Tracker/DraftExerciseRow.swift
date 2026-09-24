import SwiftUI

/// The one numbered exercise row shared by the generator and coach draft
/// cards (owner feedback, build 4: "no words should ever be getting cut off
/// or moved to the next line" and "that info button needs to be easier to
/// click"). Line one is the index in a fixed 22pt mono column, the name on
/// its own full-width line — 16pt medium, one line, shrinking to 85% before
/// it would ever wrap — and the info button at the trailing edge: a 22pt
/// glyph inside a 44×44 hit target that pushes the same `ExerciseDetailView`
/// the profile link always did. Line two is "3 sets • 8–10" in 13pt mono,
/// the disclosure chevron when the surface has something behind it, and the
/// ask button. `content` renders beneath, indented to the name: the chips and
/// the open disclosure body, which stay surface-specific. Tapping the row's
/// idle area toggles the disclosure, as the generator card always did.
struct DraftExerciseRow<Content: View>: View {
    let index: Int
    let name: String
    let sets: Int
    let reps: String
    /// The exercise id the chevron and the row's idle tap area toggle.
    let disclosureID: UUID
    @Binding var expandedIDs: Set<UUID>
    /// Whether the row has anything behind its chevron (edit fields, notes).
    let showsDisclosure: Bool
    /// Resolved profile for the info button; nil (an unmatched name) hides it.
    let infoExercise: Exercise?
    let askContext: ExerciseAskContext
    @Binding var askTarget: ExerciseAskContext?
    let askHinted: Bool
    let infoHinted: Bool
    @ViewBuilder let content: () -> Content

    /// Width of the "1." column so names line up down the list.
    private static var indexWidth: CGFloat { 22 }
    private static var indexSpacing: CGFloat { 10 }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            nameLine

            VStack(alignment: .leading, spacing: 6) {
                metaLine
                content()
            }
            .padding(.leading, Self.indexWidth + Self.indexSpacing)
        }
        .exerciseDetailDisclosureTapArea(id: disclosureID, expandedIDs: $expandedIDs, enabled: showsDisclosure)
    }

    private var nameLine: some View {
        HStack(alignment: .center, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: Self.indexSpacing) {
                Text("\(index + 1).")
                    .font(.system(.caption, design: .monospaced).weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(AppTheme.textTertiary)
                    .frame(width: Self.indexWidth, alignment: .leading)

                Text(trimmedName.isEmpty ? "Exercise name" : trimmedName)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(trimmedName.isEmpty ? AppTheme.textTertiary : AppTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .allowsTightening(true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let infoExercise {
                DraftExerciseInfoButton(exercise: infoExercise, hinted: infoHinted)
            }
        }
    }

    private var metaLine: some View {
        HStack(alignment: .center, spacing: 8) {
            Text("\(max(1, sets)) sets • \(reps)")
                .font(.system(size: 13, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(AppTheme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            if showsDisclosure {
                ExerciseDetailDisclosureChevron(
                    id: disclosureID,
                    expandedIDs: $expandedIDs,
                    font: .caption
                )
            }

            Spacer(minLength: 8)

            ExerciseAskButton(
                context: askContext,
                askTarget: $askTarget,
                font: .footnote,
                hinted: askHinted
            )
        }
    }
}

/// The draft row's info button: the same `ExerciseDetailView` push (and
/// discovery-use count) as `ExerciseInfoButton`, restyled for the row — a
/// 22pt `info.circle` in `textSecondary` whose hit area is padded out to
/// 44×44. The matching negative outer padding hands the extra space back to
/// layout, so the glyph occupies only its own footprint at the row's trailing
/// edge while the target overhangs into the card padding and the row gap.
private struct DraftExerciseInfoButton: View {
    let exercise: Exercise
    let hinted: Bool

    private static let glyphSize: CGFloat = 22
    private static let hitSize: CGFloat = 44
    private static var hitPadding: CGFloat { (hitSize - glyphSize) / 2 }

    var body: some View {
        NavigationLink(destination: ExerciseDetailView(exercise: exercise)) {
            HStack(spacing: 5) {
                if hinted {
                    DiscoveryHintLabel(text: "Info")
                }

                Image(systemName: "info.circle")
                    .font(.system(size: Self.glyphSize, weight: .regular))
                    .foregroundStyle(AppTheme.textSecondary)
                    .frame(width: Self.glyphSize, height: Self.glyphSize)
            }
            .padding(Self.hitPadding)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .simultaneousGesture(TapGesture().onEnded {
            DiscoveryHints.shared.recordInfoUse()
        })
        .padding(-Self.hitPadding)
        .accessibilityLabel("Open \(exercise.name)")
    }
}
