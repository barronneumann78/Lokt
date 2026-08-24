import Foundation
import Combine

/// Progressive-disclosure state for the two small icon buttons on
/// creation/review exercise cards: ask-coach (`questionmark.bubble`) and
/// exercise-profile (`info.circle`).
///
/// While a button is *undiscovered*, surfaces render it with a tiny gray text
/// label beside the glyph, and the first review screen shows a one-time nudge
/// line. Everything fades permanently as experience accumulates: a user counts
/// as experienced once they have enough completed sessions, and a button counts
/// as discovered once it has actually been used a couple of times. Discovery is
/// shared across surfaces — a button discovered anywhere is discovered
/// everywhere.
///
/// Persistence uses its own `UserDefaults` keys (never `routines` /
/// `workoutSessions`). The completed-session count is read by callers from the
/// injected `WorkoutStore`; callers with no reachable store pass `nil` and the
/// rule fails open to "experienced" (no hint). Nothing functional is gated
/// here — the buttons behave identically labeled or bare.
///
/// Foundation + Combine only (no SwiftUI) so the threshold state machine can be
/// compiled into a standalone harness.
final class DiscoveryHints: ObservableObject {

    static let shared = DiscoveryHints()

    // Own additive keys. Deleting them resets discovery (hints come back).
    static let askUsesKey = "discoveryAskCoachUses"
    static let infoUsesKey = "discoveryExerciseInfoUses"
    static let nudgeSeenKey = "discoveryReviewNudgeSeen"

    /// At this many completed sessions the user is experienced: every hint
    /// stops, used or not.
    static let experiencedSessionCount = 8
    /// A button used this many times is discovered; its label stops.
    static let discoveredUseCount = 2

    @Published private(set) var askUses: Int
    @Published private(set) var infoUses: Int
    @Published private(set) var nudgeSeen: Bool

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        askUses = defaults.integer(forKey: Self.askUsesKey)
        infoUses = defaults.integer(forKey: Self.infoUsesKey)
        nudgeSeen = defaults.bool(forKey: Self.nudgeSeenKey)
    }

    // MARK: - Rule

    /// The whole state machine: hint while the user is new AND that button is
    /// still unused. Both inputs only ever grow, so once this turns false for
    /// a button it stays false. `nil` session count (no reachable store) fails
    /// open to no hint rather than crashing or over-hinting.
    static func isUndiscovered(sessionCount: Int?, uses: Int) -> Bool {
        guard let sessionCount else { return false }
        return sessionCount < experiencedSessionCount && uses < discoveredUseCount
    }

    func showAskHint(sessionCount: Int?) -> Bool {
        Self.isUndiscovered(sessionCount: sessionCount, uses: askUses)
    }

    func showInfoHint(sessionCount: Int?) -> Bool {
        Self.isUndiscovered(sessionCount: sessionCount, uses: infoUses)
    }

    /// One-time nudge line above a review exercise list: offered only while
    /// something is still undiscovered and only until `markNudgeSeen()`.
    func shouldOfferNudge(sessionCount: Int?) -> Bool {
        !nudgeSeen && (showAskHint(sessionCount: sessionCount) || showInfoHint(sessionCount: sessionCount))
    }

    /// Total button uses. Review screens watch this to auto-dismiss the nudge
    /// line on the first real interaction.
    var interactionCount: Int { askUses + infoUses }

    // MARK: - Events

    func recordAskUse() {
        askUses += 1
        defaults.set(askUses, forKey: Self.askUsesKey)
    }

    func recordInfoUse() {
        infoUses += 1
        defaults.set(infoUses, forKey: Self.infoUsesKey)
    }

    func markNudgeSeen() {
        guard !nudgeSeen else { return }
        nudgeSeen = true
        defaults.set(true, forKey: Self.nudgeSeenKey)
    }
}
