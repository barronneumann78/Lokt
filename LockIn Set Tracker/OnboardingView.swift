import SwiftUI

struct OnboardingView: View {
    var onComplete: () -> Void

    @State private var selectedLocation: OnboardingTrainingLocation = .commercialGym
    @State private var selectedGoal: OnboardingPrimaryGoal = .buildMuscle
    @State private var selectedTimeLimit: OnboardingTimeLimit = .minutes45
    @State private var limitations = ""

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    headerSection
                    locationSection
                    goalSection
                    timeSection
                    limitationsSection
                    actionSection
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 20)
            }
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Help Lokt get a head start.")
                .font(.system(size: 32, weight: .black, design: .rounded))
                .foregroundStyle(AppTheme.textPrimary)

            Text("This is a quick setup, not a long quiz. You can skip it now and edit everything later in Settings.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
        }
        .padding(20)
        .glassCard()
    }

    private var locationSection: some View {
        questionCard(
            title: "Where do you train most?",
            options: OnboardingTrainingLocation.allCases,
            selected: selectedLocation
        ) { selectedLocation = $0 }
    }

    private var goalSection: some View {
        questionCard(
            title: "What are you focused on right now?",
            options: OnboardingPrimaryGoal.allCases,
            selected: selectedGoal
        ) { selectedGoal = $0 }
    }

    private var timeSection: some View {
        questionCard(
            title: "How much time do you usually have?",
            options: OnboardingTimeLimit.allCases,
            selected: selectedTimeLimit
        ) { selectedTimeLimit = $0 }
    }

    private var limitationsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Anything to work around?")
                .font(.title3.weight(.bold))
                .foregroundStyle(AppTheme.textPrimary)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous)
                    .fill(AppTheme.fieldBackground)

                if limitations.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Optional: shoulder irritation, knee pain, low back sensitivity")
                        .font(.body)
                        .foregroundStyle(AppTheme.textSecondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                }

                TextEditor(text: $limitations)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 92)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .trackerTextEditorStyle()
            }
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous)
                    .stroke(AppTheme.cardBorder, lineWidth: 1)
            }

            Text("Optional. Short notes are enough.")
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)
        }
        .padding(20)
        .glassCard()
    }

    private var actionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button("Save and Continue") {
                savePreferences()
                onComplete()
            }
            .buttonStyle(PrimaryButtonStyle(fill: AppTheme.accent))

            Button("Skip for Now") {
                onComplete()
            }
            .buttonStyle(SecondaryButtonStyle())
        }
        .padding(20)
        .glassCard()
    }

    private func questionCard<Option: OnboardingOption>(
        title: String,
        options: [Option],
        selected: Option,
        onSelect: @escaping (Option) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title3.weight(.bold))
                .foregroundStyle(AppTheme.textPrimary)

            ForEach(options) { option in
                let isSelected = selected.id == option.id
                let iconName = isSelected ? "checkmark.circle.fill" : "circle"
                let iconColor = isSelected ? AppTheme.primary : AppTheme.textSecondary
                let borderColor = isSelected ? AppTheme.primary.opacity(0.32) : AppTheme.cardBorder

                Button {
                    onSelect(option)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: iconName)
                            .font(.headline)
                            .foregroundStyle(iconColor)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(option.title)
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(AppTheme.textPrimary)

                            Text(option.subtitle)
                                .font(.caption)
                                .foregroundStyle(AppTheme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer()
                    }
                    .padding(16)
                    .surfaceCard(cornerRadius: 18, border: borderColor)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(20)
        .glassCard()
    }

    private func savePreferences() {
        let preferences = AIUserPreferences(
            preferredEquipment: selectedLocation.preferredEquipment,
            dislikedExercises: [],
            primaryGoal: selectedGoal.title,
            limitations: limitations.trimmingCharacters(in: .whitespacesAndNewlines),
            trainingStyle: selectedGoal.trainingStyleHint,
            defaultTimeLimitMinutes: selectedTimeLimit.minutes
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
