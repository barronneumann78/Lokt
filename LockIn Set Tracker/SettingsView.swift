import SwiftUI

struct SettingsView: View {
    @AppStorage(AIBackendConfiguration.userDefaultsKey) private var aiBackendBaseURL = AIBackendConfiguration.defaultBaseURLString
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var workoutSessions: [WorkoutSession] = []
    @State private var pendingAction: PendingAction?
    @State private var preferredEquipmentText = ""
    @State private var dislikedExercisesText = ""
    @State private var primaryGoalText = ""
    @State private var limitationsText = ""
    @State private var trainingStyleText = ""
    @State private var defaultTimeLimitText = ""

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    aiSection
                    aiPreferencesSection
                    historySection
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 20)
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadWorkoutSessions()
            loadPreferences()
        }
        .alert(item: $pendingAction) { action in
            switch action {
            case .deleteAll:
                return Alert(
                    title: Text("Delete All Workout History?"),
                    message: Text("This will permanently remove every saved workout session."),
                    primaryButton: .destructive(Text("Delete All")) {
                        deleteAllWorkoutHistory()
                    },
                    secondaryButton: .cancel()
                )
            case .deleteExercise(let exercise):
                return Alert(
                    title: Text("Delete \(exercise) History?"),
                    message: Text("This will remove saved history for this exercise from all workout sessions."),
                    primaryButton: .destructive(Text("Delete")) {
                        deleteHistory(for: exercise)
                    },
                    secondaryButton: .cancel()
                )
            }
        }
    }

    private var aiSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("AI BACKEND")
                .microLabel()

            TrackerTextField("Backend URL", text: $aiBackendBaseURL)
                .textFieldStyle(TrackerTextFieldStyle())
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .keyboardType(.URL)

            Button("Reset to Local Default") {
                aiBackendBaseURL = AIBackendConfiguration.defaultBaseURLString
            }
            .buttonStyle(SecondaryButtonStyle())
        }
        .padding(20)
        .glassCard()
    }

    private var aiPreferencesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("AI WORKOUT PREFERENCES")
                .microLabel()

            preferenceField(
                title: "Preferred Equipment",
                placeholder: "Dumbbells, cables, machines",
                text: $preferredEquipmentText
            )

            preferenceField(
                title: "Disliked Exercises",
                placeholder: "Burpees, upright rows, barbell back squat",
                text: $dislikedExercisesText
            )

            multilinePreferenceField(
                title: "Injuries or Limitations",
                placeholder: "Sensitive shoulders, avoid deep knee flexion, low back gets irritated",
                text: $limitationsText
            )

            preferenceField(
                title: "Primary Goal",
                placeholder: "Build muscle, get stronger, general fitness",
                text: $primaryGoalText
            )

            preferenceField(
                title: "Training Style",
                placeholder: "Hypertrophy-focused, simple compounds first, higher reps",
                text: $trainingStyleText
            )

            preferenceField(
                title: "Default Time Limit (minutes)",
                placeholder: "45",
                text: $defaultTimeLimitText,
                keyboardType: .numberPad
            )

            HStack(spacing: 12) {
                Button("Save Preferences") {
                    savePreferences()
                }
                .buttonStyle(PrimaryButtonStyle(fill: AppTheme.accent))

                Button("Retake Quiz") {
                    retakeQuiz()
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
        .padding(20)
        .glassCard()
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("WORKOUT HISTORY")
                .microLabel()

            Button {
                pendingAction = .deleteAll
            } label: {
                HStack {
                    Text("Delete All History")
                        .font(.headline)
                        .foregroundStyle(AppTheme.danger)

                    Spacer()

                    Image(systemName: "trash")
                        .foregroundStyle(AppTheme.danger)
                }
                .padding(14)
                .background(AppTheme.mutedFill)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.rowCornerRadius, style: .continuous))
            }
            .buttonStyle(.plain)

            if !exerciseNames.isEmpty {
                Text("DELETE ONE EXERCISE")
                    .microLabel()
                    .padding(.top, 6)

                ForEach(exerciseNames, id: \.self) { exercise in
                    Button {
                        pendingAction = .deleteExercise(exercise)
                    } label: {
                        HStack {
                            Text(exercise)
                                .font(.headline)
                                .foregroundStyle(AppTheme.textPrimary)

                            Spacer()

                            Image(systemName: "minus.circle")
                                .foregroundStyle(AppTheme.secondary)
                        }
                        .padding(14)
                        .background(AppTheme.mutedFill)
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.rowCornerRadius, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(20)
        .glassCard()
    }

    private var exerciseNames: [String] {
        let names = workoutSessions.flatMap { Array($0.logs.keys) }
        return Array(Set(names)).sorted()
    }

    private func loadWorkoutSessions() {
        if let data = UserDefaults.standard.data(forKey: "workoutSessions"),
           let decoded = try? JSONDecoder().decode([WorkoutSession].self, from: data) {
            workoutSessions = decoded
        } else {
            workoutSessions = []
        }
    }

    private func loadPreferences() {
        let preferences = AIUserPreferencesStore.load()
        preferredEquipmentText = preferences.preferredEquipment.joined(separator: ", ")
        dislikedExercisesText = preferences.dislikedExercises.joined(separator: ", ")
        primaryGoalText = preferences.primaryGoal
        limitationsText = preferences.limitations
        trainingStyleText = preferences.trainingStyle
        defaultTimeLimitText = preferences.defaultTimeLimitMinutes.map(String.init) ?? ""
    }

    private func savePreferences() {
        let preferences = AIUserPreferences.fromForm(
            preferredEquipmentText: preferredEquipmentText,
            dislikedExercisesText: dislikedExercisesText,
            primaryGoal: primaryGoalText,
            limitations: limitationsText,
            trainingStyle: trainingStyleText,
            defaultTimeLimitText: defaultTimeLimitText
        )

        AIUserPreferencesStore.save(preferences)
        loadPreferences()
    }

    private func retakeQuiz() {
        // Returning to the quiz is handled at the app root, which swaps back to
        // OnboardingView whenever this flag is false. Finishing (or skipping) the
        // quiz sets it true again.
        hasCompletedOnboarding = false
    }

    private func saveWorkoutSessions(_ sessions: [WorkoutSession]) {
        if let encoded = try? JSONEncoder().encode(sessions) {
            UserDefaults.standard.set(encoded, forKey: "workoutSessions")
        }
        workoutSessions = sessions
    }

    private func deleteAllWorkoutHistory() {
        UserDefaults.standard.removeObject(forKey: "workoutSessions")
        workoutSessions = []
    }

    private func deleteHistory(for exercise: String) {
        let updatedSessions = workoutSessions.compactMap { session -> WorkoutSession? in
            var updatedSession = session
            updatedSession.logs.removeValue(forKey: exercise)
            return updatedSession.logs.isEmpty ? nil : updatedSession
        }

        saveWorkoutSessions(updatedSessions)
    }

    private func preferenceField(
        title: String,
        placeholder: String,
        text: Binding<String>,
        keyboardType: UIKeyboardType = .default
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)

            TrackerTextField(placeholder, text: text)
                .textFieldStyle(TrackerTextFieldStyle())
                .keyboardType(keyboardType)
        }
    }

    private func multilinePreferenceField(
        title: String,
        placeholder: String,
        text: Binding<String>
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous)
                    .fill(AppTheme.fieldBackground)

                if text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(placeholder)
                        .font(.body)
                        .foregroundStyle(AppTheme.textSecondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                }

                TextEditor(text: text)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 92)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .trackerTextEditorStyle()
            }
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous)
                    .stroke(AppTheme.cardBorder, lineWidth: 1)
            }
        }
    }
}

private enum PendingAction: Identifiable {
    case deleteAll
    case deleteExercise(String)

    var id: String {
        switch self {
        case .deleteAll:
            return "deleteAll"
        case .deleteExercise(let exercise):
            return exercise
        }
    }
}
