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
                        .font(.title3.weight(.bold))
                        .foregroundStyle(AppTheme.textPrimary)

                    Spacer()

                    Button("Done") {
                        dismiss()
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }

                TrackerTextField("Search exercises", text: $searchText)
                    .textFieldStyle(TrackerTextFieldStyle())
                    .autocorrectionDisabled()

                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 10) {
                        ForEach(filteredExercises) { exercise in
                            exerciseRow(exercise)
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
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
        }
        // Cheap safety net: pick up custom exercises saved elsewhere.
        .onAppear(perform: exerciseStore.reloadCustomExercises)
    }

    private func exerciseRow(_ exercise: Exercise) -> some View {
        let added = isInWorkout(exercise)

        return Button {
            guard !added else { return }
            _ = onAdd(exercise)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(exercise.name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(added ? AppTheme.textTertiary : AppTheme.textPrimary)
                        .multilineTextAlignment(.leading)

                    Text(exercise.muscleGroup.rawValue)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.textTertiary)
                }

                Spacer()

                if added {
                    HStack(spacing: 5) {
                        Image(systemName: "checkmark")
                            .font(.caption.weight(.bold))

                        Text("Added")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(AppTheme.textTertiary)
                } else {
                    Image(systemName: "plus")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }
            .padding(16)
            .surfaceCard()
        }
        .buttonStyle(.plain)
    }
}
