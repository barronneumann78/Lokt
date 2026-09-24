// Logic check: onboarding flow (look v2 — OnboardingFlow.swift).
// - Seven steps in the board's order; first/last and the next/previous chain.
// - Counter text "N / 7"; progress segments filled through the current step.
// - Tap-to-advance vs Continue split; Skip only on tap steps (age required).
// - Continue eligibility: age gates on AIUserPreferences.validAge (13...120,
//   trimmed); every other step is always eligible; the age hint copy swaps.
// - The approved labels, the kept question copy, the pill titles.
// Compiles against the REAL OnboardingFlow.swift + AIUserPreferences.swift.
import Foundation

var failures = 0
func check(_ name: String, _ condition: Bool) {
    if condition {
        print("  PASS  \(name)")
    } else {
        print("  FAIL  \(name)")
        failures += 1
    }
}

let steps = OnboardingStep.allCases

// MARK: - Order

check("seven steps", OnboardingStep.count == 7 && steps.count == 7)
check("board order", steps == [.startingPoint, .focus, .location, .session, .age, .areas, .avoid])
check("first step is starting point", OnboardingStep.startingPoint.isFirst && !OnboardingStep.focus.isFirst)
check("last step is the note", OnboardingStep.avoid.isLast && !OnboardingStep.areas.isLast)
check("next chain walks the order", steps.dropLast().map { $0.next } == steps.dropFirst().map { Optional($0) })
check("previous chain walks back", steps.dropFirst().map { $0.previous } == steps.dropLast().map { Optional($0) })
check("no next after last", OnboardingStep.avoid.next == nil)
check("no previous before first", OnboardingStep.startingPoint.previous == nil)

// MARK: - Counter + segments

check("counter 1 / 7", OnboardingStep.startingPoint.counterText == "1 / 7")
check("counter 5 / 7", OnboardingStep.age.counterText == "5 / 7")
check("counter 7 / 7", OnboardingStep.avoid.counterText == "7 / 7")
check("segments: only the first on step 1",
      (0..<7).map { OnboardingStep.startingPoint.fillsSegment($0) } == [true, false, false, false, false, false, false])
check("segments: done + current on step 3",
      (0..<7).map { OnboardingStep.location.fillsSegment($0) } == [true, true, true, false, false, false, false])
check("segments: all on the last step", (0..<7).allSatisfy { OnboardingStep.avoid.fillsSegment($0) })
check("segments: never ahead of the current step", !OnboardingStep.focus.fillsSegment(2))

// MARK: - Tap-to-advance vs Continue

check("tap steps are the four single choices",
      steps.filter(\.advancesOnTap) == [.startingPoint, .focus, .location, .session])
check("continue steps are age, areas, note",
      steps.filter { !$0.advancesOnTap } == [.age, .areas, .avoid])
check("skip only on tap steps", steps.filter(\.isSkippable) == steps.filter(\.advancesOnTap))
check("age is never skippable", !OnboardingStep.age.isSkippable)
check("areas and note are not skippable", !OnboardingStep.areas.isSkippable && !OnboardingStep.avoid.isSkippable)

// MARK: - Continue eligibility

check("age: empty blocks", !OnboardingFlow.canContinue(from: .age, ageText: ""))
check("age: whitespace blocks", !OnboardingFlow.canContinue(from: .age, ageText: "   "))
check("age: 12 blocks", !OnboardingFlow.canContinue(from: .age, ageText: "12"))
check("age: 13 passes", OnboardingFlow.canContinue(from: .age, ageText: "13"))
check("age: 120 passes", OnboardingFlow.canContinue(from: .age, ageText: "120"))
check("age: 121 blocks", !OnboardingFlow.canContinue(from: .age, ageText: "121"))
check("age: trimmed passes", OnboardingFlow.canContinue(from: .age, ageText: " 34 "))
check("age: letters block", !OnboardingFlow.canContinue(from: .age, ageText: "abc"))
check("age: decimal blocks", !OnboardingFlow.canContinue(from: .age, ageText: "30.5"))
check("age: negative blocks", !OnboardingFlow.canContinue(from: .age, ageText: "-30"))
check("areas always continues (empty set is None right now)", OnboardingFlow.canContinue(from: .areas, ageText: ""))
check("note always continues", OnboardingFlow.canContinue(from: .avoid, ageText: ""))
check("tap steps always continue", [OnboardingStep.startingPoint, .focus, .location, .session]
      .allSatisfy { OnboardingFlow.canContinue(from: $0, ageText: "") })
check("eligibility matches validAge exactly",
      ["", "5", "13", "64", "120", "121", "x"].allSatisfy {
          OnboardingFlow.canContinue(from: .age, ageText: $0) == (AIUserPreferences.validAge(from: $0) != nil)
      })

// MARK: - Age hint copy

let required = "Required to personalize your starting point."
let range = "Enter an age from 13 to 120 to continue."
check("hint: requirement while empty", OnboardingFlow.ageHint(for: "") == required)
check("hint: requirement while whitespace", OnboardingFlow.ageHint(for: "  ") == required)
check("hint: requirement while valid", OnboardingFlow.ageHint(for: "30") == required)
check("hint: range once invalid", OnboardingFlow.ageHint(for: "7") == range)
check("hint: range on letters", OnboardingFlow.ageHint(for: "abc") == range)
check("hint: range past 120", OnboardingFlow.ageHint(for: "130") == range)

// MARK: - Copy

check("labels are the approved step titles", steps.map(\.label) == [
    "YOUR STARTING POINT", "YOUR FOCUS", "WHERE YOU TRAIN", "USUAL SESSION",
    "AGE", "AREAS TO WORK AROUND", "ANYTHING ELSE TO AVOID"
])
check("labels are uppercase micro labels", steps.allSatisfy { $0.label == $0.label.uppercased() })
check("existing question copy kept",
      OnboardingStep.startingPoint.question == "What best describes you right now?" &&
      OnboardingStep.focus.question == "What are you focused on right now?" &&
      OnboardingStep.areas.question == "Anything we should work around?")
check("every step has a short question", steps.allSatisfy { !$0.question.isEmpty && $0.question.count <= 40 })
check("questions end with a question mark", steps.allSatisfy { $0.question.hasSuffix("?") })
check("continue titles", OnboardingStep.age.continueTitle == "Continue" &&
      OnboardingStep.areas.continueTitle == "Continue" &&
      OnboardingStep.avoid.continueTitle == "Finish Setup")

if failures > 0 {
    print("FAILED: \(failures)")
    exit(1)
}
print("ALL PASSED")
