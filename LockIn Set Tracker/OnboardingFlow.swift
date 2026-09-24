import Foundation

/// The onboarding quiz's step order and its pure rules (look v2 — "tap a
/// tile, it slides on"). Foundation-only so the harness compiles it against
/// `AIUserPreferences.validAge`: the view owns the answers and the slide,
/// this owns what each step is and when it may move on. Nothing here is
/// persisted — the stored `AIUserPreferences` keys and values are unchanged.
enum OnboardingStep: Int, CaseIterable, Hashable {
    case startingPoint
    case focus
    case location
    case session
    case age
    case areas
    case avoid

    static var count: Int { allCases.count }

    var next: OnboardingStep? { OnboardingStep(rawValue: rawValue + 1) }
    var previous: OnboardingStep? { OnboardingStep(rawValue: rawValue - 1) }
    var isFirst: Bool { previous == nil }
    var isLast: Bool { next == nil }

    /// The accent micro label above the question.
    var label: String {
        switch self {
        case .startingPoint: return "YOUR STARTING POINT"
        case .focus: return "YOUR FOCUS"
        case .location: return "WHERE YOU TRAIN"
        case .session: return "USUAL SESSION"
        case .age: return "AGE"
        case .areas: return "AREAS TO WORK AROUND"
        case .avoid: return "ANYTHING ELSE TO AVOID"
        }
    }

    /// The 30pt question — two lines at most.
    var question: String {
        switch self {
        case .startingPoint: return "What best describes you right now?"
        case .focus: return "What are you focused on right now?"
        case .location: return "Where do you train?"
        case .session: return "How long is a usual session?"
        case .age: return "How old are you?"
        case .areas: return "Anything we should work around?"
        case .avoid: return "Anything else to leave out?"
        }
    }

    /// Single-choice steps: tapping a tile selects and slides on. The rest
    /// (age, the multi-select, the free-text note) pin a Continue pill.
    var advancesOnTap: Bool {
        switch self {
        case .startingPoint, .focus, .location, .session: return true
        case .age, .areas, .avoid: return false
        }
    }

    /// Skip — the existing leave-the-quiz action — lives only on the
    /// tap-to-advance steps. Age is required, so it is never skippable.
    var isSkippable: Bool { advancesOnTap }

    /// "2 / 7" — the top-row counter.
    var counterText: String { "\(rawValue + 1) / \(Self.count)" }

    /// Progress segment `index` is filled once its step is done or current.
    func fillsSegment(_ index: Int) -> Bool { index <= rawValue }

    /// Label of the pinned pill on Continue steps.
    var continueTitle: String { isLast ? "Finish Setup" : "Continue" }
}

enum OnboardingFlow {
    /// Continue eligibility. Only age gates: the multi-select's empty set is
    /// a real answer ("None right now") and the note is optional.
    static func canContinue(from step: OnboardingStep, ageText: String) -> Bool {
        switch step {
        case .age:
            return AIUserPreferences.validAge(from: ageText) != nil
        default:
            return true
        }
    }

    /// The one small line under the age field: the requirement while the
    /// field is empty or valid, the range once something invalid is typed.
    static func ageHint(for ageText: String) -> String {
        let trimmed = ageText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, AIUserPreferences.validAge(from: trimmed) == nil {
            return "Enter an age from 13 to 120 to continue."
        }
        return "Required to personalize your starting point."
    }
}
