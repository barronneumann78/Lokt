import SwiftUI
import UIKit

struct OnboardingView: View {
    var onComplete: () -> Void

    @State private var step = 0
    @State private var goingForward = true

    @State private var selectedLocation: OnboardingTrainingLocation?
    @State private var selectedGoal: OnboardingPrimaryGoal?
    @State private var selectedTimeLimit: OnboardingTimeLimit?
    @State private var limitations = ""

    private let totalSteps = 4

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
    }

    // MARK: - Top bar (back · progress · skip)

    private var topBar: some View {
        HStack(spacing: 12) {
            Button {
                goBack()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .frame(width: 40, height: 40)
                    .background(AppTheme.fieldBackground, in: Circle())
            }
            .buttonStyle(.plain)
            .opacity(step > 0 ? 1 : 0)
            .disabled(step == 0)

            Spacer()

            progressDots

            Spacer()

            Button("Skip") {
                onComplete()
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(AppTheme.textSecondary)
            .frame(minWidth: 40, alignment: .trailing)
        }
    }

    private var progressDots: some View {
        HStack(spacing: 8) {
            ForEach(0..<totalSteps, id: \.self) { index in
                Capsule()
                    .fill(index == step ? AppTheme.primary : AppTheme.cardBorder)
                    .frame(width: index == step ? 24 : 8, height: 8)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: step)
    }

    // MARK: - Steps

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case 0:
            questionStep(
                eyebrow: "Where you train",
                title: "Where do you train most?",
                options: OnboardingTrainingLocation.allCases,
                selection: selectedLocation
            ) { option in
                selectedLocation = option
                scheduleAdvance()
            }
        case 1:
            questionStep(
                eyebrow: "Your focus",
                title: "What are you focused on right now?",
                options: OnboardingPrimaryGoal.allCases,
                selection: selectedGoal
            ) { option in
                selectedGoal = option
                scheduleAdvance()
            }
        case 2:
            questionStep(
                eyebrow: "Session length",
                title: "How much time do you usually have?",
                options: OnboardingTimeLimit.allCases,
                selection: selectedTimeLimit
            ) { option in
                selectedTimeLimit = option
                scheduleAdvance()
            }
        default:
            limitationsStep
        }
    }

    private func questionStep<Option: OnboardingOption>(
        eyebrow: String,
        title: String,
        options: [Option],
        selection: Option?,
        onSelect: @escaping (Option) -> Void
    ) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                stepHeader(eyebrow: eyebrow, title: title, subtitle: nil)

                VStack(spacing: 12) {
                    ForEach(options) { option in
                        optionCard(
                            option: option,
                            isSelected: selection?.id == option.id,
                            action: { onSelect(option) }
                        )
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
        }
    }

    private var limitationsStep: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                stepHeader(
                    eyebrow: "Almost done",
                    title: "Anything to work around?",
                    subtitle: "Optional — a quick note helps Lokt avoid aggravating anything. You can edit this later in Settings."
                )

                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous)
                        .fill(AppTheme.fieldBackground)

                    if limitations.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Shoulder irritation, knee pain, low back sensitivity")
                            .font(.body)
                            .foregroundStyle(AppTheme.textSecondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                    }

                    TextEditor(text: $limitations)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 120)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .trackerTextEditorStyle()
                }
                .overlay {
                    RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous)
                        .stroke(AppTheme.cardBorder, lineWidth: 1)
                }

                Button("Finish Setup") {
                    finish()
                }
                .buttonStyle(PrimaryButtonStyle(fill: AppTheme.accent))
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
        }
    }

    private func stepHeader(eyebrow: String, title: String, subtitle: String?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(eyebrow.uppercased())
                .font(.caption.weight(.bold))
                .tracking(1.6)
                .foregroundStyle(AppTheme.primary)

            Text(title)
                .font(.system(size: 30, weight: .black, design: .rounded))
                .foregroundStyle(AppTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func optionCard<Option: OnboardingOption>(
        option: Option,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        let borderColor = isSelected ? AppTheme.primary.opacity(0.55) : AppTheme.cardBorder

        return Button(action: action) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(option.title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)

                    Text(option.subtitle)
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "chevron.right")
                    .font(.headline)
                    .foregroundStyle(isSelected ? AppTheme.primary : AppTheme.textSecondary)
            }
            .padding(16)
            .surfaceCard(cornerRadius: 18, border: borderColor)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Navigation

    private var slideTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: goingForward ? .trailing : .leading).combined(with: .opacity),
            removal: .move(edge: goingForward ? .leading : .trailing).combined(with: .opacity)
        )
    }

    /// Selecting an answer briefly shows the highlight, then slides to the next question.
    private func scheduleAdvance() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            goingForward = true
            withAnimation(.easeInOut(duration: 0.35)) {
                if step < totalSteps - 1 {
                    step += 1
                }
            }
        }
    }

    private func goBack() {
        guard step > 0 else { return }
        goingForward = false
        withAnimation(.easeInOut(duration: 0.35)) {
            step -= 1
        }
    }

    private func finish() {
        savePreferences()
        onComplete()
    }

    private func savePreferences() {
        let location = selectedLocation ?? .commercialGym
        let goal = selectedGoal ?? .buildMuscle
        let timeLimit = selectedTimeLimit ?? .minutes45

        let preferences = AIUserPreferences(
            preferredEquipment: location.preferredEquipment,
            dislikedExercises: [],
            primaryGoal: goal.title,
            limitations: limitations.trimmingCharacters(in: .whitespacesAndNewlines),
            trainingStyle: goal.trainingStyleHint,
            defaultTimeLimitMinutes: timeLimit.minutes
        )

        AIUserPreferencesStore.save(preferences)
    }
}

private protocol OnboardingOption: Identifiable, CaseIterable, Hashable where AllCases: RandomAccessCollection {
    var title: String { get }
    var subtitle: String { get }
}

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

    var subtitle: String {
        switch self {
        case .commercialGym:
            return "Lokt can comfortably use machines, cables, dumbbells, and barbells."
        case .homeGym:
            return "Bias toward practical home setups and fewer machine-dependent choices."
        case .minimalEquipment:
            return "Keep things simple with bodyweight, bands, or a few dumbbells."
        }
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
            return "Short, efficient sessions."
        case .minutes45:
            return "A solid default for most workouts."
        case .minutes60:
            return "More room for fuller sessions."
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
