import SwiftUI

struct CoachView: View {
    let initialContext: CoachLaunchContext

    @State private var conversationMessages: [AIWorkoutConversationMessage]
    @State private var currentDraft: AIGeneratedRoutineDraft?
    @State private var latestChangeSummary: String?
    @State private var messageText = ""
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var savedMessage: String?

    /// IDs of drafts already saved to the routine library this session. Drafts
    /// live only in memory (they die with the conversation), so this set shares
    /// their lifetime. A coach edit produces a new draft with a new id, which
    /// re-arms the save button for that new version.
    @State private var savedDraftIDs: Set<UUID> = []

    @StateObject private var exerciseStore = ExerciseStore()

    private let coachService = CoachChatService()

    init(initialContext: CoachLaunchContext = .planning) {
        self.initialContext = initialContext
        _conversationMessages = State(initialValue: Self.initialConversation(for: initialContext))
    }

    var body: some View {
        NavigationView {
            coachContent
                .navigationBarHidden(true)
        }
    }

    private var coachContent: some View {
        ZStack {
            AppBackground()

            VStack(spacing: 0) {
                topBar

                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 22) {
                            if let contextBannerText {
                                contextBanner(text: contextBannerText)
                            }

                            if let errorMessage {
                                inlineStatusRow(
                                    title: "Coach needs another try",
                                    text: errorMessage,
                                    tint: AppTheme.secondary
                                )
                            }

                            if let savedMessage {
                                inlineStatusRow(
                                    title: "Saved to routines",
                                    text: savedMessage,
                                    tint: AppTheme.success
                                )
                            }

                            ForEach(conversationMessages) { message in
                                conversationMessageView(message)
                                    .id(message.id)
                            }

                            if let currentDraft {
                                draftCard(for: currentDraft)
                                    .id("coach-draft-card")
                            }

                            if currentDraft == nil {
                                promptSuggestionRow
                            }

                            Color.clear
                                .frame(height: 6)
                                .id("chat-bottom")
                        }
                        .padding(.horizontal, 28)
                        .padding(.top, 18)
                        .padding(.bottom, 140)
                    }
                    .onAppear {
                        proxy.scrollTo("chat-bottom", anchor: .bottom)
                    }
                    .onChange(of: conversationMessages) { _, _ in
                        withAnimation(.easeOut(duration: 0.22)) {
                            proxy.scrollTo("chat-bottom", anchor: .bottom)
                        }
                    }
                    .onChange(of: currentDraft?.id) { _, _ in
                        withAnimation(.easeOut(duration: 0.22)) {
                            proxy.scrollTo("chat-bottom", anchor: .bottom)
                        }
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            composerBar
        }
    }

    private var topBar: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("Lokt Coach")
                        .font(.title.weight(.bold))
                        .foregroundStyle(AppTheme.textPrimary)

                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppTheme.textSecondary)
                }

                Text(topBarSubtitle)
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
            }

            Spacer()

            HStack(spacing: 14) {
                Image(systemName: "square.and.arrow.up")
                    .font(.headline)
                    .foregroundStyle(AppTheme.textPrimary.opacity(0.9))

                Image(systemName: "ellipsis")
                    .font(.headline)
                    .foregroundStyle(AppTheme.textPrimary.opacity(0.9))
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 18)
        .padding(.bottom, 12)
    }

    private var promptSuggestionRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(promptSuggestions, id: \.self) { suggestion in
                    Button(suggestion) {
                        messageText = suggestion
                    }
                    .buttonStyle(.plain)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppTheme.textSecondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(AppTheme.mutedFill)
                    .clipShape(Capsule())
                    .overlay {
                        Capsule()
                            .stroke(AppTheme.cardBorder, lineWidth: 1)
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var composerBar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Button {
                    messageText = promptSuggestions.randomElement() ?? ""
                } label: {
                    Image(systemName: "plus")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(AppTheme.textSecondary)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)

                TrackerTextField("Ask anything", text: $messageText, axis: .vertical)
                    .foregroundStyle(AppTheme.textPrimary)
                    .tint(AppTheme.primary)
                    .lineLimit(1...5)

                if isSending {
                    ProgressView()
                        .tint(AppTheme.textPrimary)
                        .frame(width: 32, height: 32)
                } else {
                    Button {
                        sendMessage()
                    } label: {
                        Image(systemName: currentDraft == nil ? "arrow.up.circle.fill" : "waveform.circle.fill")
                            .font(.system(size: 34))
                            .foregroundStyle(messageText.trimmingCharacters(in: .whitespacesAndNewlines).count >= 4 ? AppTheme.primary : AppTheme.textSecondary.opacity(0.55))
                    }
                    .buttonStyle(.plain)
                    .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).count < 4)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(AppTheme.surfaceElevated)
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .stroke(AppTheme.cardBorder, lineWidth: 1)
            }
            .padding(.horizontal, 24)

            Text("Lokt can make mistakes.")
                .font(.caption2)
                .foregroundStyle(AppTheme.textTertiary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 10)
        .padding(.bottom, 10)
        .background(
            AppTheme.backgroundTop
                .ignoresSafeArea()
        )
    }

    private func contextBanner(text: String) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(AppTheme.success)
                .frame(width: 8, height: 8)

            Text(text)
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)

            Spacer()
        }
    }

    private func inlineStatusRow(title: String, text: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(tint)
                .frame(width: 8, height: 8)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)

                Text(text)
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
    }

    private func conversationMessageView(_ message: AIWorkoutConversationMessage) -> some View {
        let isUser = message.role == .user

        return VStack(alignment: .leading, spacing: 8) {
            if isUser {
                HStack {
                    Spacer(minLength: 42)

                    Text(message.text)
                        .font(.title3.weight(.medium))
                        .italic()
                        .foregroundStyle(AppTheme.textPrimary.opacity(0.85))
                        .padding(.horizontal, 24)
                        .padding(.vertical, 16)
                        .background(AppTheme.surfaceElevated)
                        .clipShape(Capsule())
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text(message.text)
                        .font(.system(size: 18, weight: .regular, design: .default))
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineSpacing(5)
                        .fixedSize(horizontal: false, vertical: true)

                    if message.id == conversationMessages.last?.id {
                        assistantActionRow
                    }
                }
                .frame(maxWidth: 920, alignment: .leading)
            }
        }
    }

    private var assistantActionRow: some View {
        HStack(spacing: 18) {
            ForEach(["doc.on.doc", "hand.thumbsup", "hand.thumbsdown", "square.and.arrow.up", "ellipsis"], id: \.self) { systemName in
                Image(systemName: systemName)
                    .font(.headline)
                    .foregroundStyle(AppTheme.textSecondary.opacity(0.92))
            }
        }
        .padding(.top, 2)
    }

    private func draftCard(for draft: AIGeneratedRoutineDraft) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("WORKOUT DRAFT")
                        .microLabel()

                    Text(draft.title)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(AppTheme.textPrimary)

                    Text("\(draft.exercises.count) exercises • \(draft.totalSets) sets")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(AppTheme.textSecondary)
                }

                Spacer()

                if savedDraftIDs.contains(draft.id) {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(AppTheme.success)

                        Text("Saved")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(AppTheme.mutedFill)
                    .clipShape(Capsule())
                    .overlay {
                        Capsule()
                            .stroke(AppTheme.cardBorder, lineWidth: 1)
                    }
                } else {
                    Button("Save Routine") {
                        saveDraft(draft)
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
            }

            if let latestChangeSummary = nonEmptyText(latestChangeSummary) {
                Text(latestChangeSummary)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppTheme.textSecondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(draft.exercises.enumerated()), id: \.element.id) { item in
                    HStack(alignment: .top, spacing: 10) {
                        Text("\(item.offset + 1).")
                            .font(.caption.weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(AppTheme.textTertiary)

                        VStack(alignment: .leading, spacing: 3) {
                            ExerciseTextNavigationLink(
                                exerciseName: item.element.name,
                                exercises: exerciseStore.exercises
                            ) {
                                Text(item.element.name)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(AppTheme.textPrimary)
                            }

                            Text("\(item.element.sets) sets • \(item.element.reps)")
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                    }
                }
            }
        }
        .padding(18)
        .glassCard()
    }

    private var contextKind: CoachContextKind {
        if currentDraft != nil {
            return .draftEditing
        }

        switch initialContext {
        case .planning:
            return .planning
        case .activeWorkout:
            return .activeWorkout
        }
    }

    private var topBarSubtitle: String {
        switch contextKind {
        case .planning:
            return "Planning a new workout"
        case .draftEditing:
            return "Refining the current draft"
        case .activeWorkout:
            return "Helping during your workout"
        }
    }

    private var contextBannerText: String? {
        switch initialContext {
        case .planning:
            // The top bar subtitle already says "Planning a new workout" — no banner needed.
            return nil
        case .activeWorkout(let snapshot):
            if let nextExercise = nonEmptyText(snapshot.nextExercise) {
                return "Active workout: \(snapshot.routineName) • Up next: \(nextExercise)"
            }
            return "Active workout: \(snapshot.routineName)"
        }
    }

    private var activeWorkoutSnapshot: CoachWorkoutSnapshot? {
        if case .activeWorkout(let snapshot) = initialContext {
            return snapshot
        }

        return nil
    }

    private var promptSuggestions: [String] {
        switch contextKind {
        case .planning:
            return [
                "Make me a 45-minute upper body workout",
                "Give me a dumbbell-only push day",
                "Build a beginner pull day for a busy gym"
            ]
        case .draftEditing:
            return [
                "Make it shorter",
                "Swap this for dumbbells",
                "Make it easier on my shoulders"
            ]
        case .activeWorkout:
            return [
                "What should I do if the smith machine is taken?",
                "Should I lower the weight for the next set?",
                "Give me a quicker finisher after this"
            ]
        }
    }

    /// Saves a draft to the routine library exactly once. Marking the id saved
    /// before writing makes the action idempotent even against re-entrant taps.
    private func saveDraft(_ draft: AIGeneratedRoutineDraft) {
        guard savedDraftIDs.insert(draft.id).inserted else { return }
        AIWorkoutRoutineSaver.save(draft)
        withAnimation(.easeOut(duration: 0.18)) {
            savedMessage = "\(draft.title) is now saved in your routines."
        }
    }

    private func sendMessage() {
        let trimmedMessage = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedMessage.count >= 4 else { return }

        errorMessage = nil
        savedMessage = nil
        isSending = true
        let userMessage = AIWorkoutConversationMessage.user(trimmedMessage)
        conversationMessages.append(userMessage)

        Task { @MainActor in
            do {
                let result = try await coachService.sendMessage(
                    trimmedMessage,
                    contextKind: contextKind,
                    currentDraft: currentDraft,
                    activeWorkout: activeWorkoutSnapshot,
                    conversation: conversationMessages
                )

                if result.action.changedDraft {
                    currentDraft = result.routine
                }
                latestChangeSummary = result.changeSummary
                conversationMessages.append(.assistant(result.assistantReply))
                messageText = ""
            } catch {
                if conversationMessages.last == userMessage {
                    conversationMessages.removeLast()
                }
                errorMessage = error.localizedDescription
            }

            isSending = false
        }
    }

    private static func initialConversation(for context: CoachLaunchContext) -> [AIWorkoutConversationMessage] {
        switch context {
        case .planning:
            return [.assistant("I’m ready. Tell me what kind of workout you want, ask a training question, or just talk through ideas with me and I’ll figure out when it makes sense to actually build something for you.")]
        case .activeWorkout(let snapshot):
            let opener: String
            if let nextExercise = snapshot.nextExercise?.trimmingCharacters(in: .whitespacesAndNewlines), !nextExercise.isEmpty {
                opener = "I’m here with you during \(snapshot.routineName). You’re heading into \(nextExercise), so ask for a substitution, weight call, or a quick adjustment any time."
            } else {
                opener = "I’m here with you during \(snapshot.routineName). Ask for substitutions, setup cues, or quick coaching between sets."
            }
            return [.assistant(opener)]
        }
    }

    private func nonEmptyText(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
