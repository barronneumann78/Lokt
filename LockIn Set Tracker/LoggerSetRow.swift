import SwiftUI

/// Shared pure helpers for the logger's set grid — one home for the logic the
/// logger view and the extracted card/row all lean on.
enum LoggerSetMath {
    /// Pads with explicit `completed: false` sets (only the checkmark
    /// completes an in-session set) or trims to the preferred count.
    static func resize(sets: [WorkoutSet]?, to count: Int) -> [WorkoutSet] {
        var updatedSets = sets ?? []

        if updatedSets.count < count {
            updatedSets.append(contentsOf: Array(
                repeating: WorkoutSet(weight: "", reps: "", completed: false),
                count: count - updatedSets.count
            ))
        } else if updatedSets.count > count {
            updatedSets = Array(updatedSets.prefix(count))
        }

        return updatedSets
    }

    static func parseWeight(_ weight: String) -> Double? {
        let cleaned = weight
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: "")

        return Double(cleaned)
    }

    /// Completed-volume readout ("—" until a set is checked).
    static func volumeText(sets: [WorkoutSet]?, setCount: Int) -> String {
        let volume = resize(sets: sets, to: setCount).reduce(0.0) { total, set in
            guard set.isCompleted,
                  let weight = parseWeight(set.weight),
                  let reps = Double(set.reps.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                return total
            }
            return total + weight * reps
        }
        guard volume > 0 else { return "—" }
        return Int(volume).formatted(.number.grouping(.automatic))
    }
}

/// Column geometry shared by the set table's header row and every set row, so
/// the SET · PREV · LBS · REPS · check labels sit exactly over their cells.
enum LoggerSetColumns {
    static let spacing: CGFloat = 8
    static let rowHorizontalPadding: CGFloat = 10
    static let setNumberWidth: CGFloat = 24
    static let previousWidth: CGFloat = 58
    static let checkWidth: CGFloat = 36
    static let fieldHeight: CGFloat = 34
}

/// One set row of the logger grid, isolated so a keystroke or focus change
/// re-renders THIS row only: its inputs are the row's own `WorkoutSet` value,
/// its focus coordinate, and minimal context — and `==` compares exactly
/// those, so sibling rows (and cards) skip their bodies entirely.
///
/// Five columns on an elevated row surface: set number · PREV (last session's
/// same set, tappable to copy it) · LBS · REPS · completion check. The active
/// set — the first incomplete one — is tinted with the accent; sets after it
/// wait at reduced opacity.
struct LoggerSetRow: View, Equatable {
    let exercise: String
    let setIndex: Int
    let set: WorkoutSet
    let isActive: Bool
    /// True for sets after the active one in this exercise (rendered dimmed).
    let isPending: Bool
    let previous: WorkoutSet?
    let focus: LoggerFieldKind?
    /// True on the last reps cell of the workout — its Next reads Done.
    let isFinalField: Bool

    let onWeightChange: (String) -> Void
    let onRepsChange: (String) -> Void
    let onToggleCompletion: () -> Void
    let onUseLast: () -> Void
    let onFocusChange: (LoggerFieldKind, Bool) -> Void
    let onAdvance: (LoggerFieldKind) -> Bool

    static func == (lhs: LoggerSetRow, rhs: LoggerSetRow) -> Bool {
        lhs.exercise == rhs.exercise &&
        lhs.setIndex == rhs.setIndex &&
        lhs.set == rhs.set &&
        lhs.isActive == rhs.isActive &&
        lhs.isPending == rhs.isPending &&
        lhs.previous == rhs.previous &&
        lhs.focus == rhs.focus &&
        lhs.isFinalField == rhs.isFinalField
    }

    private var isDone: Bool { self.set.isCompleted }

    var body: some View {
        HStack(spacing: LoggerSetColumns.spacing) {
            Text("\(setIndex + 1)")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(isActive ? AppTheme.primary : AppTheme.textSecondary)
                .frame(width: LoggerSetColumns.setNumberWidth, alignment: .leading)

            previousCell
                .frame(width: LoggerSetColumns.previousWidth, alignment: .leading)

            numericCell(
                text: set.weight,
                kind: .weight,
                keyboard: .decimalPad,
                primaryActionTitle: "Next",
                onTextChange: onWeightChange
            )

            numericCell(
                text: set.reps,
                kind: .reps,
                keyboard: .numberPad,
                primaryActionTitle: isFinalField ? "Done" : "Next",
                onTextChange: onRepsChange
            )

            checkButton
                .frame(width: LoggerSetColumns.checkWidth)
        }
        .padding(.horizontal, LoggerSetColumns.rowHorizontalPadding)
        .padding(.vertical, 6)
        .background(isActive ? AppTheme.activeRowTint : AppTheme.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.rowCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.rowCornerRadius, style: .continuous)
                .stroke(isActive ? AppTheme.primary : AppTheme.cardBorder, lineWidth: 1)
        }
        .opacity(isPending ? 0.55 : 1)
    }

    /// PREV: the same set index from the last session, "—" when there is
    /// none. Tapping copies its numbers into this set (the old "Use last"
    /// line) — the keyboard toolbar's Use Last stays as the other route.
    private var previousCell: some View {
        Button {
            onUseLast()
        } label: {
            Text(previousText)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(previous == nil ? AppTheme.textTertiary : AppTheme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: LoggerSetColumns.fieldHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(previous == nil || isDone)
    }

    private var previousText: String {
        guard let previous else { return "—" }
        return "\(previous.weight)×\(previous.reps)"
    }

    /// Whole-cell numeric field: the padded, filled cell is one native tap
    /// target — tapping anywhere in it focuses the field.
    private func numericCell(
        text: String,
        kind: LoggerFieldKind,
        keyboard: UIKeyboardType,
        primaryActionTitle: String,
        onTextChange: @escaping (String) -> Void
    ) -> some View {
        LoggerNumericField(
            text: text,
            placeholder: "0",
            keyboard: keyboard,
            isActiveStyle: isActive,
            showsUseLast: previous != nil,
            primaryActionTitle: primaryActionTitle,
            isFocused: focus == kind,
            onTextChange: onTextChange,
            onFocusChange: { onFocusChange(kind, $0) },
            onUseLast: onUseLast,
            onAdvance: { onAdvance(kind) }
        )
        .frame(maxWidth: .infinity)
        .frame(height: LoggerSetColumns.fieldHeight)
        .background(AppTheme.fieldBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(focus == kind ? AppTheme.primary : AppTheme.cardBorder, lineWidth: 1)
        }
    }

    /// The checkmark is the single source of truth for set completion.
    /// Completed = filled success circle with a check; incomplete = hairline
    /// circle (accent on the active row).
    private var checkButton: some View {
        Button {
            onToggleCompletion()
        } label: {
            ZStack {
                if isDone {
                    Circle()
                        .fill(AppTheme.success)
                        .frame(width: 26, height: 26)

                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(AppTheme.backgroundTop)
                } else {
                    Circle()
                        .stroke(isActive ? AppTheme.primary : AppTheme.cardBorder, lineWidth: 1)
                        .frame(width: 26, height: 26)
                }
            }
            .frame(width: LoggerSetColumns.checkWidth, height: LoggerSetColumns.fieldHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
