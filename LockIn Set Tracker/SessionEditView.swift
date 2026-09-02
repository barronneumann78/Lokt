import SwiftUI

// Correction editor for a finished session, pushed from Home's RECENT rows.
// Fix a number, check a missed set, add the set you did after finishing,
// delete one that never happened — then Save. Not a second logger: no rest
// timers, no targets, no suggestions. All mutations run through
// `SessionEditLogic`; persistence goes through `WorkoutStore.updateSession`.
struct SessionEditView: View {
    @EnvironmentObject private var store: WorkoutStore
    @Environment(\.dismiss) private var dismiss

    private let original: WorkoutSession

    @State private var logs: [String: [WorkoutSet]]
    @State private var date: Date
    @State private var durationMinutesText: String

    init(session: WorkoutSession) {
        original = session
        _logs = State(initialValue: session.logs)
        _date = State(initialValue: session.date)
        _durationMinutesText = State(initialValue: SessionEditLogic.durationMinutesText(forSeconds: session.durationSeconds))
    }

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    sessionCard

                    ForEach(orderedExerciseNames, id: \.self) { exercise in
                        exerciseCard(exercise)
                    }

                    Button("Save Changes") {
                        save()
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.top, 8)
                }
                .padding(.horizontal, AppTheme.screenPadding)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .navigationTitle(original.routineName)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Session date & duration

    private var sessionCard: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Date")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)

                Spacer()

                DatePicker("", selection: $date, displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden()
                    .tint(AppTheme.textPrimary)
            }

            hairline

            HStack {
                Text("Duration")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)

                Spacer()

                TrackerTextField("—", text: $durationMinutesText)
                    .keyboardType(.numberPad)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(AppTheme.textPrimary)
                    .tint(AppTheme.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(width: 72)
                    .background(AppTheme.mutedFill)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                Text("min")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
        .padding(AppTheme.cardPadding)
        .glassCard()
    }

    // MARK: - Exercises

    private func exerciseCard(_ exercise: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(exercise)
                .font(.headline)
                .foregroundStyle(AppTheme.textPrimary)

            ForEach((logs[exercise] ?? []).indices, id: \.self) { index in
                setRow(exercise: exercise, index: index)
            }

            Button {
                logs[exercise] = SessionEditLogic.addingSet(to: logs[exercise] ?? [])
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.caption.weight(.bold))
                    Text("Add Set")
                        .font(.footnote.weight(.semibold))
                }
                .foregroundStyle(AppTheme.textSecondary)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(AppTheme.cardPadding)
        .glassCard()
    }

    private func setRow(exercise: String, index: Int) -> some View {
        HStack(spacing: 10) {
            Text("\(index + 1)")
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(AppTheme.textTertiary)
                .frame(width: 18, alignment: .leading)

            setField(text: fieldBinding(exercise: exercise, index: index, keyPath: \.weight), keyboard: .decimalPad)

            setField(text: fieldBinding(exercise: exercise, index: index, keyPath: \.reps), keyboard: .numberPad)

            checkButton(exercise: exercise, index: index)

            Button {
                logs[exercise] = SessionEditLogic.deletingSet(at: index, from: logs[exercise] ?? [])
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(AppTheme.textTertiary)
                    .frame(width: 28, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func setField(text: Binding<String>, keyboard: UIKeyboardType) -> some View {
        TrackerTextField("0", text: text)
            .keyboardType(keyboard)
            .font(.system(size: 18, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(AppTheme.textPrimary)
            .tint(AppTheme.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity)
            .background(AppTheme.mutedFill)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // Checkmark semantics match the logger: only the explicit check completes
    // a set, and checking needs parseable numbers. Rendered in neutral tones —
    // volt stays reserved for Save on this screen.
    private func checkButton(exercise: String, index: Int) -> some View {
        let isDone = logs[exercise]?[safe: index]?.isCompleted ?? false
        return Button {
            logs[exercise] = SessionEditLogic.togglingCompletion(at: index, in: logs[exercise] ?? [])
        } label: {
            ZStack {
                if isDone {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(AppTheme.textPrimary)
                        .frame(width: 26, height: 26)

                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(AppTheme.backgroundTop)
                } else {
                    Circle()
                        .stroke(AppTheme.textTertiary, lineWidth: 1.5)
                        .frame(width: 22, height: 22)
                }
            }
            .frame(width: 40, height: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Plumbing

    private var orderedExerciseNames: [String] {
        SessionEditLogic.orderedExerciseNames(
            in: logs,
            routine: original.routineID.flatMap { store.routine(withID: $0) }
        )
    }

    private func fieldBinding(exercise: String, index: Int, keyPath: WritableKeyPath<WorkoutSet, String>) -> Binding<String> {
        Binding(
            get: {
                guard let sets = logs[exercise], sets.indices.contains(index) else { return "" }
                return sets[index][keyPath: keyPath]
            },
            set: { newValue in
                guard var sets = logs[exercise], sets.indices.contains(index) else { return }
                sets[index][keyPath: keyPath] = newValue
                logs[exercise] = sets
            }
        )
    }

    private var hairline: some View {
        Rectangle()
            .fill(AppTheme.cardBorder)
            .frame(height: 1)
    }

    private func save() {
        let edited = SessionEditLogic.applyingEdits(
            to: original,
            logs: logs,
            date: date,
            durationMinutesText: durationMinutesText
        )
        store.updateSession(edited)
        dismiss()
    }
}
