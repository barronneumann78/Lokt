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

    /// Completed-volume readout for the VOL chip ("—" until a set is checked).
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

/// One set row of the logger grid, isolated so a keystroke or focus change
/// re-renders THIS row only: its inputs are the row's own `WorkoutSet` value,
/// its focus coordinate, and minimal context — and `==` compares exactly
/// those, so sibling rows (and cards) skip their bodies entirely.
struct LoggerSetRow: View, Equatable {
    let exercise: String
    let setIndex: Int
    let set: WorkoutSet
    let isActive: Bool
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
        lhs.previous == rhs.previous &&
        lhs.focus == rhs.focus &&
        lhs.isFinalField == rhs.isFinalField
    }

    private var isDone: Bool { self.set.isCompleted }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Text("\(setIndex + 1)")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(isActive ? AppTheme.backgroundTop : AppTheme.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(isActive ? AppTheme.primary : AppTheme.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .frame(width: 30, alignment: .leading)

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
                    .frame(width: 44)
            }

            if let previous, !isDone {
                Button {
                    onUseLast()
                } label: {
                    Text("Use last · \(previous.weight) × \(previous.reps)")
                        .font(.caption.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(AppTheme.textSecondary)
                }
                .buttonStyle(.plain)
                .padding(.leading, 42)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, isActive ? 8 : 0)
        .background(isActive ? AppTheme.surfaceElevated : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
        .background(isActive ? AppTheme.backgroundTop.opacity(0.45) : AppTheme.mutedFill)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    /// The checkmark is the single source of truth for set completion.
    /// Completed = volt check, incomplete = hollow circle (volt on the active row).
    private var checkButton: some View {
        Button {
            onToggleCompletion()
        } label: {
            ZStack {
                if isDone {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(AppTheme.primary)
                        .frame(width: 26, height: 26)

                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(AppTheme.backgroundTop)
                } else {
                    Circle()
                        .stroke(isActive ? AppTheme.primary : AppTheme.textTertiary, lineWidth: 1.5)
                        .frame(width: 22, height: 22)
                }
            }
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
