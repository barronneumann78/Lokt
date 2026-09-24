import SwiftUI
import UIKit

struct CoachView: View {
    let initialContext: CoachLaunchContext

    @State private var conversationMessages: [AIWorkoutConversationMessage]

    /// Every draft the latest coach reply carried, in the coach's order. One
    /// entry is the usual case; two to five when the user clearly asked for
    /// more than one (the card pages between them). `currentDraft` is the
    /// focused entry — the one the composer revises and the Rec chip edits.
    @State private var drafts: [AIGeneratedRoutineDraft] = []
    @State private var focusedDraftIndex = 0

    /// Direction the pager last moved — picks the slide edge.
    @State private var pagerMovesForward = true

    /// Drafts the latest change summary describes: every draft of a multi
    /// reply, or the one draft a revise replaced. Keeps a revise's summary
    /// off the other pages.
    @State private var changeSummaryDraftIDs: Set<UUID> = []
    @State private var latestChangeSummary: String?

    /// The focused draft. Setting it replaces only that entry (a revise on
    /// draft 2 never touches draft 1); nil clears the whole set.
    private var currentDraft: AIGeneratedRoutineDraft? {
        get { drafts[safe: focusedDraftIndex] }
        nonmutating set {
            guard let newValue else {
                drafts = []
                focusedDraftIndex = 0
                return
            }
            if drafts.indices.contains(focusedDraftIndex) {
                drafts[focusedDraftIndex] = newValue
            } else {
                drafts = [newValue]
                focusedDraftIndex = 0
            }
        }
    }
    @State private var messageText = ""
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var saveNotice: SaveNotice?
    @State private var copiedReplyID: UUID?
    @State private var attachmentDestination: CoachAttachmentDestination?

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

    /// The draft card's Revise hands focus here — the existing revise path
    /// (the next message replaces only the focused draft).
    @FocusState private var composerFocused: Bool

    @EnvironmentObject private var store: WorkoutStore
    @EnvironmentObject private var exerciseStore: ExerciseStore
    @ObservedObject private var hints = DiscoveryHints.shared

    private struct SaveNotice: Equatable {
        var title: String
        var text: String
    }

    private enum CoachAttachmentDestination: String, Identifiable {
        case photo
        case voice

        var id: String { rawValue }
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
        .sheet(item: $attachmentDestination) { destination in
            NavigationStack {
                Group {
                    switch destination {
                    case .photo:
                        WorkoutPhotoImportView(onSave: finishAttachmentImport)
                    case .voice:
                        VoiceWorkoutImportView(onSave: finishAttachmentImport)
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            attachmentDestination = nil
                        }
                    }
                }
            }
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
                                    TypingIndicatorDots()
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
                        .padding(.horizontal, AppTheme.screenPadding)
                        .padding(.top, 10)
                        .padding(.bottom, 12)
                    }
                    .scrollDismissesKeyboard(.interactively)
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
        // The composer is multi-line (Return = newline), so the keyboard needs
        // explicit ways down: tap the conversation, drag it, or Done.
        .dismissKeyboardOnTap()
        .keyboardDoneBar()
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

    /// "Lokt Coach" with the policy line as a tiny caption on the same row.
    private var topBar: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Lokt Coach")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(AppTheme.textPrimary)

            Spacer()

            Text("Lokt can make mistakes.")
                .font(.caption2)
                .foregroundStyle(AppTheme.textTertiary)
        }
        .padding(.horizontal, AppTheme.screenPadding)
        .padding(.top, 18)
        .padding(.bottom, 8)
    }

    /// Prompt chips under the opener — small hairline capsules on the
    /// elevated surface; tapping one drops it into the composer.
    private var promptSuggestionRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(promptSuggestions, id: \.self) { suggestion in
                    Button(suggestion) {
                        messageText = suggestion
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
            .padding(.vertical, 2)
        }
    }

    /// 50pt capsule on the card fill with a hairline: the attachment menu as
    /// a plain icon, the field, and the send control as a 38pt gradient
    /// circle — the screen's only gradient besides the draft's Save pill.
    /// The button stays put while sending (dimmed, disabled) — the typing
    /// indicator carries the "coach is thinking" signal, not a spinner.
    private var composerBar: some View {
        HStack(spacing: 6) {
            Menu {
                Button {
                    attachmentDestination = .photo
                } label: {
                    Label("Import photo or screenshot", systemImage: "photo.on.rectangle")
                }

                Button {
                    attachmentDestination = .voice
                } label: {
                    Label("Record a voice note", systemImage: "mic")
                }
            } label: {
                Image(systemName: "plus")
                    .font(.body.weight(.medium))
                    .foregroundStyle(AppTheme.textSecondary)
                    .frame(width: 38, height: 38)
                    .contentShape(Circle())
            }
            .accessibilityLabel("Add a photo, screenshot, or voice note")

            // Measured before the vertical padding so the send morph lifts
            // off the text itself, not the field's breathing room.
            TrackerTextField("Ask anything", text: $messageText, axis: .vertical)
                .font(ChatBubble.font)
                .foregroundStyle(AppTheme.textPrimary)
                .tint(AppTheme.primary)
                .lineLimit(1...5)
                .focused($composerFocused)
                .onGeometryChange(for: CGRect.self) { proxy in
                    proxy.frame(in: .named(Self.chatSpaceName))
                } action: { frame in
                    composerFieldFrame = frame
                }
                .padding(.vertical, 8)

            Button {
                sendMessage()
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
            .accessibilityLabel("Send")
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
        .padding(.bottom, 10)
        .background(
            AppTheme.backgroundTop
                .ignoresSafeArea()
        )
    }

    private var canSend: Bool {
        !isSending && messageText.trimmingCharacters(in: .whitespacesAndNewlines).count >= 4
    }

    private func finishAttachmentImport() {
        attachmentDestination = nil
        withAnimation(.easeOut(duration: 0.18)) {
            saveNotice = SaveNotice(
                title: "Imported routine saved",
                text: "Your imported workout is ready in Routines."
            )
        }
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
                    .foregroundStyle(AppTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, ChatBubble.hPad)
                    .padding(.vertical, ChatBubble.vPad)
                    .background(ChatBubble.userShape.fill(AppTheme.surfaceElevated))
                    .overlay {
                        ChatBubble.userShape
                            .stroke(AppTheme.cardBorder, lineWidth: 1)
                    }
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
            // Coach prose is plain text on the canvas — no bubble.
            VStack(alignment: .leading, spacing: 10) {
                Text(message.text)
                    .font(ChatBubble.coachFont)
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineSpacing(ChatBubble.coachLineSpacing)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.trailing, 12)

                if message.id == conversationMessages.last?.id, conversationMessages.count > 1 {
                    assistantActionRow(for: message)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .transition(incomingTransition)
        }
    }

    private func assistantActionRow(for message: AIWorkoutConversationMessage) -> some View {
        HStack(spacing: 18) {
            Button {
                UIPasteboard.general.string = message.text
                copiedReplyID = message.id
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(2))
                    if copiedReplyID == message.id {
                        copiedReplyID = nil
                    }
                }
            } label: {
                Label(
                    copiedReplyID == message.id ? "Copied" : "Copy",
                    systemImage: copiedReplyID == message.id ? "checkmark" : "doc.on.doc"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)
            }
            .buttonStyle(.plain)

            ShareLink(item: message.text) {
                Label("Share", systemImage: "square.and.arrow.up")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
        .padding(.top, 2)
    }

    /// A ZStack (not the chat VStack) hosts the page transition so the
    /// outgoing page never keeps a layout slot below the incoming one. In the
    /// single case the index never changes, so nothing transitions.
    private func draftCard(for draft: AIGeneratedRoutineDraft) -> some View {
        ZStack {
            draftCardContent(for: draft)
                .id(focusedDraftIndex)
                .transition(pagerTransition)
        }
    }

    /// The card: WORKOUT DRAFT micro label with the pager chip and dots on
    /// the right (multi replies only), 18pt title, an exercise/set meta line,
    /// a hairline, the numbered exercise list, and the action row. The
    /// accent hairline over `glassCard()` makes it the one accent-bordered
    /// card on the screen.
    private func draftCardContent(for draft: AIGeneratedRoutineDraft) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 10) {
                Text("WORKOUT DRAFT")
                    .microLabel(AppTheme.accent)

                Spacer(minLength: 8)

                if drafts.count > 1 {
                    pagerChip
                    pagerDots
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(draft.title)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                // No "~min" segment: the draft payload carries no time estimate.
                Text("\(draft.exercises.count) exercises • \(draft.totalSets) sets")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(AppTheme.textSecondary)

                if changeSummaryDraftIDs.contains(draft.id),
                   let latestChangeSummary = nonEmptyText(latestChangeSummary) {
                    Text(latestChangeSummary)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AppTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Rectangle()
                .fill(AppTheme.cardBorder)
                .frame(height: 1)

            draftExerciseList(for: draft)

            draftActions(for: draft)
        }
        .padding(18)
        .glassCard()
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous)
                .stroke(AppTheme.accentHairline, lineWidth: 1)
        }
        .gesture(pagerSwipe)
    }

    // MARK: Draft exercise list

    /// Every exercise, no "+ N more" fold — the owner prefers the small space
    /// cost to hidden rows.
    private func draftExerciseList(for draft: AIGeneratedRoutineDraft) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(draft.exercises.enumerated()), id: \.element.id) { item in
                draftExerciseRow(item.element, index: item.offset)
            }
        }
    }

    /// One `DraftExerciseRow` (the shared name / info / sets • reps / chevron /
    /// ask row — identical to the generator's). The chevron appears only when
    /// the coach gave a reasoning or tip; beneath, the "Recommended sets: N"
    /// chip sits only while it differs (the same one-tap restore as before)
    /// and the open row shows the reasoning/tip lines.
    private func draftExerciseRow(_ exercise: AIGeneratedExercise, index: Int) -> some View {
        let reasoning = nonEmptyText(exercise.reasoning)
        let tip = nonEmptyText(exercise.tip)
        let isExpanded = expandedDetailIDs.contains(exercise.id)

        return DraftExerciseRow(
            index: index,
            name: exercise.name,
            sets: exercise.sets,
            reps: exercise.reps,
            disclosureID: exercise.id,
            expandedIDs: $expandedDetailIDs,
            showsDisclosure: reasoning != nil || tip != nil,
            infoExercise: exerciseStore.exercises.resolvedExercise(named: exercise.name),
            askContext: ExerciseAskContext(draft: exercise),
            askTarget: $askTarget,
            askHinted: hints.showAskHint(sessionCount: store.sessions.count),
            infoHinted: hints.showInfoHint(sessionCount: store.sessions.count)
        ) {
            if let recommendedSets = exercise.recommendedSets,
               recommendedSets != max(1, exercise.sets) {
                RecommendedSetsChip(
                    recommended: recommendedSets,
                    count: draftSetBinding(for: index),
                    font: .caption
                )
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

    // MARK: Draft actions

    /// Bottom row: THE gradient pill of the screen — per-draft Save / Update,
    /// swapped for the Saved capsule once written — beside a fixed-width
    /// Revise ghost that hands focus to the composer (the existing revise
    /// path: the next message replaces only this draft). A multi reply with
    /// more than one unsaved draft adds Save both / Save all as a ghost pill
    /// beneath, through the same persist path as each draft's own button.
    private func draftActions(for draft: AIGeneratedRoutineDraft) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                if savedDraftIDs.contains(draft.id) {
                    savedCapsule(for: draft)

                    Spacer(minLength: 0)
                } else {
                    Button(hasSavedLineage(draft) ? "Update Workout" : "Save Workout") {
                        saveDraft(draft)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }

                Button("Revise") {
                    composerFocused = true
                }
                .buttonStyle(GhostButtonStyle(verticalPadding: 17))
                .frame(width: 96)
            }

            if unsavedDraftCount > 1 {
                Button(drafts.count == 2 ? "Save both" : "Save all") {
                    saveAllDrafts()
                }
                .buttonStyle(GhostButtonStyle())
            }
        }
        .padding(.top, 2)
    }

    private func savedCapsule(for draft: AIGeneratedRoutineDraft) -> some View {
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
    }

    // MARK: Draft pager (multi-draft replies only)

    /// "1 OF 2" — tapping advances to the next draft, wrapping.
    private var pagerChip: some View {
        Button {
            showDraft(at: (focusedDraftIndex + 1) % drafts.count, forward: true)
        } label: {
            Text("\(focusedDraftIndex + 1) OF \(drafts.count)")
                .font(.system(.caption2, design: .monospaced).weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(AppTheme.accent)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(AppTheme.accentChipFill)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Draft \(focusedDraftIndex + 1) of \(drafts.count), show next")
    }

    /// Dots to jump between drafts: accent for the focused one, hairline
    /// for the rest.
    private var pagerDots: some View {
        HStack(spacing: 2) {
            ForEach(drafts.indices, id: \.self) { index in
                Button {
                    showDraft(at: index, forward: index > focusedDraftIndex)
                } label: {
                    Circle()
                        .fill(index == focusedDraftIndex ? AppTheme.accent : AppTheme.cardBorder)
                        .frame(width: 6, height: 6)
                        .frame(width: 14, height: 14)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Draft \(index + 1)")
            }
        }
    }

    private var unsavedDraftCount: Int {
        drafts.filter { !savedDraftIDs.contains($0.id) }.count
    }

    /// Horizontal swipe on the card moves between drafts. A no-op with one
    /// draft; vertical drags still belong to the chat scroll.
    private var pagerSwipe: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { value in
                guard drafts.count > 1,
                      abs(value.translation.width) > abs(value.translation.height) else { return }
                let forward = value.translation.width < 0
                showDraft(at: focusedDraftIndex + (forward ? 1 : -1), forward: forward)
            }
    }

    private var pagerTransition: AnyTransition {
        if reduceMotion {
            return .opacity
        }
        return .asymmetric(
            insertion: .move(edge: pagerMovesForward ? .trailing : .leading).combined(with: .opacity),
            removal: .move(edge: pagerMovesForward ? .leading : .trailing).combined(with: .opacity)
        )
    }

    private func showDraft(at index: Int, forward: Bool) {
        guard drafts.indices.contains(index), index != focusedDraftIndex else { return }
        pagerMovesForward = forward
        withAnimation(.easeOut(duration: reduceMotion ? 0.2 : 0.24)) {
            focusedDraftIndex = index
        }
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

    private var contextBannerText: String? {
        switch initialContext {
        case .planning:
            // The opener already frames the planning context — no banner needed.
            return nil
        case .activeWorkout(let snapshot):
            if let checkInNote = nonEmptyText(snapshot.checkInNote) {
                return "Check-in: \(snapshot.routineName) • \(checkInNote)"
            }
            if let nextExercise = nonEmptyText(snapshot.nextExercise) {
                return "Active workout: \(snapshot.routineName) • Up next: \(nextExercise)"
            }
            return "Active workout: \(snapshot.routineName)"
        }
    }

    private var activeWorkoutSnapshot: CoachRoutineSnapshot? {
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
        case .routineEditing:
            return [
                "Does this workout look balanced?",
                "Is this exercise order good?",
                "What might this workout be missing?"
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

    /// The one write path for a Coach draft, exactly once per draft version.
    /// A version whose lineage already produced a routine updates that routine
    /// in place; otherwise it appends a new one and records the lineage.
    /// Marking the id saved before writing makes the action idempotent even
    /// against re-entrant taps.
    private func persistDraft(_ draft: AIGeneratedRoutineDraft) -> CoachRoutinePersistence.Result? {
        guard savedDraftIDs.insert(draft.id).inserted else { return nil }

        guard let result = CoachRoutinePersistence.save(
            draft,
            replacing: savedRoutineIDsByDraft[draft.id],
            in: store
        ) else { return nil }

        switch result {
        case .updated:
            updatedDraftIDs.insert(draft.id)
        case .added(let routine):
            savedRoutineIDsByDraft[draft.id] = routine.id
        }
        return result
    }

    private func saveDraft(_ draft: AIGeneratedRoutineDraft) {
        guard let result = persistDraft(draft) else { return }

        switch result {
        case .updated(let routine):
            withAnimation(.easeOut(duration: 0.18)) {
                saveNotice = SaveNotice(title: "Routine updated", text: "\(routine.name) now matches this draft.")
            }
        case .added:
            withAnimation(.easeOut(duration: 0.18)) {
                saveNotice = SaveNotice(title: "Saved to routines", text: "\(draft.title) is now saved in your routines.")
            }
        }
    }

    /// Saves every unsaved draft of a multi reply, one lineage each.
    private func saveAllDrafts() {
        var savedCount = 0
        var updatedCount = 0
        for draft in drafts where !savedDraftIDs.contains(draft.id) {
            switch persistDraft(draft) {
            case .added?:
                savedCount += 1
            case .updated?:
                updatedCount += 1
            case nil:
                break
            }
        }

        let total = savedCount + updatedCount
        guard total > 0 else { return }
        withAnimation(.easeOut(duration: 0.18)) {
            saveNotice = SaveNotice(
                title: updatedCount > 0 ? "Routines saved" : "Saved to routines",
                text: total == 1
                    ? "1 workout is now in your routines."
                    : "\(total) workouts are now in your routines."
            )
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

        // Sending ends the typing: drop the keyboard so the reply has the
        // screen (the multi-line composer has no Return-to-dismiss).
        composerFocused = false

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

        // The coach always sees the full routine library through its single
        // published owner, so this snapshot cannot lag behind another save.
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
                        let incoming = result.drafts

                        // Carry the lineage forward: the new draft version keeps
                        // pointing at whatever routine its ancestor saved, so a
                        // later save updates that routine instead of appending.
                        // Lineage rules apply to the FIRST incoming draft exactly
                        // as before (the backend's editedRoutineID describes it);
                        // every further draft of a multi reply starts fresh.
                        if let newDraft = incoming.first,
                           let previousDraftID = currentDraft?.id,
                           let lineageRoutineID = savedRoutineIDsByDraft[previousDraftID] {
                            savedRoutineIDsByDraft[newDraft.id] = lineageRoutineID
                        } else if let newDraft = incoming.first,
                                  let editedRoutineID = result.editedRoutineID,
                                  store.routine(withID: editedRoutineID) != nil {
                            // The backend built this draft as an edit of a saved
                            // routine — seed the lineage so the button reads
                            // "Update Workout" and saving upserts in place. The
                            // user still has to tap; nothing is written here.
                            savedRoutineIDsByDraft[newDraft.id] = editedRoutineID
                        }

                        if incoming.count >= 2 {
                            // A multi reply replaces the whole set. A single reply
                            // replaces only the focused draft, so a revise on
                            // draft 2 never touches draft 1.
                            pagerMovesForward = true
                            drafts = incoming
                            focusedDraftIndex = 0
                        } else {
                            currentDraft = incoming.first
                        }
                        changeSummaryDraftIDs = Set(incoming.map(\.id))
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
            if let checkInNote = snapshot.checkInNote?.trimmingCharacters(in: .whitespacesAndNewlines), !checkInNote.isEmpty {
                // M4 safety branch: the check-in reported pain or repeated
                // too-hard — open on it instead of generic session help.
                opener = "I saw your check-in for \(snapshot.routineName): \(checkInNote). Walk me through what happened and we’ll rework the plan — I can edit it right here."
            } else if let nextExercise = snapshot.nextExercise?.trimmingCharacters(in: .whitespacesAndNewlines), !nextExercise.isEmpty {
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

/// Shared geometry for the sent bubble — the real bubble and the in-flight
/// morph render must agree on every one of these so the settle is seamless.
/// Coach prose has no bubble; its font lives here too so both sides of the
/// exchange stay one type system.
private enum ChatBubble {
    static let radius: CGFloat = 18
    static let tailRadius: CGFloat = 4
    static let hPad: CGFloat = 14
    static let vPad: CGFloat = 9
    static let font = Font.system(size: 15)

    /// Coach prose: plain text, generous line height.
    static let coachFont = Font.system(size: 14)
    static let coachLineSpacing: CGFloat = 5

    /// Sent bubble: 18pt corners with a tight 4pt bottom-trailing corner.
    static var userShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: radius,
            bottomLeadingRadius: radius,
            bottomTrailingRadius: tailRadius,
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

        // Surface commits early — by half the flight the bubble has lifted
        // off the composer's card fill onto the sent bubble's elevated
        // surface and its hairline has faded in.
        let colorT = min(posT / 0.5, 1)
        let fill = AppTheme.card.mix(with: AppTheme.surfaceElevated, by: colorT)

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
                .foregroundStyle(AppTheme.textPrimary)
                .padding(.horizontal, ChatBubble.hPad)
                .padding(.vertical, ChatBubble.vPad)
                .frame(width: width, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: width, height: height, alignment: .topLeading)
        .clipShape(shape)
        .overlay {
            shape
                .stroke(AppTheme.cardBorder, lineWidth: 1)
                .opacity(colorT)
        }
        .position(x: minX + width / 2, y: minY + height / 2)
    }

    private func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat {
        a + (b - a) * t
    }
}

/// "Coach is typing": three dots pulsing in a wave, plain on the canvas like
/// the coach's prose. Reduce Motion shows the dots statically.
private struct TypingIndicatorDots: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(AppTheme.textSecondary)
                    .frame(width: 7, height: 7)
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
        .padding(.vertical, 8)
        .onAppear {
            pulsing = true
        }
    }
}
