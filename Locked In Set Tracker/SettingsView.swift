import SwiftUI

struct SettingsView: View {
    @AppStorage(AIBackendConfiguration.userDefaultsKey) private var aiBackendBaseURL = AIBackendConfiguration.defaultBaseURLString
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
                    headerSection
                    aiSection
                    aiPreferencesSection
                    deleteAllSection
                    exerciseHistorySection
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

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Settings")
                .font(.system(size: 30, weight: .black, design: .rounded))
                .foregroundStyle(AppTheme.textPrimary)

            Text("Manage workout history and the app services that power your tracker.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)

            Text("Your AI workout preferences stay on this device and help future drafts feel more like your style.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
        }
        .padding(20)
        .glassCard()
    }

    private var aiSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("AI Backend")
                .font(.title3.weight(.bold))
                .foregroundStyle(AppTheme.textPrimary)

            Text("The app sends workout prompts, voice transcriptions, and photo imports here, and the backend keeps your OpenAI API key off the device.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)

            TextField("Backend URL", text: $aiBackendBaseURL)
                .textFieldStyle(TrackerTextFieldStyle())
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .keyboardType(.URL)

            Text("For local simulator testing, the app prefers http://127.0.0.1:8788 and also tries the common local fallback ports automatically.")
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)

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
            Text("AI Workout Preferences")
                .font(.title3.weight(.bold))
                .foregroundStyle(AppTheme.textPrimary)

            Text("Set a few standing preferences so Lokt can shape workouts around your normal setup and constraints.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)

            preferenceField(
                title: "Preferred Equipment",
                placeholder: "Dumbbells, cables, machines",
                text: $preferredEquipmentText,
                helpText: "Comma-separated. Used when the prompt does not fully specify equipment."
            )

            preferenceField(
                title: "Disliked Exercises",
                placeholder: "Burpees, upright rows, barbell back squat",
                text: $dislikedExercisesText,
                helpText: "Comma-separated. Lokt will try to avoid these when possible."
            )

            multilinePreferenceField(
                title: "Injuries or Limitations",
                placeholder: "Sensitive shoulders, avoid deep knee flexion, low back gets irritated",
                text: $limitationsText,
                helpText: "Short plain-English notes are enough."
            )

            preferenceField(
                title: "Primary Goal",
                placeholder: "Build muscle, get stronger, general fitness",
                text: $primaryGoalText,
                helpText: "Used when your prompt does not clearly state the goal."
            )

            preferenceField(
                title: "Training Style",
                placeholder: "Hypertrophy-focused, simple compounds first, higher reps",
                text: $trainingStyleText,
                helpText: "Describe how you usually like your sessions programmed."
            )

            preferenceField(
                title: "Default Time Limit",
                placeholder: "45",
                text: $defaultTimeLimitText,
                helpText: "Optional minutes. Used when you do not mention time.",
                keyboardType: .numberPad
            )

            HStack(spacing: 12) {
                Button("Save Preferences") {
                    savePreferences()
                }
                .buttonStyle(PrimaryButtonStyle(fill: AppTheme.accent))

                Button("Reset") {
                    resetPreferences()
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
        .padding(20)
        .glassCard()
    }

    private var deleteAllSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Workout History")
                .font(.title3.weight(.bold))
                .foregroundStyle(AppTheme.textPrimary)

            Button {
                pendingAction = .deleteAll
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Delete All History")
                            .font(.headline)
                            .foregroundStyle(.red)

                        Text("Remove every saved workout session.")
                            .font(.caption)
                            .foregroundStyle(AppTheme.textSecondary)
                    }

                    Spacer()

                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                }
                .padding(16)
                .background(Color.white.opacity(0.72))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .glassCard()
    }

    private var exerciseHistorySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Delete One Exercise")
                .font(.title3.weight(.bold))
                .foregroundStyle(AppTheme.textPrimary)

            if exerciseNames.isEmpty {
                Text("No exercise history found yet.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)
            } else {
                ForEach(exerciseNames, id: \.self) { exercise in
                    Button {
                        pendingAction = .deleteExercise(exercise)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(exercise)
                                    .font(.headline)
                                    .foregroundStyle(AppTheme.textPrimary)

                                Text("Delete this exercise from saved history")
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.textSecondary)
                            }

                            Spacer()

                            Image(systemName: "minus.circle")
                                .foregroundStyle(AppTheme.secondary)
                        }
                        .padding(16)
                        .background(Color.white.opacity(0.72))
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
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

    private func resetPreferences() {
        AIUserPreferencesStore.reset()
        loadPreferences()
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
        helpText: String,
        keyboardType: UIKeyboardType = .default
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(AppTheme.textPrimary)

            TextField(placeholder, text: text)
                .textFieldStyle(TrackerTextFieldStyle())
                .keyboardType(keyboardType)

            Text(helpText)
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)
        }
    }

    private func multilinePreferenceField(
        title: String,
        placeholder: String,
        text: Binding<String>,
        helpText: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(AppTheme.textPrimary)

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

            Text(helpText)
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)
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
