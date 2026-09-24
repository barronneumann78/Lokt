import SwiftUI

/// The exercise page (look v2, phase 7 — "Exercise — cues in drop-downs"):
/// a quiet title bar, the 24pt name over muscle chips, BEST / e1RM / LAST
/// tiles from the lifter's own history, the content as drop-down sections
/// (FORM CUES open by default, the rest closed — remembered per app), and
/// the ASK LOKT composer pinned at the bottom: its send circle is the
/// screen's one gradient. The add-to-routine sheet lives at the end of the
/// file.
struct ExerciseDetailView: View {
    let exercise: Exercise
    var primaryAddAction: ExerciseDetailPrimaryAddAction? = nil

    @EnvironmentObject private var exerciseStore: ExerciseStore
    @EnvironmentObject private var workoutStore: WorkoutStore
    @State private var showAddSheet = false
    @State private var addFeedbackMessage: String?
    @State private var coachQuestion = ""
    @State private var coachReply: ExerciseCoachReply?
    @State private var coachErrorMessage: String?
    @State private var isRequestingCoach = false
    /// Bumps whenever the answer area changes shape, so the page scrolls
    /// the loading row / reply / error into view above the composer.
    @State private var answerEpoch = 0
    @State private var fetchedCues: [String]?
    @State private var isLoadingCues = false
    @State private var cuesFailed = false
    @State private var simpleExplanation: String?
    @State private var showSimpleExplanation = false
    @State private var isLoadingSimpleExplanation = false
    @State private var simpleExplanationErrorMessage: String?
    @State private var variations: [Exercise] = []
    @State private var stats = ExerciseDetailInsights.Stats.empty
    @FocusState private var composerFocused: Bool

    // Drop-down state persists per app, not per exercise (`ExerciseDetailSection`).
    @AppStorage(ExerciseDetailSection.formCues.storageKey)
    private var cuesOpen = ExerciseDetailSection.formCues.opensByDefault
    @AppStorage(ExerciseDetailSection.howTo.storageKey)
    private var howToOpen = ExerciseDetailSection.howTo.opensByDefault
    @AppStorage(ExerciseDetailSection.plainWords.storageKey)
    private var plainWordsOpen = ExerciseDetailSection.plainWords.opensByDefault
    @AppStorage(ExerciseDetailSection.variations.storageKey)
    private var variationsOpen = ExerciseDetailSection.variations.opensByDefault
    @AppStorage(ExerciseDetailSection.history.storageKey)
    private var historyOpen = ExerciseDetailSection.history.opensByDefault
    /// Analytics → ADVANCED on: HISTORY rows carry their position in the session.
    @AppStorage(AnalyticsAdvanced.storageKey) private var showPositions = false

    private static let answerAnchor = "exercise-detail-answer"

    var body: some View {
        ZStack {
            AppBackground()

            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        header

                        if stats.hasHistory {
                            statsRow
                        }

                        if exercise.imageName != nil {
                            demoCard
                        }

                        cuesSection

                        if !exercise.howTo.isEmpty {
                            howToSection
                        }

                        plainWordsSection

                        if !variations.isEmpty {
                            variationsSection
                        }

                        if stats.hasHistory {
                            historySection
                        }

                        addActions

                        answerArea
                            .id(Self.answerAnchor)
                    }
                    .padding(.horizontal, AppTheme.screenPadding)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                }
                .scrollDismissesKeyboard(.interactively)
                .safeAreaInset(edge: .bottom) {
                    composer
                }
                .onChange(of: answerEpoch) { _, _ in
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(Self.answerAnchor, anchor: .bottom)
                    }
                }
            }
        }
        .dismissKeyboardOnTap()
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAddSheet) {
            ExerciseAddSheet(exercise: exercise) { message in
                addFeedbackMessage = message
            }
        }
        .task {
            loadCuesIfNeeded()
            variations = ExerciseVariations.variations(for: exercise, in: exerciseStore.exercises)
            stats = computeStats()
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(exercise.name)
                .font(.system(size: 24, weight: .bold))
                .tracking(-0.5)
                .foregroundStyle(AppTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            ChipFlowLayout(spacing: 6) {
                ForEach(primaryMuscles, id: \.self) { muscle in
                    muscleChip(muscle, accent: true)
                }
                ForEach(secondaryMuscles, id: \.self) { muscle in
                    muscleChip(muscle, accent: false)
                }
            }
        }
    }

    /// The MUSCLES data (`ExerciseMuscleRoles`), as chips: primaries wear the
    /// accent, secondaries a plain hairline. Spellings that collapse onto the
    /// same muscle show once, and a secondary never repeats a primary.
    private var primaryMuscles: [String] {
        ExerciseMuscleRoles.primaryRoles(for: exercise).map { $0.muscle.sentenceStyled }
    }

    private var secondaryMuscles: [String] {
        var seen = Set(ExerciseMuscleRoles.primaryRoles(for: exercise).map {
            ExerciseMuscleRoles.canonicalMuscle($0.muscle)
        })
        return exercise.metadata.secondaryMuscles.compactMap { raw in
            let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, seen.insert(ExerciseMuscleRoles.canonicalMuscle(name)).inserted else {
                return nil
            }
            return name.sentenceStyled
        }
    }

    private func muscleChip(_ title: String, accent: Bool) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(accent ? AppTheme.primary : AppTheme.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(accent ? AppTheme.accentChipFill : Color.clear)
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .stroke(accent ? AppTheme.accentHairline : AppTheme.cardBorder, lineWidth: 1)
            }
    }

    // MARK: - Stat tiles

    private var statsRow: some View {
        HStack(spacing: 8) {
            statTile(label: "BEST", value: stats.bestLabel)
            statTile(label: "e1RM", value: stats.e1RMLabel, hero: true)
            statTile(label: "LAST", value: stats.lastLabel)
        }
    }

    /// The Analytics headline tile: 16pt card, 10pt label, 22pt mono number.
    /// e1RM is the page's one hero — accent under `.heroGlow()`.
    private func statTile(label: String, value: String, hero: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(AppTheme.textTertiary)
                .lineLimit(1)

            tileValue(value, hero: hero)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .glassCard(cornerRadius: 16)
    }

    @ViewBuilder
    private func tileValue(_ value: String, hero: Bool) -> some View {
        let text = Text(value)
            .font(.system(size: 22, weight: .bold))
            .monospacedDigit()
            .tracking(-0.5)
            .foregroundStyle(hero ? AppTheme.primary : AppTheme.textPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)

        if hero {
            text.heroGlow()
        } else {
            text
        }
    }

    /// Only for exercises that ship a real demo (custom entries with media);
    /// the bundled library has none, and the placeholder icon would only
    /// push the content down.
    private var demoCard: some View {
        ExerciseMediaView(
            imageName: exercise.imageName,
            placeholderSystemImageName: exercise.placeholderSystemImageName,
            height: 220,
            cornerRadius: 18,
            iconSize: 48,
            contentPadding: 10,
            maxContentWidth: 250
        )
        .frame(maxWidth: .infinity)
        .glassCard(cornerRadius: 18)
    }

    // MARK: - Form cues

    private var displayCues: [String] {
        if !exercise.cues.isEmpty {
            return Array(exercise.cues.prefix(3))
        }

        if let fetchedCues {
            return Array(fetchedCues.prefix(3))
        }

        return []
    }

    private var cuesSection: some View {
        DetailSection(title: "FORM CUES", isOpen: $cuesOpen) {
            if !displayCues.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(displayCues.enumerated()), id: \.offset) { index, cue in
                        numberedCue(index + 1, cue)
                    }
                }
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
    }

    /// Concept cue row: a 22pt accent-outlined circle number on the elevated
    /// surface, then 14pt text.
    private func numberedCue(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.system(size: 11, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(AppTheme.primary)
                .frame(width: 22, height: 22)
                .background(AppTheme.surfaceElevated)
                .clipShape(Circle())
                .overlay {
                    Circle()
                        .stroke(AppTheme.accentHairline, lineWidth: 1)
                }

            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(AppTheme.textPrimary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
    }

    // MARK: - How to

    private var howToSection: some View {
        DetailSection(title: "HOW TO", count: "\(exercise.howTo.count)", isOpen: $howToOpen) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(exercise.howTo.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(index + 1)")
                            .font(.system(size: 12, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(AppTheme.textTertiary)
                            .frame(width: 22, alignment: .center)
                            .padding(.top, 1)

                        Text(step)
                            .font(.system(size: 14))
                            .foregroundStyle(AppTheme.textSecondary)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    // MARK: - In plain words

    /// The library description, with the simpler-explanation control beneath
    /// it; the AI's plain-words version replaces the control once it lands.
    private var plainWordsSection: some View {
        DetailSection(title: "IN PLAIN WORDS", isOpen: $plainWordsOpen) {
            VStack(alignment: .leading, spacing: 12) {
                if !exercise.description.isEmpty {
                    Text(exercise.description)
                        .font(.system(size: 14))
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if showSimpleExplanation, let simpleExplanation {
                    Divider().overlay(AppTheme.cardBorder)

                    Text(simpleExplanation)
                        .font(.system(size: 14))
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Button(isLoadingSimpleExplanation ? "Explaining..." : "Explain It Simply") {
                        requestSimpleExplanation()
                    }
                    .buttonStyle(GhostButtonStyle(isCompact: true))
                    .disabled(isLoadingSimpleExplanation)
                }

                if let simpleExplanationErrorMessage {
                    Text(simpleExplanationErrorMessage)
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondary)
                }
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

    // MARK: - Variations

    private var variationsSection: some View {
        DetailSection(
            title: "VARIATIONS",
            count: "\(variations.count)",
            isOpen: $variationsOpen,
            contentBottomPadding: 6
        ) {
            VStack(spacing: 0) {
                ForEach(Array(variations.enumerated()), id: \.element.id) { index, variation in
                    NavigationLink(destination: ExerciseDetailView(exercise: variation, primaryAddAction: primaryAddAction)) {
                        HStack(spacing: 10) {
                            Text(variation.name)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(AppTheme.textPrimary)
                                .multilineTextAlignment(.leading)

                            Spacer(minLength: 8)

                            Text(variationDescriptor(for: variation))
                                .font(.caption)
                                .foregroundStyle(AppTheme.textSecondary)

                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(AppTheme.textTertiary)
                        }
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if index < variations.count - 1 {
                        Divider().overlay(AppTheme.cardBorder)
                    }
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

    // MARK: - History

    private var historySection: some View {
        DetailSection(
            title: "HISTORY",
            count: ExerciseDetailInsights.sessionsLabel(stats.sessionCount),
            isOpen: $historyOpen,
            contentBottomPadding: 6
        ) {
            VStack(spacing: 0) {
                ForEach(Array(stats.recent.enumerated()), id: \.element.id) { index, row in
                    HStack(spacing: 8) {
                        Text(ExerciseDetailInsights.dayLabel(row.date, now: Date(), calendar: .current))
                            .font(.system(size: 14, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(AppTheme.textPrimary)

                        if let tag = ExerciseDetailInsights.positionTag(row.position, advanced: showPositions) {
                            Text(tag)
                                .font(.caption2)
                                .monospacedDigit()
                                .foregroundStyle(AppTheme.textTertiary)
                                .fixedSize()
                        }

                        Spacer(minLength: 8)

                        Text(row.bestSet.label)
                            .font(.system(size: 14, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(AppTheme.textPrimary)
                    }
                    .padding(.vertical, 10)

                    if index < stats.recent.count - 1 {
                        Divider().overlay(AppTheme.cardBorder)
                    }
                }
            }
        }
    }

    /// Tiles and history from the store, aliases merged the way Analytics
    /// merges them: a log key belongs to this exercise when it is the same
    /// name or the library resolves it to this entry.
    private func computeStats() -> ExerciseDetailInsights.Stats {
        let library = exerciseStore.exercises
        var resolved: [String: Bool] = [:]

        func matches(_ name: String) -> Bool {
            if let cached = resolved[name] { return cached }
            let hit = name.caseInsensitiveCompare(exercise.name) == .orderedSame
                || library.resolvedExercise(named: name)?.id == exercise.id
            resolved[name] = hit
            return hit
        }

        return ExerciseDetailInsights.stats(
            for: exercise.name,
            sessions: workoutStore.sessions,
            routineOrders: ExercisePositionLogic.routineOrders(from: workoutStore.routines),
            isMatch: matches
        )
    }

    // MARK: - Add to routine

    /// Ghost pills only — the composer's send circle is the screen's one
    /// gradient. Same actions and sheet as before.
    private var addActions: some View {
        VStack(spacing: 10) {
            if let primaryAddAction {
                Button(primaryAddAction.title) {
                    addFeedbackMessage = primaryAddAction.perform(exercise).message
                }
                .buttonStyle(GhostButtonStyle())

                Button("Add Somewhere Else") {
                    showAddSheet = true
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)
            } else {
                Button("Add to Routine") {
                    showAddSheet = true
                }
                .buttonStyle(GhostButtonStyle())
            }

            if let addFeedbackMessage {
                Label(addFeedbackMessage, systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.success)
            }
        }
        .padding(.top, 4)
    }

    // MARK: - Ask Lokt

    /// Where the answer lands: the loading row, the coach take, or the
    /// error — in the scroll, right above the pinned composer.
    private var answerArea: some View {
        VStack(alignment: .leading, spacing: 12) {
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

    /// Pinned composer: ASK LOKT over a 50pt card-fill capsule holding the
    /// question field and the 38pt gradient send circle. Return sends; the
    /// screen's tap-outside / scroll dismissal handles the keyboard.
    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ASK LOKT")
                .microLabel()

            HStack(spacing: 6) {
                TrackerTextField("Ask about this exercise", text: $coachQuestion)
                    .font(.system(size: 15))
                    .foregroundStyle(AppTheme.textPrimary)
                    .tint(AppTheme.primary)
                    .focused($composerFocused)
                    .submitLabel(.send)
                    .onSubmit {
                        requestCoachAnswer(for: coachQuestion, updatingField: true)
                    }
                    .padding(.leading, 12)

                Button {
                    requestCoachAnswer(for: coachQuestion, updatingField: true)
                } label: {
                    ZStack {
                        if isRequestingCoach {
                            ProgressView()
                                .tint(AppTheme.backgroundTop)
                        } else {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(AppTheme.backgroundTop)
                        }
                    }
                    .frame(width: 38, height: 38)
                    .background(AppTheme.primaryGradient)
                    .clipShape(Circle())
                    .opacity(canAsk || isRequestingCoach ? 1 : 0.4)
                }
                .buttonStyle(.plain)
                .disabled(!canAsk)
                .accessibilityLabel("Ask Lokt")
            }
            .padding(.horizontal, 6)
            .frame(minHeight: 50)
            .background(AppTheme.card)
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .stroke(AppTheme.cardBorder, lineWidth: 1)
            }
        }
        .padding(.horizontal, AppTheme.screenPadding)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(
            AppTheme.backgroundTop
                .ignoresSafeArea()
        )
    }

    private var canAsk: Bool {
        !isRequestingCoach && coachQuestion.trimmingCharacters(in: .whitespacesAndNewlines).count >= 4
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
        guard trimmedQuestion.count >= 4, !isRequestingCoach else { return }

        if updatingField {
            coachQuestion = trimmedQuestion
        }
        composerFocused = false

        Task {
            await MainActor.run {
                isRequestingCoach = true
                coachErrorMessage = nil
                answerEpoch += 1
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
                    answerEpoch += 1
                }
            } catch {
                await MainActor.run {
                    coachErrorMessage = error.localizedDescription
                    isRequestingCoach = false
                    answerEpoch += 1
                }
            }
        }
    }
}

struct ExerciseDetailPrimaryAddAction {
    var title: String
    var perform: (Exercise) -> AddExerciseResult
}

/// One drop-down on the exercise page: an 18pt card whose header row is the
/// micro label (plus an optional mono count) and a chevron; the body shows
/// only while open. Open state belongs to the caller (`@AppStorage`).
private struct DetailSection<Content: View>: View {
    let title: String
    var count: String? = nil
    @Binding var isOpen: Bool
    var contentBottomPadding: CGFloat = 16
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(ExerciseDetailDisclosure.animation) {
                    isOpen.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    (Text(title) + Text(count.map { " · \($0)" } ?? "").monospacedDigit())
                        .microLabel()
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.textTertiary)
                        .rotationEffect(.degrees(isOpen ? 180 : 0))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title.capitalized)
            .accessibilityValue(isOpen ? "Expanded" : "Collapsed")

            if isOpen {
                content()
                    .padding(.horizontal, 16)
                    .padding(.bottom, contentBottomPadding)
                    .transition(.opacity)
            }
        }
        .glassCard(cornerRadius: 18)
    }
}

/// Left-aligned wrapping row for the muscle chips (an exercise carries up to
/// six), so a long list folds onto a second line instead of clipping.
private struct ChipFlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(subviews: subviews, width: proposal.width ?? .infinity).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let placement = arrange(subviews: subviews, width: bounds.width)
        for (index, origin) in placement.origins.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y),
                proposal: .unspecified
            )
        }
    }

    private func arrange(subviews: Subviews, width: CGFloat) -> (size: CGSize, origins: [CGPoint]) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widest: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }

        return (CGSize(width: widest, height: y + rowHeight), origins)
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

/// Add-to-routine picker: EXISTING ROUTINES as card rows, NEW ROUTINE as
/// the sheet's one gradient pill. `RoutineLibrary.addExercise` /
/// `createRoutine` paths are unchanged.
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
                    VStack(alignment: .leading, spacing: 24) {
                        Text(exercise.name)
                            .font(.system(size: 24, weight: .bold))
                            .tracking(-0.5)
                            .foregroundStyle(AppTheme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)

                        existingRoutineSection
                        createRoutineSection
                    }
                    .padding(.horizontal, AppTheme.screenPadding)
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

    @ViewBuilder
    private var existingRoutineSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("EXISTING ROUTINES")
                .microLabel()

            if routines.isEmpty {
                Text("No saved routines yet.")
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
                            VStack(alignment: .leading, spacing: 3) {
                                Text(routine.name)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(AppTheme.textPrimary)
                                    .multilineTextAlignment(.leading)

                                Text("\(routine.exercises.count) exercise\(routine.exercises.count == 1 ? "" : "s")")
                                    .font(.caption)
                                    .monospacedDigit()
                                    .foregroundStyle(AppTheme.textSecondary)
                            }

                            Spacer()

                            Image(systemName: "plus")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                        .padding(16)
                        .contentShape(Rectangle())
                        .glassCard(cornerRadius: 18)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var createRoutineSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("NEW ROUTINE")
                .microLabel()

            Button("Create a New Routine") {
                let routine = RoutineLibrary.createRoutine(from: exercise.name, in: workoutStore)
                onComplete("Created \(routine.name).")
                dismiss()
            }
            .buttonStyle(PrimaryButtonStyle())
        }
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
