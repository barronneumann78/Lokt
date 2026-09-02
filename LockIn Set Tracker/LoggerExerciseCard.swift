import SwiftUI

/// One exercise's logging card, isolated from the logger's screen-level state:
/// every input is a plain value derived for THIS exercise, and `==` compares
/// exactly those values. A keystroke re-renders only the card (and row) it
/// touched; the every-second workout timer re-renders no cards at all.
struct LoggerExerciseCard: View, Equatable {
    @EnvironmentObject private var exerciseStore: ExerciseStore

    let exercise: String
    let sets: [WorkoutSet]
    let setCount: Int
    let isActiveExercise: Bool
    /// The primary (next-up) set in this exercise, nil when it lives elsewhere.
    let activeSetIndex: Int?
    /// Focus scoped to this card — nil unless the focused cell is here.
    let focus: LoggerField?
    /// The last matching session's sets for this exercise (previous-set lookups).
    let lastSessionSets: [WorkoutSet]?
    let lastSummary: String?
    let targetChip: String?
    let oneRM: Int?
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
        lhs.isActiveExercise == rhs.isActiveExercise &&
        lhs.activeSetIndex == rhs.activeSetIndex &&
        lhs.focus == rhs.focus &&
        lhs.lastSessionSets == rhs.lastSessionSets &&
        lhs.lastSummary == rhs.lastSummary &&
        lhs.targetChip == rhs.targetChip &&
        lhs.oneRM == rhs.oneRM &&
        lhs.nudgeNote == rhs.nudgeNote &&
        lhs.isHistoryExpanded == rhs.isHistoryExpanded &&
        lhs.history == rhs.history &&
        lhs.isLastExercise == rhs.isLastExercise
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        if isActiveExercise {
                            Text("ACTIVE")
                                .microLabel(AppTheme.primary)
                        }

                        ExerciseTextNavigationLink(
                            exerciseName: exercise,
                            exercises: exerciseStore.exercises,
                            primaryAddAction: addAction
                        ) {
                            Text(exercise)
                                .font(.title3.weight(.bold))
                                .foregroundStyle(AppTheme.textPrimary)
                        }
                    }

                    Spacer()

                    ExerciseDragHandle(exerciseName: exercise, draggedExercise: $draggedExercise)
                }

                HStack(spacing: 8) {
                    Button("Smart Swap") {
                        onSmartSwap()
                    }
                    .buttonStyle(SecondaryButtonStyle())

                    Button(isHistoryExpanded ? "Hide History" : "History") {
                        onToggleHistory()
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
            }

            setTable

            HStack(spacing: 10) {
                Button {
                    onAddSet()
                } label: {
                    Label("Add Set", systemImage: "plus")
                }
                .buttonStyle(SecondaryButtonStyle())

                Button {
                    onRemoveSet()
                } label: {
                    Label("Delete Set", systemImage: "minus")
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(setCount <= 1)
                .opacity(setCount <= 1 ? 0.55 : 1)

                Spacer()
            }

            statChips

            // One line of why behind an applied nudge target ("last one felt
            // easy") — cleared automatically once the next check-in lands.
            if let nudgeNote {
                Text(nudgeNote)
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineLimit(2)
            }

            if isHistoryExpanded {
                historySection
            }
        }
        .padding(20)
        .glassCard()
    }

    // MARK: - Set table

    private var setTable: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("SET")
                    .microLabel()
                    .frame(width: 30, alignment: .leading)

                Text("WEIGHT")
                    .microLabel()
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text("REPS")
                    .microLabel()
                    .frame(maxWidth: .infinity, alignment: .leading)

                Color.clear
                    .frame(width: 44, height: 1)
            }
            .padding(.bottom, 8)

            hairline

            ForEach(0..<setCount, id: \.self) { index in
                setRow(at: index)

                if index < setCount - 1 {
                    hairline
                }
            }
        }
    }

    private func setRow(at index: Int) -> some View {
        LoggerSetRow(
            exercise: exercise,
            setIndex: index,
            set: sets[safe: index] ?? WorkoutSet(weight: "", reps: "", completed: false),
            isActive: activeSetIndex == index,
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

    // MARK: - Stat chips

    private var statChips: some View {
        HStack(spacing: 10) {
            statChip(label: "LAST", value: lastSummary ?? "—")

            // The one suggestion surface: an applied check-in nudge wins,
            // otherwise the fatigue model's estimate as before.
            if let targetChip {
                statChip(label: "TARGET", value: targetChip)
            }

            if let oneRM {
                statChip(label: "1RM", value: "\(oneRM) lb")
            }

            statChip(label: "VOL", value: LoggerSetMath.volumeText(sets: sets, setCount: setCount))
        }
    }

    private func statChip(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .microLabel()
                .lineLimit(1)

            Text(value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(AppTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(AppTheme.mutedFill)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var hairline: some View {
        Rectangle()
            .fill(AppTheme.cardBorder)
            .frame(height: 1)
    }

    // MARK: - History

    @ViewBuilder
    private var historySection: some View {
        if history.isEmpty {
            Text("No history yet for this exercise.")
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text("RECENT HISTORY")
                    .microLabel()

                ForEach(Array(history.enumerated()), id: \.offset) { item in
                    let sets = item.element

                    VStack(alignment: .leading, spacing: 5) {
                        Text("Workout \(item.offset + 1)")
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(AppTheme.textSecondary)

                        Text(historySummary(for: sets))
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppTheme.mutedFill)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
            .padding(.top, 6)
        }
    }

    private func historySummary(for sets: [WorkoutSet]) -> String {
        sets.enumerated()
            .map { "Set \($0.offset + 1): \($0.element.weight) x \($0.element.reps)" }
            .joined(separator: "  •  ")
    }
}
