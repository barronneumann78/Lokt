import SwiftUI

struct ExerciseDetailView: View {
    let exercise: Exercise
    var primaryAddAction: ExerciseDetailPrimaryAddAction? = nil

    @StateObject private var exerciseStore = ExerciseStore()
    @State private var showAddSheet = false
    @State private var addFeedbackMessage: String?
    @State private var coachQuestion = ""
    @State private var coachReply: ExerciseCoachReply?
    @State private var coachErrorMessage: String?
    @State private var isRequestingCoach = false

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

            Text(exercise.imageName == nil ? "Image placeholder" : "Exercise demo")
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 18)
        .glassCard()
    }

    private var detailSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(exercise.name)
                .font(.system(size: 30, weight: .black, design: .rounded))
                .foregroundStyle(AppTheme.textPrimary)

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

            chipSection(
                title: "Primary Muscles",
                values: exercise.metadata.primaryMuscles,
                color: AppTheme.secondary
            )

            if !exercise.metadata.secondaryMuscles.isEmpty {
                chipSection(
                    title: "Secondary Muscles",
                    values: exercise.metadata.secondaryMuscles,
                    color: AppTheme.accent
                )
            }

            textSection(title: "Overview", text: exercise.description)
            bulletSection(title: "How To", items: exercise.howTo)
            bulletSection(title: "Key Cues", items: exercise.cues)
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
                .buttonStyle(PrimaryButtonStyle(fill: AppTheme.success))

                Button("Add Somewhere Else") {
                    showAddSheet = true
                }
                .buttonStyle(SecondaryButtonStyle())
            } else {
                Button("Add to Routine") {
                    showAddSheet = true
                }
                .buttonStyle(PrimaryButtonStyle(fill: AppTheme.success))
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

    private var coachSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Ask Lokt")
                .font(.headline)
                .foregroundStyle(AppTheme.textPrimary)

            Text("Get a quick coach take on why this lift is useful, what it trains, or what to swap to.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], alignment: .leading, spacing: 10) {
                ForEach(ExerciseCoachQuickAction.allCases) { action in
                    Button {
                        requestCoachAnswer(for: action.question, updatingField: false)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: action.systemImage)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(action.color)

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
                TextField("Ask your own question about this exercise", text: $coachQuestion)
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
                        .tint(AppTheme.primary)

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
            Text(title)
                .font(.headline)
                .foregroundStyle(AppTheme.textPrimary)

            Text(text)
                .font(.body)
                .foregroundStyle(AppTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func bulletSection(title: String, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .foregroundStyle(AppTheme.textPrimary)

            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: 10) {
                    Circle()
                        .fill(AppTheme.primary.opacity(0.8))
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

    private func chipSection(title: String, values: [String], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .foregroundStyle(AppTheme.textPrimary)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(values, id: \.self) { value in
                    TagChip(title: value.sentenceStyled, color: color)
                }
            }
        }
    }

    private func coachReplyCard(_ reply: ExerciseCoachReply) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Coach Take")
                .font(.headline)
                .foregroundStyle(AppTheme.textPrimary)

            Text(reply.answer)
                .font(.body)
                .foregroundStyle(AppTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if !reply.suggestions.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Good Alternatives")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)

                    ForEach(reply.suggestions) { suggestion in
                        ExerciseTextNavigationLink(
                            exerciseName: suggestion.exerciseName,
                            exercises: exerciseStore.exercises,
                            primaryAddAction: primaryAddAction
                        ) {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "arrow.triangle.swap")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(AppTheme.primary)
                                    .padding(.top, 2)

                                VStack(alignment: .leading, spacing: 5) {
                                    Text(suggestion.exerciseName)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(AppTheme.textPrimary)

                                    Text(suggestion.reason)
                                        .font(.caption)
                                        .foregroundStyle(AppTheme.textSecondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }

                                Spacer(minLength: 0)

                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(AppTheme.textSecondary.opacity(0.8))
                                    .padding(.top, 4)
                            }
                            .padding(14)
                            .surfaceCard(cornerRadius: AppTheme.controlCornerRadius)
                        }
                    }
                }
            }
        }
        .padding(16)
        .surfaceCard(cornerRadius: AppTheme.controlCornerRadius)
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

    var color: Color {
        switch self {
        case .why:
            return AppTheme.primary
        case .muscles:
            return AppTheme.success
        case .easier:
            return AppTheme.secondary
        case .shoulder:
            return AppTheme.accent
        case .substitute:
            return AppTheme.primary
        }
    }
}

struct ExerciseTextNavigationLink<Label: View>: View {
    let exerciseName: String
    let exercises: [Exercise]
    var primaryAddAction: ExerciseDetailPrimaryAddAction? = nil
    @ViewBuilder var label: () -> Label

    var body: some View {
        if let exercise = exercises.exercise(named: exerciseName) {
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
            routines = RoutineLibrary.load()
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(exercise.name)
                .font(.title3.weight(.bold))
                .foregroundStyle(AppTheme.textPrimary)

            Text("Add this exercise to an existing routine or start a new one from it.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
        }
        .padding(20)
        .glassCard()
    }

    @ViewBuilder
    private var existingRoutineSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Existing Routines")
                .font(.headline)
                .foregroundStyle(AppTheme.textPrimary)

            if routines.isEmpty {
                Text("You don’t have any saved routines yet.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)
                    .padding(.vertical, 6)
            } else {
                ForEach(routines) { routine in
                    Button {
                        let result = RoutineLibrary.addExercise(named: exercise.name, toRoutineID: routine.id)
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
                                    .foregroundStyle(AppTheme.textSecondary)
                            }

                            Spacer()

                            Image(systemName: "plus.circle.fill")
                                .font(.title3)
                                .foregroundStyle(AppTheme.success)
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
            Text("New Routine")
                .font(.headline)
                .foregroundStyle(AppTheme.textPrimary)

            Button {
                let routine = RoutineLibrary.createRoutine(from: exercise.name)
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

                        Text("Start a saved routine with just this exercise.")
                            .font(.caption)
                            .foregroundStyle(AppTheme.textSecondary)
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
