import SwiftUI

/// A short, local Coach conversation for a routine that is still being edited.
/// It deliberately lives in a sheet above the editor instead of routing to the
/// Coach tab: the form stays visible underneath and the user's main Coach
/// thread keeps its own history. The backend treats this context as advice-only
/// too, so a reply can never write or replace the in-progress routine.
struct RoutineEditorCoachSheet: View {
    let snapshot: CoachRoutineSnapshot

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var workoutStore: WorkoutStore

    @State private var messages: [AIWorkoutConversationMessage]
    @State private var messageText = ""
    @State private var isSending = false
    @State private var errorMessage: String?

    private let coachService = CoachChatService()

    init(snapshot: CoachRoutineSnapshot) {
        self.snapshot = snapshot
        _messages = State(initialValue: [
            .assistant(
                "I can look at \(snapshot.routineName) as a whole. Ask whether it feels balanced, whether the order makes sense, or what you might be missing. I’ll keep this to advice so you stay in control of the edits."
            )
        ])
    }

    var body: some View {
        ZStack {
            AppBackground()

            VStack(spacing: 0) {
                header
                chat
                composer
            }
        }
        .dismissKeyboardOnTap()
        .keyboardDoneBar()
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(isSending)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("LOKT COACH")
                        .microLabel()

                    Text(snapshot.routineName)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(1)
                }

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppTheme.textSecondary)
                        .frame(width: 36, height: 36)
                        .background(AppTheme.surfaceElevated)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close Coach")
            }

            Text("Advice for this routine only — your edits stay here.")
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)

            Text("\(snapshot.exercises.count) exercises in this routine")
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(AppTheme.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(AppTheme.mutedFill)
                .clipShape(Capsule())
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 14)
    }

    private var chat: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(messages) { message in
                        messageBubble(message)
                            .id(message.id)
                    }

                    if isSending {
                        HStack(spacing: 8) {
                            ProgressView()
                                .tint(AppTheme.textSecondary)

                            Text("Lokt is thinking")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .surfaceCard(cornerRadius: AppTheme.controlCornerRadius)
                        .id("routine-editor-thinking")
                    }

                    if messages.count == 1, !isSending {
                        suggestionRow
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondary)
                            .padding(12)
                            .surfaceCard(cornerRadius: AppTheme.controlCornerRadius, border: AppTheme.secondary.opacity(0.25))
                    }

                    Color.clear
                        .frame(height: 1)
                        .id("routine-editor-chat-bottom")
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
            }
            .scrollDismissesKeyboard(.interactively)
            .onAppear {
                proxy.scrollTo("routine-editor-chat-bottom", anchor: .bottom)
            }
            .onChange(of: messages.count) { _, _ in
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo("routine-editor-chat-bottom", anchor: .bottom)
                }
            }
            .onChange(of: isSending) { _, _ in
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo("routine-editor-chat-bottom", anchor: .bottom)
                }
            }
        }
    }

    private func messageBubble(_ message: AIWorkoutConversationMessage) -> some View {
        HStack {
            if message.role == .user {
                Spacer(minLength: 44)
            }

            Text(message.text)
                .font(.body)
                .foregroundStyle(message.role == .user ? AppTheme.backgroundTop : AppTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(message.role == .user ? AppTheme.accent : AppTheme.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            if message.role == .assistant {
                Spacer(minLength: 44)
            }
        }
    }

    private var suggestionRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(suggestedQuestions, id: \.self) { question in
                    Button(question) {
                        messageText = question
                    }
                    .buttonStyle(.plain)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppTheme.textSecondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(AppTheme.mutedFill)
                    .clipShape(Capsule())
                    .overlay {
                        Capsule()
                            .stroke(AppTheme.cardBorder, lineWidth: 1)
                    }
                }
            }
        }
    }

    private var composer: some View {
        HStack(spacing: 10) {
            TrackerTextField("Ask about this workout", text: $messageText, axis: .vertical)
                .textFieldStyle(TrackerTextFieldStyle())
                .lineLimit(1...3)
                .submitLabel(.send)
                .onSubmit(send)

            Button {
                send()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(canSend ? AppTheme.primary : AppTheme.textSecondary.opacity(0.55))
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .accessibilityLabel("Send to Coach")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(AppTheme.backgroundTop)
    }

    private var canSend: Bool {
        !isSending && messageText.trimmingCharacters(in: .whitespacesAndNewlines).count >= 4
    }

    private var suggestedQuestions: [String] {
        [
            "Does this workout look balanced?",
            "Is this exercise order good?",
            "What might this workout be missing?"
        ]
    }

    private func send() {
        let trimmedMessage = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedMessage.count >= 4, !isSending else { return }

        let userMessage = AIWorkoutConversationMessage.user(trimmedMessage)
        messageText = ""
        errorMessage = nil
        isSending = true
        messages.append(userMessage)
        KeyboardDismiss.dismiss()

        Task { @MainActor in
            do {
                let result = try await coachService.sendMessage(
                    trimmedMessage,
                    contextKind: .routineEditing,
                    currentDraft: nil,
                    activeWorkout: snapshot,
                    savedRoutines: workoutStore.routines,
                    conversation: messages
                )
                // Routine-editor context is advice-only. Even if an outdated
                // backend returned a draft, this temporary sheet never applies
                // or displays it; the editor remains the explicit edit path.
                messages.append(.assistant(result.assistantReply))
            } catch {
                if messageText.isEmpty {
                    messageText = trimmedMessage
                }
                errorMessage = error.localizedDescription
            }

            isSending = false
        }
    }
}
