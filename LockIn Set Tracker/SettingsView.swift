import SwiftUI

// Settings hub: hairline navigation rows grouped under micro-labels, each
// pushing a focused sub-page. All pushes stay inside Home's NavigationView.
struct SettingsView: View {
    @EnvironmentObject private var theme: ThemeStore

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("APP")
                            .microLabel()

                        VStack(spacing: 0) {
                            hubRow(title: "Appearance", destination: AppearanceSettingsView()) {
                                Circle()
                                    .fill(AppTheme.accent)
                                    .frame(width: 12, height: 12)
                            }
                        }
                        .glassCard()
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("WORKOUTS")
                            .microLabel()

                        VStack(spacing: 0) {
                            hubRow(title: "Workout Preferences", destination: WorkoutPreferencesSettingsView())

                            hairline

                            hubRow(title: "Workout History", destination: WorkoutHistorySettingsView())
                        }
                        .glassCard()
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 20)
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var hairline: some View {
        Rectangle()
            .fill(AppTheme.cardBorder)
            .frame(height: 1)
            .padding(.leading, 20)
    }

    private func hubRow(
        title: String,
        destination: some View,
        @ViewBuilder accessory: () -> some View = { EmptyView() }
    ) -> some View {
        NavigationLink(destination: destination) {
            HStack(spacing: 12) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(AppTheme.textPrimary)

                Spacer()

                accessory()

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AppTheme.textTertiary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Appearance

private struct AppearanceSettingsView: View {
    @EnvironmentObject private var theme: ThemeStore

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("ACCENT")
                        .microLabel()

                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(AccentScheme.allCases) { scheme in
                            swatch(for: scheme)
                        }
                    }
                }
                .padding(20)
                .glassCard()
                .padding(.horizontal, 20)
                .padding(.vertical, 20)
            }
        }
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
        // Applies here instantly; the app-wide rebuild is committed on exit.
        .onDisappear {
            theme.commitIfNeeded()
        }
    }

    private func swatch(for scheme: AccentScheme) -> some View {
        let isSelected = scheme == theme.scheme

        return Button {
            theme.select(scheme)
        } label: {
            VStack(spacing: 10) {
                ZStack {
                    if isSelected {
                        Circle()
                            .stroke(scheme.color, lineWidth: 2)
                            .frame(width: 54, height: 54)
                    }

                    Circle()
                        .fill(scheme.color)
                        .frame(width: 42, height: 42)

                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(AppTheme.backgroundTop)
                    }
                }
                .frame(width: 54, height: 54)

                Text(scheme.displayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isSelected ? AppTheme.textPrimary : AppTheme.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(AppTheme.mutedFill)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.rowCornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.rowCornerRadius, style: .continuous)
                    .stroke(AppTheme.cardBorder, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Workout Preferences

private struct WorkoutPreferencesSettingsView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var preferredEquipmentText = ""
    @State private var dislikedExercisesText = ""
    @State private var primaryGoalText = ""
    @State private var limitationsText = ""
    @State private var trainingStyleText = ""
    @State private var defaultTimeLimitText = ""
    @State private var trainingExperience: TrainingExperience?
    @State private var ageText = ""
    @State private var selectedInjuryFlags: Set<InjuryFlag> = []
    @State private var ageValidationMessage: String?

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView(showsIndicators: false) {
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

                    safetyProfileFields

                    multilinePreferenceField(
                        title: "Notes About Limitations",
                        placeholder: "For example: avoid overhead pressing or deep knee bends",
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
                .padding(.horizontal, 20)
                .padding(.vertical, 20)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .dismissKeyboardOnTap()
        .keyboardDoneBar()
        .navigationTitle("Workout Preferences")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadPreferences()
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
        trainingExperience = preferences.trainingExperience
        ageText = preferences.age.map(String.init) ?? ""
        selectedInjuryFlags = Set(preferences.injuryFlags ?? [])
        ageValidationMessage = nil
    }

    private func savePreferences() {
        let trimmedAge = ageText.trimmingCharacters(in: .whitespacesAndNewlines)
        let age: Int?
        if trimmedAge.isEmpty {
            age = nil
        } else if let parsedAge = AIUserPreferences.validAge(from: trimmedAge) {
            age = parsedAge
        } else {
            ageValidationMessage = "Enter an age from 13 to 120, or clear the field."
            return
        }

        let preferences = AIUserPreferences.fromForm(
            preferredEquipmentText: preferredEquipmentText,
            dislikedExercisesText: dislikedExercisesText,
            primaryGoal: primaryGoalText,
            limitations: limitationsText,
            trainingStyle: trainingStyleText,
            defaultTimeLimitText: defaultTimeLimitText,
            trainingExperience: trainingExperience,
            age: age,
            injuryFlags: InjuryFlag.allCases.filter(selectedInjuryFlags.contains)
        )

        AIUserPreferencesStore.save(preferences)
        loadPreferences()
    }

    private var safetyProfileFields: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("SAFETY PROFILE")
                .microLabel()

            VStack(alignment: .leading, spacing: 8) {
                Text("Training Experience")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textSecondary)

                Menu {
                    Button("Not set") {
                        trainingExperience = nil
                    }

                    ForEach(TrainingExperience.allCases) { option in
                        Button(option.title) {
                            trainingExperience = option
                        }
                    }
                } label: {
                    HStack {
                        Text(trainingExperience?.title ?? "Not set")
                            .foregroundStyle(AppTheme.textPrimary)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 13)
                    .background(AppTheme.fieldBackground)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous)
                            .stroke(AppTheme.cardBorder, lineWidth: 1)
                    }
                }
            }

            preferenceField(
                title: "Age",
                placeholder: "Optional",
                text: $ageText,
                keyboardType: .numberPad
            )

            if let ageValidationMessage {
                Text(ageValidationMessage)
                    .font(.caption)
                    .foregroundStyle(AppTheme.danger)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Areas to Work Around")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textSecondary)

                Button {
                    selectedInjuryFlags.removeAll()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: selectedInjuryFlags.isEmpty ? "checkmark.circle.fill" : "circle")
                        Text("None right now")
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(selectedInjuryFlags.isEmpty ? AppTheme.primary : AppTheme.textSecondary)
                }
                .buttonStyle(.plain)

                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                    spacing: 10
                ) {
                    ForEach(InjuryFlag.allCases) { flag in
                        injuryFlagButton(flag)
                    }
                }
            }

            Text("Lokt uses these as plan constraints, not medical advice.")
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)
        }
    }

    private func injuryFlagButton(_ flag: InjuryFlag) -> some View {
        let isSelected = selectedInjuryFlags.contains(flag)

        return Button {
            if isSelected {
                selectedInjuryFlags.remove(flag)
            } else {
                selectedInjuryFlags.insert(flag)
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.subheadline)
                Text(flag.title)
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .foregroundStyle(isSelected ? AppTheme.primary : AppTheme.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? AppTheme.primary.opacity(0.14) : AppTheme.fieldBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.rowCornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.rowCornerRadius, style: .continuous)
                    .stroke(isSelected ? AppTheme.primary.opacity(0.65) : AppTheme.cardBorder, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private func retakeQuiz() {
        // Returning to the quiz is handled at the app root, which swaps back to
        // OnboardingView whenever this flag is false. Finishing (or skipping) the
        // quiz sets it true again.
        hasCompletedOnboarding = false
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

// MARK: - Workout History

private struct WorkoutHistorySettingsView: View {
    @EnvironmentObject private var store: WorkoutStore
    @State private var workoutSessions: [WorkoutSession] = []
    @State private var pendingAction: PendingAction?
    @State private var exportItem: ExportItem?

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("WORKOUT HISTORY")
                        .microLabel()

                    Button {
                        exportData()
                    } label: {
                        HStack {
                            Text("Export My Data")
                                .font(.headline)
                                .foregroundStyle(AppTheme.textPrimary)

                            Spacer()

                            Image(systemName: "square.and.arrow.up")
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                        .padding(14)
                        .background(AppTheme.mutedFill)
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.rowCornerRadius, style: .continuous))
                    }
                    .buttonStyle(.plain)

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
                .padding(.horizontal, 20)
                .padding(.vertical, 20)
            }
        }
        .navigationTitle("Workout History")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadWorkoutSessions()
        }
        .sheet(item: $exportItem) { item in
            ShareSheet(activityItems: [item.url])
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

    /// Builds the full-data JSON export and hands it to the share sheet.
    /// Raw routine and session history has one owner: `WorkoutStore`.
    private func exportData() {
        let now = Date()
        let document = DataExport.buildDocument(
            routines: store.routines,
            sessions: store.sessions,
            preferences: AIUserPreferencesStore.load(),
            customExercises: CustomExerciseLibrary.loadExercises(),
            appVersion: DataExport.currentAppVersion,
            exportedAt: now
        )

        guard let data = try? DataExport.encode(document) else { return }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(DataExport.filename(for: now))

        do {
            try data.write(to: url, options: .atomic)
        } catch {
            return
        }

        exportItem = ExportItem(url: url)
    }

    private var exerciseNames: [String] {
        let names = workoutSessions.flatMap { Array($0.logs.keys) }
        return Array(Set(names)).sorted()
    }

    private func loadWorkoutSessions() {
        workoutSessions = store.sessions
    }

    private func saveWorkoutSessions(_ sessions: [WorkoutSession]) {
        store.replaceSessions(sessions)
        workoutSessions = store.sessions
    }

    private func deleteAllWorkoutHistory() {
        store.deleteAllSessions()
        workoutSessions = store.sessions
    }

    private func deleteHistory(for exercise: String) {
        let updatedSessions = workoutSessions.compactMap { session -> WorkoutSession? in
            var updatedSession = session
            updatedSession.logs.removeValue(forKey: exercise)
            return updatedSession.logs.isEmpty ? nil : updatedSession
        }

        saveWorkoutSessions(updatedSessions)
    }
}

private struct ExportItem: Identifiable {
    let id = UUID()
    let url: URL
}

// Minimal share-sheet bridge: SwiftUI has no programmatic ShareLink trigger,
// and the export file must be built (store reload + encode) at tap time.
private struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
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
