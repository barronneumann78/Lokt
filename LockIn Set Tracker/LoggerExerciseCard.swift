import SwiftUI

/// One exercise's logging card, isolated from the logger's screen-level state:
/// every input is a plain value derived for THIS exercise, and `==` compares
/// exactly those values. A keystroke re-renders only the card (and row) it
/// touched; the every-second workout timer re-renders no cards at all.
///
/// Phase 3 look: name + TARGET chip, the recommended-sets chip and nudge note
/// beneath, then the five-column set table on elevated row surfaces.
struct LoggerExerciseCard: View, Equatable {
    @EnvironmentObject private var exerciseStore: ExerciseStore

    let exercise: String
    let sets: [WorkoutSet]
    let setCount: Int
    /// The primary (next-up) set in this exercise, nil when it lives elsewhere.
    let activeSetIndex: Int?
    /// Focus scoped to this card — nil unless the focused cell is here.
    let focus: LoggerField?
    /// The last matching session's sets for this exercise (previous-set lookups).
    let lastSessionSets: [WorkoutSet]?
    let targetChip: String?
    /// The plan's set count when it differs from the current one — the
    /// "Recommended sets: N" chip restores it in one tap.
    let recommendedSets: Int?
    let nudgeNote: String?
    let isHistoryExpanded: Bool
    /// Recent completed set-lists, newest first — populated only when expanded.
    let history: [[WorkoutSet]]
    let isLastExercise: Bool

    @Binding var draggedExercise: String?
    let addAction: ExerciseDetailPrimaryAddAction
    let onSmartSwap: () -> Void
    let onToggleHistory: () -> Void
    let onAddSet: () -> Void
    let onRemoveSet: () -> Void
    let onSetCountChange: (Int) -> Void
    let onWeightChange: (Int, String) -> Void
    let onRepsChange: (Int, String) -> Void
    let onToggleCompletion: (Int) -> Void
    let onUseLast: (Int) -> Void
    let onFocusChange: (LoggerField, Bool) -> Void
    let onAdvance: (LoggerField) -> Bool

    static func == (lhs: LoggerExerciseCard, rhs: LoggerExerciseCard) -> Bool {
        lhs.exercise == rhs.exercise &&
        lhs.sets == rhs.sets &&
        lhs.setCount == rhs.setCount &&
        lhs.activeSetIndex == rhs.activeSetIndex &&
        lhs.focus == rhs.focus &&
        lhs.lastSessionSets == rhs.lastSessionSets &&
        lhs.targetChip == rhs.targetChip &&
        lhs.recommendedSets == rhs.recommendedSets &&
        lhs.nudgeNote == rhs.nudgeNote &&
        lhs.isHistoryExpanded == rhs.isHistoryExpanded &&
        lhs.history == rhs.history &&
        lhs.isLastExercise == rhs.isLastExercise
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                ExerciseTextNavigationLink(
                    exerciseName: exercise,
                    exercises: exerciseStore.exercises,
                    primaryAddAction: addAction
                ) {
                    Text(exercise)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 6)

                // The one suggestion surface: an applied check-in nudge wins,
                // otherwise the fatigue model's estimate.
                if let targetChip {
                    targetChipView(targetChip)
                }

                ExerciseDragHandle(exerciseName: exercise, draggedExercise: $draggedExercise)
            }

            if recommendedSets != nil || nudgeNote != nil {
                VStack(alignment: .leading, spacing: 6) {
                    if let recommendedSets {
                        RecommendedSetsChip(
                            recommended: recommendedSets,
                            count: Binding(get: { setCount }, set: { onSetCountChange($0) }),
                            font: .caption
                        )
                    }

                    // One line of why behind an applied nudge target ("last one
                    // felt easy") — cleared once the next check-in lands.
                    if let nudgeNote {
                        Text(nudgeNote)
                            .font(.caption)
                            .foregroundStyle(AppTheme.textSecondary)
                            .lineLimit(1)
                    }
                }
            }

            setTable

            rowActions

            if isHistoryExpanded {
                historySection
            }
        }
        .padding(16)
        .glassCard()
    }

    // MARK: - Header chip

    private func targetChipView(_ value: String) -> some View {
        HStack(spacing: 6) {
            Text("TARGET")
                .microLabel()

            Text(value)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(AppTheme.textPrimary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(AppTheme.mutedFill)
        .clipShape(Capsule())
        .overlay {
            Capsule()
                .stroke(AppTheme.cardBorder, lineWidth: 1)
        }
        .fixedSize()
    }

    // MARK: - Set table

    private var setTable: some View {
        VStack(spacing: 6) {
            HStack(spacing: LoggerSetColumns.spacing) {
                Text("SET")
                    .microLabel()
                    .frame(width: LoggerSetColumns.setNumberWidth, alignment: .leading)

                Text("PREV")
                    .microLabel()
                    .frame(width: LoggerSetColumns.previousWidth, alignment: .leading)

                Text("LBS")
                    .microLabel()
                    .frame(maxWidth: .infinity)

                Text("REPS")
                    .microLabel()
                    .frame(maxWidth: .infinity)

                Color.clear
                    .frame(width: LoggerSetColumns.checkWidth, height: 1)
            }
            .padding(.horizontal, LoggerSetColumns.rowHorizontalPadding)
            .padding(.bottom, 2)

            ForEach(0..<setCount, id: \.self) { index in
                setRow(at: index)
            }
        }
    }

    private func setRow(at index: Int) -> some View {
        LoggerSetRow(
            exercise: exercise,
            setIndex: index,
            set: sets[safe: index] ?? WorkoutSet(weight: "", reps: "", completed: false),
            isActive: activeSetIndex == index,
            isPending: activeSetIndex.map { index > $0 } ?? false,
            previous: previousSet(at: index),
            focus: rowFocus(at: index),
            isFinalField: isLastExercise && index == setCount - 1,
            onWeightChange: { onWeightChange(index, $0) },
            onRepsChange: { onRepsChange(index, $0) },
            onToggleCompletion: { onToggleCompletion(index) },
            onUseLast: { onUseLast(index) },
            onFocusChange: { kind, isFocused in onFocusChange(fieldID(index, kind), isFocused) },
            onAdvance: { kind in onAdvance(fieldID(index, kind)) }
        )
        .equatable()
        .id(LoggerField.weight(exercise, index))
    }

    private func fieldID(_ index: Int, _ kind: LoggerFieldKind) -> LoggerField {
        kind == .weight ? .weight(exercise, index) : .reps(exercise, index)
    }

    private func rowFocus(at index: Int) -> LoggerFieldKind? {
        guard let focus, focus.setIndex == index else { return nil }
        return focus.kind
    }

    /// Previous-session set for this row — completed sets only, same
    /// semantics as the logger's `getLastSet`.
    private func previousSet(at index: Int) -> WorkoutSet? {
        guard let previous = lastSessionSets?[safe: index], previous.isCompleted else { return nil }
        return previous
    }

    // MARK: - Quiet row actions (+ Set · − Set · Swap · History)

    private var rowActions: some View {
        HStack(spacing: 18) {
            textAction("+ Set", action: onAddSet)

            textAction("− Set", action: onRemoveSet)
                .disabled(setCount <= 1)
                .opacity(setCount <= 1 ? 0.45 : 1)

            Spacer()

            textAction("Swap", action: onSmartSwap)

            textAction(isHistoryExpanded ? "Hide History" : "History", action: onToggleHistory)
        }
        .padding(.horizontal, 4)
    }

    private func textAction(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(AppTheme.textSecondary)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - History

    @ViewBuilder
    private var historySection: some View {
        if history.isEmpty {
            Text("No history yet")
                .font(.caption)
                .foregroundStyle(AppTheme.textTertiary)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("RECENT")
                    .microLabel()

                ForEach(Array(history.enumerated()), id: \.offset) { item in
                    Text(historySummary(for: item.element))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppTheme.mutedFill)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
        }
    }

    private func historySummary(for sets: [WorkoutSet]) -> String {
        sets.map { "\($0.weight)×\($0.reps)" }.joined(separator: "  ·  ")
    }
}
