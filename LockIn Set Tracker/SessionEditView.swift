import SwiftUI

// Correction editor for a finished session, pushed from Home's RECENT rows.
// Fix a number, check a missed set, add the set you did after finishing,
// delete one that never happened — then Save. Not a second logger: no rest
// timers, no targets, no suggestions. All mutations run through
// `SessionEditLogic`; persistence goes through `WorkoutStore.updateSession`.
//
// Look v2: the logger's set-table vocabulary — SET · LBS · REPS · check on
// elevated hairline rows, 34pt numeric cells whose hairline turns accent
// while focused (`LoggerSetColumns` widths, read-only). No PREV column: this
// editor has no previous-session lookup, and adding one would be new logic.
struct SessionEditView: View {
    @EnvironmentObject private var store: WorkoutStore
    @Environment(\.dismiss) private var dismiss

    private let original: WorkoutSession

    @State private var logs: [String: [WorkoutSet]]
    @State private var date: Date
    @State private var durationMinutesText: String

    /// Which numeric cell is first responder — drives the accent hairline.
    private struct EditField: Hashable {
        enum Kind: Hashable {
            case duration
            case weight
            case reps
        }

        let exercise: String
        let index: Int
        let kind: Kind
    }

    @FocusState private var focusedField: EditField?

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
                    header

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
        .dismissKeyboardOnTap()
        .keyboardDoneBar()
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(original.routineName)
                .font(.system(size: 26, weight: .bold))
                .tracking(-0.3)
                .foregroundStyle(AppTheme.textPrimary)

            Text(date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                .font(.system(size: 13))
                .monospacedDigit()
                .foregroundStyle(AppTheme.textSecondary)
        }
        .padding(.bottom, 2)
    }

    // MARK: - Session date & duration

    private var sessionCard: some View {
        VStack(spacing: 12) {
            HStack {
                Text("DATE")
                    .microLabel()

                Spacer()

                DatePicker("", selection: $date, displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden()
                    .tint(AppTheme.textPrimary)
            }

            hairline

            HStack {
                Text("DURATION")
                    .microLabel()

                Spacer()

                numericField(
                    text: $durationMinutesText,
                    keyboard: .numberPad,
                    field: EditField(exercise: "", index: 0, kind: .duration),
                    placeholder: "—"
                )
                .frame(width: 72)

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
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(AppTheme.textPrimary)

            VStack(spacing: 6) {
                columnHeader

                ForEach((logs[exercise] ?? []).indices, id: \.self) { index in
                    setRow(exercise: exercise, index: index)
                }
            }

            Button {
                logs[exercise] = SessionEditLogic.addingSet(to: logs[exercise] ?? [])
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .bold))
                    Text("Add Set")
                }
            }
            .buttonStyle(GhostButtonStyle(isCompact: true))
            .padding(.top, 2)
        }
        .padding(AppTheme.cardPadding)
        .glassCard()
    }

    /// SET · LBS · REPS over the check and delete columns, in the logger's
    /// column widths.
    private var columnHeader: some View {
        HStack(spacing: LoggerSetColumns.spacing) {
            Text("SET")
                .microLabel()
                .frame(width: LoggerSetColumns.setNumberWidth, alignment: .leading)

            Text("LBS")
                .microLabel()
                .frame(maxWidth: .infinity)

            Text("REPS")
                .microLabel()
                .frame(maxWidth: .infinity)

            Color.clear
                .frame(width: LoggerSetColumns.checkWidth, height: 1)

            Color.clear
                .frame(width: Self.deleteWidth, height: 1)
        }
        .padding(.horizontal, LoggerSetColumns.rowHorizontalPadding)
        .padding(.bottom, 2)
    }

    private static let deleteWidth: CGFloat = 24

    private func setRow(exercise: String, index: Int) -> some View {
        HStack(spacing: LoggerSetColumns.spacing) {
            Text("\(index + 1)")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(AppTheme.textSecondary)
                .frame(width: LoggerSetColumns.setNumberWidth, alignment: .leading)

            numericField(
                text: fieldBinding(exercise: exercise, index: index, keyPath: \.weight),
                keyboard: .decimalPad,
                field: EditField(exercise: exercise, index: index, kind: .weight)
            )

            numericField(
                text: fieldBinding(exercise: exercise, index: index, keyPath: \.reps),
                keyboard: .numberPad,
                field: EditField(exercise: exercise, index: index, kind: .reps)
            )

            checkButton(exercise: exercise, index: index)

            Button {
                logs[exercise] = SessionEditLogic.deletingSet(at: index, from: logs[exercise] ?? [])
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(AppTheme.textTertiary)
                    .frame(width: Self.deleteWidth, height: LoggerSetColumns.fieldHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete set \(index + 1)")
        }
        .padding(.horizontal, LoggerSetColumns.rowHorizontalPadding)
        .padding(.vertical, 6)
        .background(AppTheme.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.rowCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.rowCornerRadius, style: .continuous)
                .stroke(AppTheme.cardBorder, lineWidth: 1)
        }
    }

    /// The logger's numeric cell: 34pt on the field fill, 8pt corners, the
    /// hairline turning accent while the cell is first responder.
    private func numericField(
        text: Binding<String>,
        keyboard: UIKeyboardType,
        field: EditField,
        placeholder: String = "0"
    ) -> some View {
        TrackerTextField(placeholder, text: text)
            .keyboardType(keyboard)
            .font(.system(size: 16, weight: .semibold))
            .monospacedDigit()
            .multilineTextAlignment(.center)
            .foregroundStyle(AppTheme.textPrimary)
            .tint(AppTheme.primary)
            .focused($focusedField, equals: field)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity)
            .frame(height: LoggerSetColumns.fieldHeight)
            .background(AppTheme.fieldBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(focusedField == field ? AppTheme.accentHairline : AppTheme.cardBorder, lineWidth: 1)
            }
    }

    // Checkmark semantics match the logger: only the explicit check completes
    // a set, and checking needs parseable numbers. Same glyph as the logger —
    // filled success circle when done, hairline circle otherwise.
    private func checkButton(exercise: String, index: Int) -> some View {
        let isDone = logs[exercise]?[safe: index]?.isCompleted ?? false
        return Button {
            logs[exercise] = SessionEditLogic.togglingCompletion(at: index, in: logs[exercise] ?? [])
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
                        .stroke(AppTheme.cardBorder, lineWidth: 1)
                        .frame(width: 26, height: 26)
                }
            }
            .frame(width: LoggerSetColumns.checkWidth, height: LoggerSetColumns.fieldHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isDone ? "Set \(index + 1) completed" : "Mark set \(index + 1) completed")
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
