import SwiftUI

// Settings hub: a 26pt screen title over hairline navigation rows grouped
// under micro labels, each pushing a focused sub-page. All pushes stay inside
// Home's NavigationView; the nav bar itself stays quiet (empty inline title)
// so every page carries its own title in the app's vocabulary.
struct SettingsView: View {
    @EnvironmentObject private var theme: ThemeStore

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    SettingsScreenTitle("Settings")

                    VStack(alignment: .leading, spacing: 10) {
                        Text("APP")
                            .microLabel(AppTheme.textSecondary)

                        VStack(spacing: 0) {
                            hubRow(title: "Appearance", destination: AppearanceSettingsView()) {
                                Circle()
                                    .fill(AppTheme.accent)
                                    .frame(width: 10, height: 10)
                            }
                        }
                        .glassCard()
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("WORKOUTS")
                            .microLabel(AppTheme.textSecondary)

                        VStack(spacing: 0) {
                            hubRow(title: "Workout Preferences", destination: WorkoutPreferencesSettingsView())

                            SettingsHairline(leadingInset: AppTheme.cardPadding)

                            hubRow(title: "Workout History", destination: WorkoutHistorySettingsView())
                        }
                        .glassCard()
                    }
                }
                .padding(.horizontal, AppTheme.screenPadding)
                .padding(.vertical, 20)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func hubRow(
        title: String,
        destination: some View,
        @ViewBuilder accessory: () -> some View = { EmptyView() }
    ) -> some View {
        NavigationLink(destination: destination) {
            HStack(spacing: 12) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary)

                Spacer()

                accessory()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.textTertiary)
            }
            .padding(.horizontal, AppTheme.cardPadding)
            .padding(.vertical, 18)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Shared chrome

/// 26pt bold screen title with an optional `textSecondary` subtitle — the
/// same header the Analytics screen wears.
private struct SettingsScreenTitle: View {
    let title: String
    var subtitle: String? = nil

    init(_ title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 26, weight: .bold))
                .tracking(-0.3)
                .foregroundStyle(AppTheme.textPrimary)

            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 13))
                    .monospacedDigit()
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
        .padding(.bottom, 2)
    }
}

private struct SettingsHairline: View {
    var leadingInset: CGFloat = 0

    var body: some View {
        Rectangle()
            .fill(AppTheme.cardBorder)
            .frame(height: 1)
            .padding(.leading, leadingInset)
    }
}

// MARK: - Appearance

private struct AppearanceSettingsView: View {
    @EnvironmentObject private var theme: ThemeStore

    private static let tileCornerRadius: CGFloat = 16
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    SettingsScreenTitle("Appearance")

                    VStack(alignment: .leading, spacing: 10) {
                        Text("ACCENT")
                            .microLabel(AppTheme.textSecondary)

                        LazyVGrid(columns: columns, spacing: 10) {
                            ForEach(AccentScheme.allCases) { scheme in
                                swatchTile(for: scheme)
                            }
                        }
                    }
                }
                .padding(.horizontal, AppTheme.screenPadding)
                .padding(.vertical, 20)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        // Applies here instantly; the app-wide rebuild is committed on exit.
        .onDisappear {
            theme.commitIfNeeded()
        }
    }

    /// One scheme per tile: a 36pt swatch over the name. The selected tile
    /// wears the chip vocabulary — accent chip fill, accent hairline, accent
    /// name — plus a near-black check on its swatch.
    private func swatchTile(for scheme: AccentScheme) -> some View {
        let isSelected = scheme == theme.scheme
        let shape = RoundedRectangle(cornerRadius: Self.tileCornerRadius, style: .continuous)

        return Button {
            theme.select(scheme)
        } label: {
            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(scheme.color)
                        .frame(width: 36, height: 36)

                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundStyle(AppTheme.backgroundTop)
                    }
                }

                Text(scheme.displayName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isSelected ? AppTheme.primary : AppTheme.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background {
                if isSelected {
                    shape.fill(AppTheme.accentChipFill)
                }
            }
            .glassCard(cornerRadius: Self.tileCornerRadius)
            .overlay {
                if isSelected {
                    shape.stroke(AppTheme.accentHairline, lineWidth: 1)
                }
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isSelected ? "\(scheme.displayName), selected" : scheme.displayName)
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
                VStack(alignment: .leading, spacing: 24) {
                    SettingsScreenTitle("Workout Preferences")

                    VStack(alignment: .leading, spacing: 10) {
                        Text("AI WORKOUT PREFERENCES")
                            .microLabel(AppTheme.textSecondary)

                        VStack(alignment: .leading, spacing: 16) {
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

                            SettingsHairline()

                            safetyProfileFields

                            multilinePreferenceField(
                                title: "Notes About Limitations",
                                placeholder: "For example: avoid overhead pressing or deep knee bends",
                                text: $limitationsText
                            )

                            SettingsHairline()

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
                        }
                        .padding(AppTheme.cardPadding)
                        .glassCard()
                    }

                    // THE gradient pill of the screen beside a fixed-width ghost —
                    // the Coach draft card's Save / Revise pairing.
                    HStack(spacing: 10) {
                        Button("Save Preferences") {
                            savePreferences()
                        }
                        .buttonStyle(PrimaryButtonStyle())

                        Button("Retake Quiz") {
                            retakeQuiz()
                        }
                        .buttonStyle(GhostButtonStyle(verticalPadding: 17))
                        .frame(width: 128)
                    }

                    Text("Lokt uses these as plan constraints, not medical advice.")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.textTertiary)
                }
                .padding(.horizontal, AppTheme.screenPadding)
                .padding(.vertical, 20)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .dismissKeyboardOnTap()
        .keyboardDoneBar()
        .navigationTitle("")
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
        VStack(alignment: .leading, spacing: 16) {
            Text("SAFETY PROFILE")
                .microLabel(AppTheme.textSecondary)

            VStack(alignment: .leading, spacing: 8) {
                fieldLabel("Training Experience")

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
                fieldLabel("Areas to Work Around")

                selectionTile(title: "None right now", isSelected: selectedInjuryFlags.isEmpty) {
                    selectedInjuryFlags.removeAll()
                }

                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                    spacing: 10
                ) {
                    ForEach(InjuryFlag.allCases) { flag in
                        selectionTile(title: flag.title, isSelected: selectedInjuryFlags.contains(flag)) {
                            if selectedInjuryFlags.contains(flag) {
                                selectedInjuryFlags.remove(flag)
                            } else {
                                selectedInjuryFlags.insert(flag)
                            }
                        }
                    }
                }
            }
        }
    }

    /// Multi-select tile in the chip vocabulary: field fill + hairline at
    /// rest; accent chip fill, accent hairline, accent label and a check
    /// when selected.
    private func selectionTile(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        let shape = RoundedRectangle(cornerRadius: AppTheme.rowCornerRadius, style: .continuous)

        return Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 0)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                }
            }
            .foregroundStyle(isSelected ? AppTheme.primary : AppTheme.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? AppTheme.accentChipFill : AppTheme.fieldBackground)
            .clipShape(shape)
            .overlay {
                shape.stroke(isSelected ? AppTheme.accentHairline : AppTheme.cardBorder, lineWidth: 1)
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
    }

    private func retakeQuiz() {
        // Returning to the quiz is handled at the app root, which swaps back to
        // OnboardingView whenever this flag is false. Finishing (or skipping) the
        // quiz sets it true again.
        hasCompletedOnboarding = false
    }

    private func fieldLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .microLabel()
    }

    private func preferenceField(
        title: String,
        placeholder: String,
        text: Binding<String>,
        keyboardType: UIKeyboardType = .default
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel(title)

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
            fieldLabel(title)

            TrackerTextEditor(placeholder, text: text)
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
                VStack(alignment: .leading, spacing: 24) {
                    SettingsScreenTitle(
                        "Workout History",
                        subtitle: workoutSessions.isEmpty ? nil : "\(workoutSessions.count) session\(workoutSessions.count == 1 ? "" : "s") logged"
                    )

                    VStack(spacing: 0) {
                        actionRow(
                            title: "Export My Data",
                            systemImage: "square.and.arrow.up",
                            titleTint: AppTheme.textPrimary,
                            iconTint: AppTheme.textSecondary
                        ) {
                            exportData()
                        }

                        SettingsHairline(leadingInset: AppTheme.cardPadding)

                        actionRow(
                            title: "Delete All History",
                            systemImage: "trash",
                            titleTint: AppTheme.danger,
                            iconTint: AppTheme.danger
                        ) {
                            pendingAction = .deleteAll
                        }
                    }
                    .glassCard()

                    if !exerciseNames.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("DELETE ONE EXERCISE")
                                .microLabel(AppTheme.textSecondary)

                            VStack(spacing: 0) {
                                ForEach(Array(exerciseNames.enumerated()), id: \.element) { item in
                                    if item.offset > 0 {
                                        SettingsHairline(leadingInset: AppTheme.cardPadding)
                                    }

                                    actionRow(
                                        title: item.element,
                                        systemImage: "minus.circle",
                                        titleTint: AppTheme.textPrimary,
                                        iconTint: AppTheme.secondary
                                    ) {
                                        pendingAction = .deleteExercise(item.element)
                                    }
                                }
                            }
                            .glassCard()
                        }
                    }
                }
                .padding(.horizontal, AppTheme.screenPadding)
                .padding(.vertical, 20)
            }
        }
        .navigationTitle("")
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

    /// Hairline list row: 16pt title, quiet trailing glyph.
    private func actionRow(
        title: String,
        systemImage: String,
        titleTint: Color,
        iconTint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(titleTint)
                    .multilineTextAlignment(.leading)

                Spacer()

                Image(systemName: systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(iconTint)
            }
            .padding(.horizontal, AppTheme.cardPadding)
            .padding(.vertical, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
