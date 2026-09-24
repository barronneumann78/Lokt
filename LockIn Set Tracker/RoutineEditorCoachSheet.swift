import SwiftUI

/// A short, local Coach conversation for a routine that is still being edited.
/// It deliberately lives in a sheet above the editor instead of routing to the
/// Coach tab: the form stays visible underneath and the user's main Coach
/// thread keeps its own history. The backend treats this context as advice-only
/// too, so a reply can never write or replace the in-progress routine.
///
/// Look v2: the Coach tab's vocabulary — "Lokt Coach" 22pt over the routine
/// name, sent messages as hairline bubbles on the elevated surface with a 4pt
/// tail, coach prose as plain 14pt text, and the 50pt card-capsule composer
/// with the 38pt gradient send circle (the sheet's one gradient).
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
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Lokt Coach")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(AppTheme.textPrimary)

                Text(snapshot.routineName)
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineLimit(1)

                TagChip(title: "\(snapshot.exercises.count) exercises in this routine")
                    .padding(.top, 4)
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
        .padding(.horizontal, AppTheme.screenPadding)
        .padding(.top, 18)
        .padding(.bottom, 12)
    }

    private var chat: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(messages) { message in
                        messageView(message)
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
                        .padding(.vertical, 4)
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
                .padding(.horizontal, AppTheme.screenPadding)
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

    /// Sent: 18pt-cornered hairline bubble on the elevated surface with a
    /// tight 4pt bottom-trailing tail. Coach: plain text on the canvas.
    @ViewBuilder
    private func messageView(_ message: AIWorkoutConversationMessage) -> some View {
        if message.role == .user {
            HStack {
                Spacer(minLength: 56)

                Text(message.text)
                    .font(.system(size: 15))
                    .foregroundStyle(AppTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Self.sentBubbleShape.fill(AppTheme.surfaceElevated))
                    .overlay {
                        Self.sentBubbleShape
                            .stroke(AppTheme.cardBorder, lineWidth: 1)
                    }
            }
        } else {
            Text(message.text)
                .font(.system(size: 14))
                .foregroundStyle(AppTheme.textPrimary)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.trailing, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private static var sentBubbleShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: 18,
            bottomLeadingRadius: 18,
            bottomTrailingRadius: 4,
            topTrailingRadius: 18,
            style: .continuous
        )
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
                    .padding(.vertical, 8)
                    .background(AppTheme.surfaceElevated)
                    .clipShape(Capsule())
                    .overlay {
                        Capsule()
                            .stroke(AppTheme.cardBorder, lineWidth: 1)
                    }
                }
            }
        }
    }

    /// The Coach composer: 50pt card-fill capsule holding the field and the
    /// 38pt gradient send circle. Return still sends (`.onSubmit`), the
    /// keyboard Done bar and tap-outside are the ways down.
    private var composer: some View {
        HStack(spacing: 6) {
            TrackerTextField("Ask about this workout", text: $messageText, axis: .vertical)
                .font(.system(size: 15))
                .foregroundStyle(AppTheme.textPrimary)
                .tint(AppTheme.primary)
                .lineLimit(1...3)
                .submitLabel(.send)
                .onSubmit(send)
                .padding(.leading, 12)
                .padding(.vertical, 8)

            Button {
                send()
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(AppTheme.backgroundTop)
                    .frame(width: 38, height: 38)
                    .background(AppTheme.primaryGradient)
                    .clipShape(Circle())
                    .opacity(canSend ? 1 : 0.4)
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .accessibilityLabel("Send to Coach")
        }
        .padding(.horizontal, 6)
        .frame(minHeight: 50)
        .background(AppTheme.card)
        .clipShape(Capsule())
        .overlay {
            Capsule()
                .stroke(AppTheme.cardBorder, lineWidth: 1)
        }
        .padding(.horizontal, AppTheme.screenPadding)
        .padding(.top, 8)
        .padding(.bottom, 12)
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
