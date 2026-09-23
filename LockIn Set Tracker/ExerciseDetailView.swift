import SwiftUI

struct ExerciseDetailView: View {
    let exercise: Exercise
    var primaryAddAction: ExerciseDetailPrimaryAddAction? = nil

    @EnvironmentObject private var exerciseStore: ExerciseStore
    @State private var showAddSheet = false
    @State private var addFeedbackMessage: String?
    @State private var coachQuestion = ""
    @State private var coachReply: ExerciseCoachReply?
    @State private var coachErrorMessage: String?
    @State private var isRequestingCoach = false
    @State private var fetchedCues: [String]?
    @State private var isLoadingCues = false
    @State private var cuesFailed = false
    @State private var simpleExplanation: String?
    @State private var showSimpleExplanation = false
    @State private var isLoadingSimpleExplanation = false
    @State private var simpleExplanationErrorMessage: String?
    @State private var variations: [Exercise] = []

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    imageSection
                    detailSection
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 20)
            }
        }
        .navigationTitle("Exercise")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            loadCuesIfNeeded()
            variations = ExerciseVariations.variations(for: exercise, in: exerciseStore.exercises)
        }
    }

    private var imageSection: some View {
        VStack(spacing: 12) {
            ExerciseMediaView(
                imageName: exercise.imageName,
                placeholderSystemImageName: exercise.placeholderSystemImageName,
                height: 320,
                cornerRadius: 28,
                iconSize: 60,
                contentPadding: 10,
                maxContentWidth: 250
            )
            .frame(maxWidth: 280)
            .frame(maxWidth: .infinity)

            Text(exercise.imageName == nil ? "NO DEMO" : "DEMO")
                .microLabel()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 18)
        .glassCard()
    }

    private var detailSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(exercise.name)
                .font(.system(size: 30, weight: .bold))
                .tracking(-0.5)
                .foregroundStyle(AppTheme.textPrimary)

            cueSection
            overviewSection
            addActionSection
            coachSection

            chipSection(
                title: "Movement Profile",
                values: [
                    exercise.movementPattern.rawValue,
                    exercise.equipment.rawValue,
                    exercise.difficulty.rawValue,
                    exercise.metadata.mechanic.sentenceStyled,
                    exercise.metadata.laterality.sentenceStyled
                ],
                color: AppTheme.primary
            )

            musclesSection

            if !exercise.howTo.isEmpty {
                numberedSection(title: "How To", items: exercise.howTo)
            }

            variationsSection
        }
        .padding(20)
        .glassCard()
        .sheet(isPresented: $showAddSheet) {
            ExerciseAddSheet(exercise: exercise) { message in
                addFeedbackMessage = message
            }
        }
    }

    private var addActionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let primaryAddAction {
                Button(primaryAddAction.title) {
                    addFeedbackMessage = primaryAddAction.perform(exercise).message
                }
                .buttonStyle(PrimaryButtonStyle())

                Button("Add Somewhere Else") {
                    showAddSheet = true
                }
                .buttonStyle(SecondaryButtonStyle())
            } else {
                Button("Add to Routine") {
                    showAddSheet = true
                }
                .buttonStyle(PrimaryButtonStyle())
            }

            if let addFeedbackMessage {
                Label(addFeedbackMessage, systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.success)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .surfaceCard(cornerRadius: AppTheme.controlCornerRadius, border: AppTheme.success.opacity(0.22))
            }
        }
    }

    private var displayCues: [String] {
        if !exercise.cues.isEmpty {
            return Array(exercise.cues.prefix(3))
        }

        if let fetchedCues {
            return Array(fetchedCues.prefix(3))
        }

        return []
    }

    @ViewBuilder
    private var cueSection: some View {
        if !displayCues.isEmpty {
            bulletSection(title: "Form Cues", items: displayCues)
        } else if isLoadingCues {
            HStack(spacing: 10) {
                ProgressView()
                    .tint(AppTheme.textSecondary)

                Text("Loading form cues...")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)
            }
        } else if cuesFailed {
            HStack(spacing: 12) {
                Text("Form cues unavailable.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)

                Button("Retry") {
                    loadCuesIfNeeded(forceRefetch: true)
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary)
            }
        }
    }

    private var overviewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !exercise.description.isEmpty {
                textSection(title: "Overview", text: exercise.description)
            }

            if showSimpleExplanation, let simpleExplanation {
                VStack(alignment: .leading, spacing: 8) {
                    Text("IN PLAIN WORDS")
                        .microLabel()

                    Text(simpleExplanation)
                        .font(.body)
                        .foregroundStyle(AppTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .surfaceCard(cornerRadius: AppTheme.controlCornerRadius)
            } else {
                Button(isLoadingSimpleExplanation ? "Explaining..." : "Explain It Simply") {
                    requestSimpleExplanation()
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(isLoadingSimpleExplanation)
            }

            if let simpleExplanationErrorMessage {
                Text(simpleExplanationErrorMessage)
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondary)
            }
        }
    }

    private func loadCuesIfNeeded(forceRefetch: Bool = false) {
        guard exercise.cues.isEmpty, !isLoadingCues else { return }
        guard fetchedCues == nil || forceRefetch else { return }

        if !forceRefetch,
           let cached = ExerciseInsightCache.record(for: exercise.name)?.cues,
           !cached.isEmpty {
            fetchedCues = cached
            return
        }

        isLoadingCues = true
        cuesFailed = false

        Task {
            do {
                let cues = try await ExerciseInsightService().formCues(for: exercise)

                await MainActor.run {
                    fetchedCues = cues
                    isLoadingCues = false
                    ExerciseInsightCache.saveCues(cues, for: exercise.name)
                }
            } catch {
                await MainActor.run {
                    cuesFailed = true
                    isLoadingCues = false
                }
            }
        }
    }

    private func requestSimpleExplanation() {
        if simpleExplanation == nil,
           let cached = ExerciseInsightCache.record(for: exercise.name)?.simpleExplanation,
           !cached.isEmpty {
            simpleExplanation = cached
            showSimpleExplanation = true
            return
        }

        if simpleExplanation != nil {
            showSimpleExplanation = true
            return
        }

        isLoadingSimpleExplanation = true
        simpleExplanationErrorMessage = nil

        Task {
            do {
                let explanation = try await ExerciseInsightService().simpleExplanation(for: exercise)

                await MainActor.run {
                    simpleExplanation = explanation
                    showSimpleExplanation = true
                    isLoadingSimpleExplanation = false
                    ExerciseInsightCache.saveSimpleExplanation(explanation, for: exercise.name)
                }
            } catch {
                await MainActor.run {
                    simpleExplanationErrorMessage = error.localizedDescription
                    isLoadingSimpleExplanation = false
                }
            }
        }
    }

    private var coachSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("ASK LOKT")
                .microLabel()

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], alignment: .leading, spacing: 10) {
                ForEach(ExerciseCoachQuickAction.allCases) { action in
                    Button {
                        requestCoachAnswer(for: action.question, updatingField: false)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: action.systemImage)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AppTheme.textSecondary)

                            Text(action.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AppTheme.textPrimary)
                                .multilineTextAlignment(.leading)

                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .surfaceCard(cornerRadius: AppTheme.controlCornerRadius)
                    }
                    .buttonStyle(.plain)
                    .disabled(isRequestingCoach)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                TrackerTextField("Ask your own question about this exercise", text: $coachQuestion)
                    .textFieldStyle(TrackerTextFieldStyle())

                Button(isRequestingCoach ? "Thinking..." : "Ask Lokt") {
                    requestCoachAnswer(for: coachQuestion, updatingField: true)
                }
                .buttonStyle(PrimaryButtonStyle(fill: AppTheme.accent))
                .disabled(isRequestingCoach || coachQuestion.trimmingCharacters(in: .whitespacesAndNewlines).count < 4)
            }

            if isRequestingCoach {
                HStack(spacing: 10) {
                    ProgressView()
                        .tint(AppTheme.textSecondary)

                    Text("Lokt is looking at the lift.")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AppTheme.textSecondary)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .surfaceCard(cornerRadius: AppTheme.controlCornerRadius)
            }

            if let coachReply {
                coachReplyCard(coachReply)
            }

            if let coachErrorMessage {
                Text(coachErrorMessage)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondary)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .surfaceCard(cornerRadius: AppTheme.controlCornerRadius, border: AppTheme.secondary.opacity(0.25))
            }
        }
    }

    private func textSection(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .microLabel()

            Text(text)
                .font(.body)
                .foregroundStyle(AppTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func bulletSection(title: String, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .microLabel()

            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: 10) {
                    Circle()
                        .fill(AppTheme.textTertiary)
                        .frame(width: 6, height: 6)
                        .padding(.top, 6)

                    Text(item)
                        .font(.body)
                        .foregroundStyle(AppTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func numberedSection(title: String, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .microLabel()

            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .top, spacing: 10) {
                    Text("\(index + 1)")
                        .font(.footnote.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(AppTheme.textTertiary)
                        .frame(width: 18, alignment: .trailing)
                        .padding(.top, 2)

                    Text(item)
                        .font(.body)
                        .foregroundStyle(AppTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var musclesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("MUSCLES")
                .microLabel()

            ForEach(ExerciseMuscleRoles.primaryRoles(for: exercise), id: \.muscle) { role in
                (
                    Text(role.muscle.sentenceStyled)
                        .fontWeight(.semibold)
                        .foregroundStyle(AppTheme.textPrimary)
                    + Text(" — ")
                        .foregroundStyle(AppTheme.textTertiary)
                    + Text(role.clause)
                        .foregroundStyle(AppTheme.textSecondary)
                )
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
            }

            if !exercise.metadata.secondaryMuscles.isEmpty {
                (
                    Text("Secondary")
                        .fontWeight(.semibold)
                        .foregroundStyle(AppTheme.textTertiary)
                    + Text(" — ")
                        .foregroundStyle(AppTheme.textTertiary)
                    + Text(exercise.metadata.secondaryMuscles.map(\.sentenceStyled).joined(separator: ", "))
                        .foregroundStyle(AppTheme.textSecondary)
                )
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
            }
        }
    }

    @ViewBuilder
    private var variationsSection: some View {
        if !variations.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("VARIATIONS")
                    .microLabel()

                ForEach(variations) { variation in
                    NavigationLink(destination: ExerciseDetailView(exercise: variation, primaryAddAction: primaryAddAction)) {
                        HStack(spacing: 10) {
                            Text(variation.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AppTheme.textPrimary)
                                .multilineTextAlignment(.leading)

                            Spacer(minLength: 8)

                            Text(variationDescriptor(for: variation))
                                .font(.caption)
                                .foregroundStyle(AppTheme.textSecondary)

                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AppTheme.textTertiary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .surfaceCard(cornerRadius: AppTheme.controlCornerRadius)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// What makes this variation different: equipment when it changes,
    /// otherwise the difficulty step.
    private func variationDescriptor(for variation: Exercise) -> String {
        if variation.equipment != exercise.equipment {
            return variation.equipment.rawValue
        }
        return variation.difficulty.rawValue
    }

    private func chipSection(title: String, values: [String], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .microLabel()

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(values, id: \.self) { value in
                    TagChip(title: value.sentenceStyled, color: color)
                }
            }
        }
    }

    private func coachReplyCard(_ reply: ExerciseCoachReply) -> some View {
        ExerciseCoachReplyCard(
            reply: reply,
            exercises: exerciseStore.exercises,
            primaryAddAction: primaryAddAction,
            allowsSuggestionNavigation: true
        )
    }

    private func requestCoachAnswer(for question: String, updatingField: Bool) {
        let trimmedQuestion = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedQuestion.count >= 4 else { return }

        if updatingField {
            coachQuestion = trimmedQuestion
        }

        Task {
            await MainActor.run {
                isRequestingCoach = true
                coachErrorMessage = nil
            }

            do {
                let reply = try await ExerciseCoachService().reply(
                    for: trimmedQuestion,
                    exercise: exercise,
                    exercises: exerciseStore.exercises
                )

                await MainActor.run {
                    coachReply = reply
                    isRequestingCoach = false
                }
            } catch {
                await MainActor.run {
                    coachErrorMessage = error.localizedDescription
                    isRequestingCoach = false
                }
            }
        }
    }
}

struct ExerciseDetailPrimaryAddAction {
    var title: String
    var perform: (Exercise) -> AddExerciseResult
}

private enum ExerciseCoachQuickAction: String, CaseIterable, Identifiable {
    case why = "Why is this here?"
    case muscles = "What muscles does this hit?"
    case easier = "What’s an easier version?"
    case shoulder = "What if this hurts my shoulder?"
    case substitute = "What can I substitute?"

    var id: String { rawValue }

    var title: String { rawValue }

    var question: String { rawValue }

    var systemImage: String {
        switch self {
        case .why:
            return "questionmark.circle"
        case .muscles:
            return "figure.strengthtraining.traditional"
        case .easier:
            return "arrow.down.circle"
        case .shoulder:
            return "cross.case"
        case .substitute:
            return "arrow.triangle.swap"
        }
    }

}

struct ExerciseTextNavigationLink<Label: View>: View {
    let exerciseName: String
    let exercises: [Exercise]
    var primaryAddAction: ExerciseDetailPrimaryAddAction? = nil
    @ViewBuilder var label: () -> Label

    var body: some View {
        if let exercise = exercises.resolvedExercise(named: exerciseName) {
            NavigationLink(destination: ExerciseDetailView(exercise: exercise, primaryAddAction: primaryAddAction)) {
                label()
            }
            .buttonStyle(.plain)
        } else {
            label()
        }
    }
}

private struct ExerciseAddSheet: View {
    let exercise: Exercise
    var onComplete: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var workoutStore: WorkoutStore
    @State private var routines: [Routine] = []

    var body: some View {
        NavigationView {
            ZStack {
                AppBackground()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        headerCard
                        existingRoutineSection
                        createRoutineSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 20)
                }
            }
            .navigationTitle("Add Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            routines = workoutStore.routines
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(exercise.name)
                .font(.title3.weight(.bold))
                .foregroundStyle(AppTheme.textPrimary)
        }
        .padding(20)
        .glassCard()
    }

    @ViewBuilder
    private var existingRoutineSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("EXISTING ROUTINES")
                .microLabel()

            if routines.isEmpty {
                Text("You don’t have any saved routines yet.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)
                    .padding(.vertical, 6)
            } else {
                ForEach(routines) { routine in
                    Button {
                        let result = RoutineLibrary.addExercise(
                            named: exercise.name,
                            toRoutineID: routine.id,
                            in: workoutStore
                        )
                        onComplete(result.message)
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(routine.name)
                                    .font(.headline.weight(.semibold))
                                    .foregroundStyle(AppTheme.textPrimary)

                                Text("\(routine.exercises.count) exercises")
                                    .font(.caption)
                                    .monospacedDigit()
                                    .foregroundStyle(AppTheme.textSecondary)
                            }

                            Spacer()

                            Image(systemName: "plus.circle.fill")
                                .font(.title3)
                                .foregroundStyle(AppTheme.textPrimary)
                        }
                        .padding(16)
                        .background(AppTheme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(20)
        .glassCard()
    }

    private var createRoutineSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("NEW ROUTINE")
                .microLabel()

            Button {
                let routine = RoutineLibrary.createRoutine(from: exercise.name, in: workoutStore)
                onComplete("Created \(routine.name).")
                dismiss()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "plus.square.on.square")
                        .font(.title3)
                        .foregroundStyle(AppTheme.primary)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Create a New Routine")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(AppTheme.textPrimary)
                    }

                    Spacer()
                }
                .padding(16)
                .background(AppTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .glassCard()
    }
}

private extension String {
    var sentenceStyled: String {
        guard let first else { return self }
        return String(first).uppercased() + dropFirst()
    }
}

extension Array where Element == Exercise {
    func exercise(named name: String) -> Exercise? {
        first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }
}
