import SwiftUI

/// Mid-workout "Add Exercise" picker: search the shared library and tap a row
/// to append it to the CURRENT session. Stays open so several adds are one
/// flow; exercises already in the workout show a quiet "Added" state instead
/// of duplicating. Search reuses the library's alias-aware approach — folded
/// name keys, live alias prefixes ("pec deck"), and the fuzzy matcher's
/// verdict — never a plain `contains` reinvention.
struct WorkoutAddExercisePicker: View {
    /// Exercise names currently in the session (routine + session-added).
    let currentExerciseNames: [String]
    let onAdd: (Exercise) -> AddExerciseResult

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var exerciseStore: ExerciseStore
    @State private var searchText = ""

    private var filteredExercises: [Exercise] {
        let exercises = exerciseStore.exercises
        let searchKeys = exerciseStore.searchKeys

        // Per-keystroke work happens ONCE here, not per exercise (same shape
        // as ExerciseLibraryView): fold the query, collect alias targets, and
        // take the memoized fuzzy matcher's verdict.
        let query = ExerciseAliases.searchFold(searchText)
        var aliasTargets: Set<String> = []
        var fuzzyTargetName: String?
        if !query.isEmpty {
            aliasTargets = ExerciseAliases.canonicalNames(matchingPrefix: searchText)
            fuzzyTargetName = exercises.resolvedExercise(named: searchText)?.name
        }

        var result: [Exercise] = []
        for (index, exercise) in exercises.enumerated() {
            let matchesSearch = query.isEmpty
                || (index < searchKeys.count && searchKeys[index].contains(query))
                || aliasTargets.contains(exercise.name)
                || exercise.name == fuzzyTargetName
            if matchesSearch {
                result.append(exercise)
            }
        }
        return result
    }

    private func isInWorkout(_ exercise: Exercise) -> Bool {
        currentExerciseNames.contains {
            $0.caseInsensitiveCompare(exercise.name) == .orderedSame
        }
    }

    var body: some View {
        ZStack {
            AppBackground()

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Add Exercise")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(AppTheme.textPrimary)

                    Spacer()

                    Button("Done") {
                        dismiss()
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }

                TrackerSearchField("Search exercises", text: $searchText)

                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(filteredExercises.enumerated()), id: \.element.id) { item in
                            if item.offset > 0 {
                                Rectangle()
                                    .fill(AppTheme.cardBorder)
                                    .frame(height: 1)
                            }

                            exerciseRow(item.element)
                        }

                        if filteredExercises.isEmpty {
                            Text("No exercises match that search.")
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.textSecondary)
                                .padding(.vertical, 12)
                        }
                    }
                    .padding(.bottom, 20)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .padding(.horizontal, AppTheme.screenPadding)
            .padding(.top, 24)
        }
        .dismissKeyboardOnTap()
        // Cheap safety net: pick up custom exercises saved elsewhere.
        .onAppear(perform: exerciseStore.reloadCustomExercises)
    }

    /// Hairline row: 16pt name over a muscle chip; a plus on the right, or
    /// the quiet Added chip once the exercise is already in the session.
    private func exerciseRow(_ exercise: Exercise) -> some View {
        let added = isInWorkout(exercise)

        return Button {
            guard !added else { return }
            _ = onAdd(exercise)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(exercise.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(added ? AppTheme.textTertiary : AppTheme.textPrimary)
                        .multilineTextAlignment(.leading)

                    TagChip(title: exercise.muscleGroup.rawValue)
                }

                Spacer()

                if added {
                    TagChip(title: "Added", systemImage: "checkmark")
                } else {
                    Image(systemName: "plus")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.textSecondary)
                        .frame(width: 34, height: 34)
                        .background(AppTheme.surfaceElevated)
                        .clipShape(Circle())
                        .overlay {
                            Circle()
                                .stroke(AppTheme.cardBorder, lineWidth: 1)
                        }
                }
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(added ? "\(exercise.name), already in this workout" : "Add \(exercise.name)")
    }
}
