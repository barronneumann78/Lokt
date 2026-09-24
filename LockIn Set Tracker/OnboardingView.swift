import SwiftUI
import UIKit

/// The onboarding quiz — "tap a tile, it slides on" (look v2). One question
/// per `OnboardingStep`: an accent micro label, a 30pt question, big tiles.
/// Single-choice steps advance on tap (the check lands, ~250ms, then the
/// slide); age / areas / the note pin the screen's one gradient pill.
/// Stored keys and values are untouched — `savePreferences` writes the same
/// `AIUserPreferences` as before, and `onComplete` still flips the
/// `hasCompletedOnboarding` flag at the app root (Settings → Retake Quiz
/// clears it to restart here).
struct OnboardingView: View {
    var onComplete: () -> Void

    @State private var step: OnboardingStep = .startingPoint
    @State private var goingForward = true
    @State private var advancingFrom: OnboardingStep?

    @State private var selectedExperience: TrainingExperience?
    @State private var selectedGoal: OnboardingPrimaryGoal?
    @State private var selectedLocation: OnboardingTrainingLocation?
    @State private var selectedTimeLimit: OnboardingTimeLimit?
    @State private var ageText = ""
    @State private var selectedInjuryFlags: Set<InjuryFlag> = []
    @State private var limitations = ""

    @FocusState private var ageFieldFocused: Bool

    private static let tileCornerRadius: CGFloat = 20

    var body: some View {
        ZStack {
            AppBackground()

            VStack(spacing: 20) {
                topBar
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                stepContent
                    .id(step)
                    .transition(slideTransition)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .dismissKeyboardOnTap()
        .keyboardDoneBar()
    }

    // MARK: - Top row (back · segments · counter)

    private var topBar: some View {
        HStack(spacing: 14) {
            Button {
                goBack()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .frame(width: 36, height: 36, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(step.isFirst ? 0 : 1)
            .disabled(step.isFirst)

            progressSegments

            Text(step.counterText)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(AppTheme.textTertiary)
                .frame(width: 44, alignment: .trailing)
        }
    }

    /// One 4pt segment per step: done + current wear the gradient token, the
    /// rest stay hairline.
    private var progressSegments: some View {
        HStack(spacing: 4) {
            ForEach(0..<OnboardingStep.count, id: \.self) { index in
                Capsule()
                    .fill(step.fillsSegment(index)
                          ? AnyShapeStyle(AppTheme.primaryGradient)
                          : AnyShapeStyle(AppTheme.cardBorder))
                    .frame(height: 4)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: step)
    }

    // MARK: - Steps

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .startingPoint:
            tapStep(options: TrainingExperience.allCases, selection: selectedExperience) {
                selectedExperience = $0
            }
        case .focus:
            tapStep(options: OnboardingPrimaryGoal.allCases, selection: selectedGoal) {
                selectedGoal = $0
            }
        case .location:
            tapStep(options: OnboardingTrainingLocation.allCases, selection: selectedLocation) {
                selectedLocation = $0
            }
        case .session:
            tapStep(options: OnboardingTimeLimit.allCases, selection: selectedTimeLimit) {
                selectedTimeLimit = $0
            }
        case .age:
            ageStep
        case .areas:
            areasStep
        case .avoid:
            avoidStep
        }
    }

    /// A single-choice step: tiles that select and slide on.
    private func tapStep<Option: OnboardingOption>(
        options: [Option],
        selection: Option?,
        select: @escaping (Option) -> Void
    ) -> some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    stepHeader

                    VStack(spacing: 12) {
                        ForEach(options) { option in
                            optionTile(
                                title: option.title,
                                subtitle: option.subtitle,
                                isSelected: selection?.id == option.id
                            ) {
                                select(option)
                                scheduleAdvance()
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }

            tapFooter
        }
    }

    private var ageStep: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    stepHeader

                    VStack(alignment: .leading, spacing: 10) {
                        TrackerTextField("Your age", text: $ageText)
                            .textFieldStyle(TrackerTextFieldStyle())
                            .font(.system(size: 22, weight: .bold))
                            .keyboardType(.numberPad)
                            .focused($ageFieldFocused)

                        Text(OnboardingFlow.ageHint(for: ageText))
                            .font(.system(size: 13))
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)

            continueFooter(enabled: OnboardingFlow.canContinue(from: .age, ageText: ageText)) {
                ageFieldFocused = false
                advance()
            }
        }
        .onAppear {
            // Land the keyboard after the slide, not during it.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                if step == .age {
                    ageFieldFocused = true
                }
            }
        }
    }

    /// Multi-select: "None right now" is the empty set, every flag toggles.
    private var areasStep: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    stepHeader

                    VStack(spacing: 12) {
                        optionTile(title: "None right now", subtitle: nil, isSelected: selectedInjuryFlags.isEmpty) {
                            selectedInjuryFlags.removeAll()
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }

                        ForEach(InjuryFlag.allCases) { flag in
                            optionTile(title: flag.title, subtitle: nil, isSelected: selectedInjuryFlags.contains(flag)) {
                                toggle(flag)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }

            continueFooter(enabled: true) {
                advance()
            }
        }
    }

    private var avoidStep: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    stepHeader

                    limitationsField

                    Text("Lokt is not medical care. Stop if a movement hurts, and get professional guidance before training with symptoms or a medical condition.")
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)

            continueFooter(enabled: true) {
                finish()
            }
        }
    }

    private var limitationsField: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: Self.tileCornerRadius, style: .continuous)
                .fill(AppTheme.fieldBackground)

            if limitations.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("For example: avoid overhead pressing or deep knee bends")
                    .font(.body)
                    .foregroundStyle(AppTheme.textSecondary)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 16)
            }

            TextEditor(text: $limitations)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 120)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .trackerTextEditorStyle()
        }
        .overlay {
            RoundedRectangle(cornerRadius: Self.tileCornerRadius, style: .continuous)
                .stroke(AppTheme.cardBorder, lineWidth: 1)
        }
    }

    // MARK: - Pieces

    private var stepHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(step.label)
                .microLabel(AppTheme.accent)

            Text(step.question)
                .font(.system(size: 30, weight: .bold))
                .tracking(-0.5)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .foregroundStyle(AppTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The board's tile: 17pt bold title, optional 13pt subtitle, a 26pt
    /// mark on the right — hairline at rest, the gradient token with a
    /// near-black check when selected (tile fill `accentChipFill`, border
    /// `accentHairline`: the app's chip vocabulary).
    private func optionTile(
        title: String,
        subtitle: String?,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 17, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(AppTheme.textPrimary)
                        .multilineTextAlignment(.leading)

                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 13))
                            .foregroundStyle(AppTheme.textSecondary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 12)

                selectionMark(isSelected: isSelected)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: Self.tileCornerRadius, style: .continuous)
                        .fill(AppTheme.accentChipFill)
                }
            }
            .glassCard(cornerRadius: Self.tileCornerRadius)
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: Self.tileCornerRadius, style: .continuous)
                        .stroke(AppTheme.accentHairline, lineWidth: 1)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: Self.tileCornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func selectionMark(isSelected: Bool) -> some View {
        ZStack {
            if isSelected {
                Circle()
                    .fill(AppTheme.primaryGradient)

                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(AppTheme.backgroundTop)
            } else {
                Circle()
                    .stroke(AppTheme.cardBorder, lineWidth: 1)
            }
        }
        .frame(width: 26, height: 26)
    }

    /// Under the tiles on tap-to-advance steps: the hint on the left, the
    /// existing leave-the-quiz Skip on the right.
    private var tapFooter: some View {
        HStack {
            Text("Tap one — it slides on")
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.textTertiary)

            Spacer()

            if step.isSkippable {
                Button {
                    onComplete()
                } label: {
                    Text("Skip")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.textSecondary)
                        .padding(.vertical, 6)
                        .padding(.leading, 12)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    /// The screen's one gradient pill, pinned under the Continue steps.
    private func continueFooter(enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(step.continueTitle, action: action)
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!enabled)
            .opacity(enabled ? 1 : 0.55)
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 12)
    }

    // MARK: - Navigation

    private var slideTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: goingForward ? .trailing : .leading).combined(with: .opacity),
            removal: .move(edge: goingForward ? .leading : .trailing).combined(with: .opacity)
        )
    }

    /// Tap-to-advance: the check lands, then ~250ms later the slide. A second
    /// tap inside that window re-points the selection without scheduling a
    /// second slide; leaving the step cancels the pending one.
    private func scheduleAdvance() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        guard advancingFrom == nil else { return }
        advancingFrom = step
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            let pending = advancingFrom
            advancingFrom = nil
            guard pending == step else { return }
            advance()
        }
    }

    private func advance() {
        guard let next = step.next else { return }
        goingForward = true
        withAnimation(.easeInOut(duration: 0.35)) {
            step = next
        }
    }

    private func goBack() {
        guard let previous = step.previous else { return }
        goingForward = false
        withAnimation(.easeInOut(duration: 0.35)) {
            step = previous
        }
    }

    private func toggle(_ flag: InjuryFlag) {
        if selectedInjuryFlags.contains(flag) {
            selectedInjuryFlags.remove(flag)
        } else {
            selectedInjuryFlags.insert(flag)
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func finish() {
        guard hasValidAge else {
            // Age was cleared after passing its step — slide back to it.
            goingForward = false
            withAnimation(.easeInOut(duration: 0.35)) {
                step = .age
            }
            return
        }
        savePreferences()
        onComplete()
    }

    private var hasValidAge: Bool {
        AIUserPreferences.validAge(from: ageText) != nil
    }

    private func savePreferences() {
        let experience = selectedExperience ?? .newToTraining
        let location = selectedLocation ?? .commercialGym
        let goal = selectedGoal ?? .buildMuscle
        let timeLimit = selectedTimeLimit ?? .minutes45

        let preferences = AIUserPreferences(
            preferredEquipment: location.preferredEquipment,
            dislikedExercises: [],
            primaryGoal: goal.title,
            limitations: limitations.trimmingCharacters(in: .whitespacesAndNewlines),
            trainingStyle: goal.trainingStyleHint,
            defaultTimeLimitMinutes: timeLimit.minutes,
            trainingExperience: experience,
            age: AIUserPreferences.validAge(from: ageText),
            injuryFlags: InjuryFlag.allCases.filter(selectedInjuryFlags.contains)
        )

        AIUserPreferencesStore.save(preferences)
    }
}

private protocol OnboardingOption: Identifiable, CaseIterable, Hashable where AllCases: RandomAccessCollection {
    var title: String { get }
    var subtitle: String { get }
}

extension TrainingExperience: OnboardingOption {}

private enum OnboardingTrainingLocation: String, CaseIterable, Hashable, OnboardingOption {
    case commercialGym
    case homeGym
    case minimalEquipment

    var id: String { rawValue }

    var title: String {
        switch self {
        case .commercialGym:
            return "Commercial Gym"
        case .homeGym:
            return "Home Gym"
        case .minimalEquipment:
            return "Minimal Equipment"
        }
    }

    /// Factual: exactly the equipment list the plan will be told to use.
    var subtitle: String {
        let list = preferredEquipment.joined(separator: ", ")
        return list.prefix(1).uppercased() + list.dropFirst()
    }

    var preferredEquipment: [String] {
        switch self {
        case .commercialGym:
            return ["machines", "cables", "dumbbells", "barbells"]
        case .homeGym:
            return ["dumbbells", "barbells", "bench", "bodyweight"]
        case .minimalEquipment:
            return ["bodyweight", "bands", "dumbbells"]
        }
    }
}

private enum OnboardingPrimaryGoal: String, CaseIterable, Hashable, OnboardingOption {
    case buildMuscle
    case getStronger
    case generalFitness
    case loseFat

    var id: String { rawValue }

    var title: String {
        switch self {
        case .buildMuscle:
            return "Build Muscle"
        case .getStronger:
            return "Get Stronger"
        case .generalFitness:
            return "General Fitness"
        case .loseFat:
            return "Lose Fat"
        }
    }

    var subtitle: String {
        switch self {
        case .buildMuscle:
            return "Bias toward hypertrophy-friendly volume and exercise selection."
        case .getStronger:
            return "Bias toward heavier compounds and steady progression."
        case .generalFitness:
            return "Keep sessions balanced, practical, and easy to recover from."
        case .loseFat:
            return "Keep sessions efficient with enough training density to stay moving."
        }
    }

    var trainingStyleHint: String {
        switch self {
        case .buildMuscle:
            return "Hypertrophy-focused with solid volume and controlled reps"
        case .getStronger:
            return "Strength-focused with compounds first and lower rep top sets"
        case .generalFitness:
            return "Balanced training with practical full-body or split sessions"
        case .loseFat:
            return "Efficient sessions with steady pace and moderate rest"
        }
    }
}

private enum OnboardingTimeLimit: String, CaseIterable, Hashable, OnboardingOption {
    case minutes30
    case minutes45
    case minutes60

    var id: String { rawValue }

    var title: String {
        "\(minutes) minutes"
    }

    var subtitle: String {
        switch self {
        case .minutes30:
            return "Quick"
        case .minutes45:
            return "Balanced"
        case .minutes60:
            return "Full"
        }
    }

    var minutes: Int {
        switch self {
        case .minutes30:
            return 30
        case .minutes45:
            return 45
        case .minutes60:
            return 60
        }
    }
}
