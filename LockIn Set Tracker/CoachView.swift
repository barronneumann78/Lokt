import SwiftUI

struct CoachView: View {
    let initialContext: CoachLaunchContext

    @State private var conversationMessages: [AIWorkoutConversationMessage]
    @State private var currentDraft: AIGeneratedRoutineDraft?
    @State private var latestChangeSummary: String?
    @State private var messageText = ""
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var saveNotice: SaveNotice?

    /// Live frame of the composer text field in chat space — the launch pad
    /// for the send morph.
    @State private var composerFieldFrame: CGRect = .zero

    /// In-flight send morphs. While a message id is here, its real bubble in
    /// the conversation renders invisible and a floating overlay bubble flies
    /// from the composer to the bubble's live frame; on spring settle the
    /// overlay is removed and the real bubble takes over in the same frame.
    @State private var sendMorphs: [SendMorph] = []

    /// iMessage-style three-dot bubble shown while the coach is "typing".
    /// Appears slightly after the send morph so the landing slot stays stable
    /// during the flight.
    @State private var showTypingIndicator = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// One spring family for every chat motion — the send morph, the scroll
    /// ride-up, and the incoming pop — so the whole exchange feels like a
    /// single piece of physics.
    private static let sendSpring = Animation.spring(response: 0.40, dampingFraction: 0.78)
    private static let replySpring = Animation.spring(response: 0.42, dampingFraction: 0.80)
    private static let chatSpaceName = "coachChatSpace"

    private struct SendMorph: Identifiable, Equatable {
        let id: UUID
        let text: String
        let start: CGRect
        var dest: CGRect
        var progress: CGFloat = 0
        var launched = false
    }

    /// IDs of drafts already saved to the routine library this session. Drafts
    /// live only in memory (they die with the conversation), so this set shares
    /// their lifetime. A coach edit produces a new draft with a new id, which
    /// re-arms the save button for that new version.
    @State private var savedDraftIDs: Set<UUID> = []

    /// Draft-version id → id of the routine that version's lineage saved.
    /// Seeded when a version is first saved and carried forward every time a
    /// coach revision replaces the draft, so saving a later version updates
    /// the same routine in place instead of appending a copy.
    @State private var savedRoutineIDsByDraft: [UUID: UUID] = [:]

    /// Draft versions that performed an in-place update (capsule reads
    /// "Updated" instead of "Saved").
    @State private var updatedDraftIDs: Set<UUID> = []

    /// Exercise the quick-ask sheet is currently scoped to.
    @State private var askTarget: ExerciseAskContext?

    /// Draft exercise ids whose reasoning/tip block is open. New draft
    /// versions decode fresh ids, so rows naturally start collapsed.
    @State private var expandedDetailIDs: Set<UUID> = []

    @EnvironmentObject private var store: WorkoutStore
    @EnvironmentObject private var exerciseStore: ExerciseStore
    @ObservedObject private var hints = DiscoveryHints.shared

    private struct SaveNotice: Equatable {
        var title: String
        var text: String
    }

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
        .sheet(item: $askTarget) { context in
            ExerciseAskCoachSheet(context: context)
        }
    }

    private var coachContent: some View {
        ZStack {
            AppBackground()

            VStack(spacing: 0) {
                topBar

                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 16) {
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

                            if let saveNotice {
                                inlineStatusRow(
                                    title: saveNotice.title,
                                    text: saveNotice.text,
                                    tint: AppTheme.success
                                )
                            }

                            ForEach(conversationMessages) { message in
                                conversationMessageView(message)
                                    .id(message.id)
                            }

                            if showTypingIndicator {
                                HStack {
                                    TypingIndicatorBubble()
                                    Spacer(minLength: 56)
                                }
                                .id("typing-indicator")
                                .transition(incomingTransition)
                            }

                            if let currentDraft {
                                draftCard(for: currentDraft)
                                    .id("coach-draft-card")
                                    .transition(incomingTransition)
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
                        .padding(.bottom, 12)
                    }
                    .onAppear {
                        proxy.scrollTo("chat-bottom", anchor: .bottom)
                    }
                    .onChange(of: conversationMessages) { _, _ in
                        scrollToBottom(proxy)
                    }
                    .onChange(of: showTypingIndicator) { _, shown in
                        if shown {
                            scrollToBottom(proxy)
                        }
                    }
                    .onChange(of: currentDraft?.id) { _, _ in
                        scrollToBottom(proxy)
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            composerBar
        }
        .overlay {
            sendMorphLayer
        }
        .coordinateSpace(name: Self.chatSpaceName)
    }

    /// The conversation rides up on the same spring the send morph flies on,
    /// so the new bubble and the content shift read as one motion.
    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        if reduceMotion {
            proxy.scrollTo("chat-bottom", anchor: .bottom)
        } else {
            withAnimation(Self.sendSpring) {
                proxy.scrollTo("chat-bottom", anchor: .bottom)
            }
        }
    }

    /// Incoming coach content pops from the bottom-leading corner — scale up
    /// with a slight rise, springed. Reduce Motion gets a plain fade.
    private var incomingTransition: AnyTransition {
        if reduceMotion {
            return .opacity
        }
        return .scale(scale: 0.86, anchor: .bottomLeading)
            .combined(with: .offset(y: 8))
            .combined(with: .opacity)
    }

    /// Floating layer that carries in-flight send bubbles from the composer
    /// to their slot in the conversation. Drawn above the composer so the
    /// bubble visibly lifts out of the input field.
    private var sendMorphLayer: some View {
        GeometryReader { geo in
            let layerOrigin = geo.frame(in: .named(Self.chatSpaceName)).origin

            ZStack(alignment: .topLeading) {
                ForEach(sendMorphs) { morph in
                    Color.clear
                        .modifier(SendMorphRender(
                            progress: morph.progress,
                            start: morph.start.offsetBy(dx: -layerOrigin.x, dy: -layerOrigin.y),
                            dest: morph.dest.offsetBy(dx: -layerOrigin.x, dy: -layerOrigin.y),
                            text: morph.text
                        ))
                }
            }
        }
        .allowsHitTesting(false)
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
                    .onGeometryChange(for: CGRect.self) { proxy in
                        proxy.frame(in: .named(Self.chatSpaceName))
                    } action: { frame in
                        composerFieldFrame = frame
                    }

                // The button stays put while sending (dimmed, disabled) —
                // the in-conversation typing indicator carries the "coach is
                // thinking" signal, iMessage-style, instead of a spinner.
                Button {
                    sendMessage()
                } label: {
                    Image(systemName: currentDraft == nil ? "arrow.up.circle.fill" : "waveform.circle.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(sendButtonColor)
                }
                .buttonStyle(.plain)
                .disabled(isSending || messageText.trimmingCharacters(in: .whitespacesAndNewlines).count < 4)
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

    private var sendButtonColor: Color {
        if isSending {
            return AppTheme.textSecondary.opacity(0.35)
        }
        return messageText.trimmingCharacters(in: .whitespacesAndNewlines).count >= 4
            ? AppTheme.primary
            : AppTheme.textSecondary.opacity(0.55)
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

    @ViewBuilder
    private func conversationMessageView(_ message: AIWorkoutConversationMessage) -> some View {
        if message.role == .user {
            HStack {
                Spacer(minLength: 56)

                Text(message.text)
                    .font(ChatBubble.font)
                    .foregroundStyle(AppTheme.backgroundTop)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, ChatBubble.hPad)
                    .padding(.vertical, ChatBubble.vPad)
                    .background(ChatBubble.userShape.fill(AppTheme.accent))
                    .onGeometryChange(for: CGRect.self) { proxy in
                        proxy.frame(in: .named(Self.chatSpaceName))
                    } action: { frame in
                        updateMorphDestination(messageID: message.id, frame: frame)
                    }
            }
            // While the overlay bubble is in flight, the real bubble stays
            // invisible but keeps its layout — it is the morph's live target.
            .opacity(sendMorphs.contains { $0.id == message.id } ? 0 : 1)
            .transition(.opacity)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(message.text)
                        .font(ChatBubble.font)
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, ChatBubble.hPad)
                        .padding(.vertical, ChatBubble.vPad)
                        .background(ChatBubble.coachShape.fill(AppTheme.surfaceElevated))

                    Spacer(minLength: 56)
                }

                if message.id == conversationMessages.last?.id {
                    assistantActionRow
                        .padding(.leading, 4)
                }
            }
            .transition(incomingTransition)
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

                        Text(updatedDraftIDs.contains(draft.id) ? "Updated" : "Saved")
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
                    Button(hasSavedLineage(draft) ? "Update Workout" : "Save Workout") {
                        saveDraft(draft)
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
            }

            if let overview = draft.briefOverview {
                Text(overview)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let latestChangeSummary = nonEmptyText(latestChangeSummary) {
                Text(latestChangeSummary)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppTheme.textSecondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(draft.exercises.enumerated()), id: \.element.id) { item in
                    let reasoning = nonEmptyText(item.element.reasoning)
                    let tip = nonEmptyText(item.element.tip)
                    let isExpanded = expandedDetailIDs.contains(item.element.id)

                    HStack(alignment: .top, spacing: 10) {
                        Text("\(item.offset + 1).")
                            .font(.caption.weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(AppTheme.textTertiary)

                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 10) {
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    ExerciseTextNavigationLink(
                                        exerciseName: item.element.name,
                                        exercises: exerciseStore.exercises
                                    ) {
                                        Text(item.element.name)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(AppTheme.textPrimary)
                                    }

                                    if reasoning != nil || tip != nil {
                                        ExerciseDetailDisclosureChevron(
                                            id: item.element.id,
                                            expandedIDs: $expandedDetailIDs,
                                            font: .footnote
                                        )
                                    }
                                }

                                Spacer(minLength: 8)

                                ExerciseAskButton(
                                    context: ExerciseAskContext(draft: item.element),
                                    askTarget: $askTarget,
                                    font: .subheadline,
                                    hinted: hints.showAskHint(sessionCount: store.sessions.count)
                                )
                            }

                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("\(item.element.sets) sets • \(item.element.reps)")
                                    .font(.caption)
                                    .monospacedDigit()
                                    .foregroundStyle(AppTheme.textSecondary)

                                if let recommendedSets = item.element.recommendedSets {
                                    RecommendedSetsChip(
                                        recommended: recommendedSets,
                                        count: draftSetBinding(for: item.offset),
                                        font: .caption
                                    )
                                }
                            }

                            if isExpanded, let reasoning {
                                Text(reasoning)
                                    .font(.footnote)
                                    .foregroundStyle(AppTheme.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            if isExpanded, let tip {
                                Text(tip)
                                    .font(.footnote)
                                    .foregroundStyle(AppTheme.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
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

    /// Editable set count for one exercise of the current draft — the coach
    /// card's only count control, driven by the "Rec N" chip. Changing it
    /// after a save re-arms the save button (the draft id stays the same, so
    /// its lineage still updates the same routine in place), keeping the
    /// review-before-save invariant: what's saved is what the card shows.
    private func draftSetBinding(for index: Int) -> Binding<Int> {
        Binding(
            get: { max(1, currentDraft?.exercises[safe: index]?.sets ?? 3) },
            set: { newValue in
                guard var draft = currentDraft,
                      draft.exercises.indices.contains(index) else { return }

                draft.exercises[index].sets = max(1, newValue)
                currentDraft = draft
                savedDraftIDs.remove(draft.id)
                updatedDraftIDs.remove(draft.id)
            }
        )
    }

    /// True when this draft version descends from a version that already saved
    /// a routine and that routine still exists. Drives the "Update Workout"
    /// button label; a deleted target falls back to a fresh save.
    private func hasSavedLineage(_ draft: AIGeneratedRoutineDraft) -> Bool {
        guard let lineageID = savedRoutineIDsByDraft[draft.id] else { return false }
        return store.routine(withID: lineageID) != nil
    }

    /// Saves a draft to the routine library exactly once per draft version.
    /// A version whose lineage already produced a routine updates that routine
    /// in place; otherwise it appends a new one. Marking the id saved before
    /// writing makes the action idempotent even against re-entrant taps.
    private func saveDraft(_ draft: AIGeneratedRoutineDraft) {
        guard savedDraftIDs.insert(draft.id).inserted else { return }

        // Unmigrated screens still write the "routines" key directly (M1b),
        // and persisting through a stale store would drop their changes —
        // sync with UserDefaults before touching the library.
        store.reload()

        guard let routine = AIWorkoutRoutineSaver.makeRoutine(from: draft) else { return }

        if let lineageID = savedRoutineIDsByDraft[draft.id],
           let existing = store.routine(withID: lineageID) {
            // Coach revision of an already-saved routine: same identity,
            // updated content. Name history and adaptation state survive so
            // session history and the progression loop stay attached.
            var updated = Routine(
                id: existing.id,
                name: routine.name,
                exercises: routine.exercises,
                preferredSetCounts: routine.preferredSetCounts,
                historyNames: existing.allKnownNames + [routine.name],
                importContext: existing.importContext
            )
            updated.progression = existing.progression
            store.upsertRoutine(updated)
            updatedDraftIDs.insert(draft.id)
            withAnimation(.easeOut(duration: 0.18)) {
                saveNotice = SaveNotice(title: "Routine updated", text: "\(routine.name) now matches this draft.")
            }
        } else {
            // First save of this lineage — or its routine was deleted, in
            // which case we append fresh rather than resurrect the old id.
            store.addRoutine(routine)
            savedRoutineIDsByDraft[draft.id] = routine.id
            withAnimation(.easeOut(duration: 0.18)) {
                saveNotice = SaveNotice(title: "Saved to routines", text: "\(draft.title) is now saved in your routines.")
            }
        }
    }

    private func sendMessage() {
        let trimmedMessage = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedMessage.count >= 4 else { return }

        errorMessage = nil
        saveNotice = nil
        isSending = true
        let userMessage = AIWorkoutConversationMessage.user(trimmedMessage)

        // Capture the composer's live frame before clearing it — a multiline
        // draft shrinks the field the moment the text goes away.
        let fieldFrame = composerFieldFrame

        var instant = Transaction()
        instant.disablesAnimations = true

        if reduceMotion || fieldFrame == .zero {
            // Reduce Motion (or no measured composer yet): clear instantly,
            // fade the bubble in where it belongs. No flight.
            withTransaction(instant) {
                messageText = ""
            }
            withAnimation(.easeOut(duration: 0.2)) {
                conversationMessages.append(userMessage)
            }
        } else {
            // The typed text detaches from the composer: bubble padding grows
            // around the exact spot the text sat in the field, so glyphs never
            // jump at liftoff. The real bubble is appended hidden in the same
            // update; its first measured frame launches the flight.
            let startRect = fieldFrame.insetBy(dx: -ChatBubble.hPad, dy: -ChatBubble.vPad)
            withTransaction(instant) {
                messageText = ""
                sendMorphs.append(SendMorph(
                    id: userMessage.id,
                    text: userMessage.text,
                    start: startRect,
                    dest: startRect
                ))
                conversationMessages.append(userMessage)
            }
        }

        scheduleTypingIndicator()

        // The coach always sees the full routine library. Unmigrated screens
        // still write the "routines" key directly (M1b), so re-read from
        // UserDefaults first — the snapshot must never be stale.
        store.reload()
        let savedRoutines = store.routines

        Task { @MainActor in
            do {
                let result = try await coachService.sendMessage(
                    trimmedMessage,
                    contextKind: contextKind,
                    currentDraft: currentDraft,
                    activeWorkout: activeWorkoutSnapshot,
                    savedRoutines: savedRoutines,
                    conversation: conversationMessages
                )

                withAnimation(reduceMotion ? .easeOut(duration: 0.2) : Self.replySpring) {
                    showTypingIndicator = false

                    if result.action.changedDraft {
                        // Carry the lineage forward: the new draft version keeps
                        // pointing at whatever routine its ancestor saved, so a
                        // later save updates that routine instead of appending.
                        if let newDraft = result.routine,
                           let previousDraftID = currentDraft?.id,
                           let lineageRoutineID = savedRoutineIDsByDraft[previousDraftID] {
                            savedRoutineIDsByDraft[newDraft.id] = lineageRoutineID
                        } else if let newDraft = result.routine,
                                  let editedRoutineID = result.editedRoutineID,
                                  store.routine(withID: editedRoutineID) != nil {
                            // The backend built this draft as an edit of a saved
                            // routine — seed the lineage so the button reads
                            // "Update Workout" and saving upserts in place. The
                            // user still has to tap; nothing is written here.
                            savedRoutineIDsByDraft[newDraft.id] = editedRoutineID
                        }
                        currentDraft = result.routine
                    }
                    latestChangeSummary = result.changeSummary
                    conversationMessages.append(.assistant(result.assistantReply))
                }
            } catch {
                withTransaction(instant) {
                    sendMorphs.removeAll { $0.id == userMessage.id }
                }
                withAnimation(.easeOut(duration: 0.2)) {
                    showTypingIndicator = false
                    if conversationMessages.last == userMessage {
                        conversationMessages.removeLast()
                    }
                }
                // Put the failed message back so nothing typed is lost — but
                // never clobber text the user has started typing since.
                if messageText.isEmpty {
                    messageText = trimmedMessage
                }
                errorMessage = error.localizedDescription
            }

            isSending = false
        }
    }

    /// Shows the three-dot bubble only if the coach is still thinking once the
    /// send morph has mostly landed, so the flight's target slot stays put.
    private func scheduleTypingIndicator() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard isSending, !showTypingIndicator else { return }
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : Self.replySpring) {
                showTypingIndicator = true
            }
        }
    }

    /// Called from the hidden real bubble's geometry observer. The first
    /// measurement launches the flight; every later one retargets it, so the
    /// overlay chases the bubble while the scroll spring settles.
    private func updateMorphDestination(messageID: UUID, frame: CGRect) {
        guard let index = sendMorphs.firstIndex(where: { $0.id == messageID }) else { return }
        guard sendMorphs[index].dest != frame || !sendMorphs[index].launched else { return }

        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) {
            sendMorphs[index].dest = frame
        }

        guard !sendMorphs[index].launched else { return }
        sendMorphs[index].launched = true

        withAnimation(Self.sendSpring, completionCriteria: .removed) {
            sendMorphs[index].progress = 1
        } completion: {
            finishMorph(messageID)
        }
    }

    /// Swaps the settled overlay for the real bubble in a single frame.
    private func finishMorph(_ messageID: UUID) {
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) {
            sendMorphs.removeAll { $0.id == messageID }
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

/// Shared geometry for chat bubbles — the real bubbles and the in-flight
/// morph render must agree on every one of these so the settle is seamless.
private enum ChatBubble {
    static let radius: CGFloat = 18
    static let tailRadius: CGFloat = 6
    static let hPad: CGFloat = 14
    static let vPad: CGFloat = 9
    static let font = Font.system(size: 17)

    /// Sent bubble: tight bottom-trailing corner, iMessage tail feel.
    static var userShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: radius,
            bottomLeadingRadius: radius,
            bottomTrailingRadius: tailRadius,
            topTrailingRadius: radius,
            style: .continuous
        )
    }

    /// Received bubble: tight bottom-leading corner.
    static var coachShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: radius,
            bottomLeadingRadius: tailRadius,
            bottomTrailingRadius: radius,
            topTrailingRadius: radius,
            style: .continuous
        )
    }
}

/// Draws one in-flight sent bubble. `progress` is the animatable scalar the
/// send spring drives; `start`/`dest` are plain values, so retargeting the
/// destination mid-flight (the conversation is still riding the scroll
/// spring) updates the path without restarting the animation. Position runs
/// on unclamped progress — the spring's overshoot carries the bubble past its
/// slot and back — while size and corner radii settle at 1 so text never
/// re-wraps during the overshoot.
private struct SendMorphRender: ViewModifier, Animatable {
    var progress: CGFloat
    var start: CGRect
    var dest: CGRect
    var text: String

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let posT = max(progress, 0)
        let sizeT = min(posT, 1)

        let width = max(lerp(start.width, dest.width, sizeT), 1)
        let height = max(lerp(start.height, dest.height, sizeT), 1)
        let minX = lerp(start.minX, dest.minX, posT)
        let minY = lerp(start.minY, dest.minY, posT)

        // The composer capsule's rounding relaxes into the bubble's corners;
        // the bottom-trailing corner tightens into the tail.
        let startRadius = min(start.height / 2, 26)
        let radius = lerp(startRadius, ChatBubble.radius, sizeT)
        let tail = lerp(startRadius, ChatBubble.tailRadius, sizeT)

        // Color commits early — by half the flight the bubble reads as sent.
        let colorT = min(posT / 0.5, 1)
        let fill = AppTheme.surfaceElevated.mix(with: AppTheme.accent, by: colorT)
        let textColor = AppTheme.textPrimary.mix(with: AppTheme.backgroundTop, by: colorT)

        let shape = UnevenRoundedRectangle(
            topLeadingRadius: radius,
            bottomLeadingRadius: radius,
            bottomTrailingRadius: tail,
            topTrailingRadius: radius,
            style: .continuous
        )

        ZStack(alignment: .topLeading) {
            shape.fill(fill)

            Text(text)
                .font(ChatBubble.font)
                .foregroundStyle(textColor)
                .padding(.horizontal, ChatBubble.hPad)
                .padding(.vertical, ChatBubble.vPad)
                .frame(width: width, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: width, height: height, alignment: .topLeading)
        .clipShape(shape)
        .position(x: minX + width / 2, y: minY + height / 2)
    }

    private func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat {
        a + (b - a) * t
    }
}

/// iMessage-style "coach is typing" bubble: three dots pulsing in a wave.
/// Reduce Motion shows the dots statically.
private struct TypingIndicatorBubble: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(AppTheme.textSecondary)
                    .frame(width: 8, height: 8)
                    .opacity(pulsing ? 1 : 0.35)
                    .scaleEffect(pulsing ? 1 : 0.82)
                    .animation(
                        reduceMotion
                            ? nil
                            : .easeInOut(duration: 0.45)
                                .repeatForever(autoreverses: true)
                                .delay(Double(index) * 0.15),
                        value: pulsing
                    )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(ChatBubble.coachShape.fill(AppTheme.surfaceElevated))
        .onAppear {
            pulsing = true
        }
    }
}
