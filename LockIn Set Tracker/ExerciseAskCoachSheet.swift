import SwiftUI

/// Everything the quick-ask sheet knows about one draft exercise. Carries the
/// draft's own numbers so questions still get grounded answers when the name
/// never matched the exercise library.
struct ExerciseAskContext: Identifiable {
    var name: String
    var sets: Int?
    var reps: String?
    var notes: String?
    var reasoning: String?
    var tip: String?

    var id: String { name }

    init(
        name: String,
        sets: Int? = nil,
        reps: String? = nil,
        notes: String? = nil,
        reasoning: String? = nil,
        tip: String? = nil
    ) {
        self.name = name
        self.sets = sets
        self.reps = reps
        self.notes = notes
        self.reasoning = reasoning
        self.tip = tip
    }

    init(draft: AIGeneratedExercise) {
        self.init(
            name: draft.name,
            sets: draft.sets,
            reps: draft.reps,
            notes: draft.notes,
            reasoning: draft.reasoning,
            tip: draft.tip
        )
    }
}

/// Small trailing icon button that opens the quick-ask sheet for one exercise.
/// Neutral chrome by design — the sheet's single CTA carries the accent.
/// While the button is undiscovered (`hinted`), a tiny gray "Ask" label leads
/// the glyph; it collapses back to the bare icon with experience.
struct ExerciseAskButton: View {
    let context: ExerciseAskContext
    @Binding var askTarget: ExerciseAskContext?
    var font: Font = .headline
    var hinted: Bool = false

    var body: some View {
        Button {
            DiscoveryHints.shared.recordAskUse()
            askTarget = context
        } label: {
            HStack(spacing: 5) {
                if hinted {
                    DiscoveryHintLabel(text: "Ask")
                }

                Image(systemName: "questionmark.bubble")
                    .font(font)
                    .foregroundStyle(AppTheme.textPrimary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Ask about \(context.name)")
    }
}

/// Lightweight per-exercise Q&A sheet used on creation/review surfaces. Same
/// plumbing as the Ask Lokt section in `ExerciseDetailView` — shared
/// `ExerciseCoachService` and shared `ExerciseCoachReplyCard` — just without
/// leaving the draft.
struct ExerciseAskCoachSheet: View {
    let context: ExerciseAskContext

    @EnvironmentObject private var exerciseStore: ExerciseStore

    @State private var question = ""
    @State private var reply: ExerciseCoachReply?
    @State private var errorMessage: String?
    @State private var isRequesting = false
    /// Session cache: normalized question → reply, scoped to this exercise.
    @State private var cachedReplies: [String: ExerciseCoachReply] = [:]

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    Text("ASK LOKT")
                        .microLabel()

                    Text(context.name)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(AppTheme.textPrimary)

                    TrackerTextField("Ask about this exercise", text: $question)
                        .textFieldStyle(TrackerTextFieldStyle())
                        .submitLabel(.send)
                        .onSubmit(ask)

                    Button(isRequesting ? "Thinking..." : "Ask Lokt") {
                        ask()
                    }
                    .buttonStyle(PrimaryButtonStyle(fill: AppTheme.accent))
                    .disabled(!canAsk)
                    .opacity(canAsk ? 1 : 0.6)

                    if isRequesting {
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

                    if let reply {
                        ExerciseCoachReplyCard(
                            reply: reply,
                            exercises: exerciseStore.exercises,
                            allowsSuggestionNavigation: false
                        )
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.secondary)
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .surfaceCard(cornerRadius: AppTheme.controlCornerRadius, border: AppTheme.secondary.opacity(0.25))
                    }
                }
                .padding(20)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
    }

    private var canAsk: Bool {
        !isRequesting && question.trimmingCharacters(in: .whitespacesAndNewlines).count >= 4
    }

    private func ask() {
        let trimmedQuestion = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedQuestion.count >= 4 else { return }

        let cacheKey = trimmedQuestion.lowercased()
        if let cached = cachedReplies[cacheKey] {
            reply = cached
            errorMessage = nil
            return
        }

        Task {
            await MainActor.run {
                isRequesting = true
                errorMessage = nil
            }

            do {
                let freshReply = try await ExerciseCoachService().reply(
                    for: trimmedQuestion,
                    context: context,
                    exercises: exerciseStore.exercises
                )

                await MainActor.run {
                    cachedReplies[cacheKey] = freshReply
                    reply = freshReply
                    isRequesting = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isRequesting = false
                }
            }
        }
    }
}

/// Shared "COACH TAKE" card for `ExerciseCoachReply`. `ExerciseDetailView`
/// renders it with navigating suggestions; the quick-ask sheet renders the
/// same card with static suggestion rows (no navigation container in a sheet).
struct ExerciseCoachReplyCard: View {
    let reply: ExerciseCoachReply
    var exercises: [Exercise] = []
    var primaryAddAction: ExerciseDetailPrimaryAddAction? = nil
    var allowsSuggestionNavigation = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("COACH TAKE")
                .microLabel()

            Text(reply.answer)
                .font(.body)
                .foregroundStyle(AppTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if !reply.suggestions.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("GOOD ALTERNATIVES")
                        .microLabel()

                    ForEach(reply.suggestions) { suggestion in
                        if allowsSuggestionNavigation {
                            ExerciseTextNavigationLink(
                                exerciseName: suggestion.exerciseName,
                                exercises: exercises,
                                primaryAddAction: primaryAddAction
                            ) {
                                suggestionRow(suggestion, showsChevron: true)
                            }
                        } else {
                            suggestionRow(suggestion, showsChevron: false)
                        }
                    }
                }
            }
        }
        .padding(16)
        .surfaceCard(cornerRadius: AppTheme.controlCornerRadius)
    }

    private func suggestionRow(_ suggestion: ExerciseCoachSuggestion, showsChevron: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "arrow.triangle.swap")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)
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

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.textSecondary.opacity(0.8))
                    .padding(.top, 4)
            }
        }
        .padding(14)
        .surfaceCard(cornerRadius: AppTheme.controlCornerRadius)
    }
}
