// Logic check: timed tab-root reset.
// - TabResetPolicy.shouldReset: left-at + now -> reset? with injected dates;
//   the 5-minute threshold boundary; Coach and active-workout exemptions;
//   clock-skew safety.
// - CoachRouter integration: selectedTab transitions record left-at stamps and
//   bump the entered tab's reset epoch only on stale re-entry, via the
//   injectable `now`/`defaults` seams. Coach epoch never moves.
// Compiles against the REAL CoachRouter/Models sources.
import Foundation

// MARK: - Check plumbing

var failures = 0
func check(_ name: String, _ condition: Bool) {
    if condition {
        print("  PASS  \(name)")
    } else {
        print("  FAIL  \(name)")
        failures += 1
    }
}

// MARK: - Fixed dates

let iso = ISO8601DateFormatter()
iso.timeZone = TimeZone(identifier: "UTC")
let t0 = iso.date(from: "2026-08-30T12:00:00Z")!
func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

// MARK: - Constants

print("Constants:")
check("staleAfterSeconds is 5 minutes", TabResetPolicy.staleAfterSeconds == 300)
check("active-workout key is activeWorkoutV1", TabResetPolicy.activeWorkoutKey == "activeWorkoutV1")

// MARK: - Pure decision logic

print("Pure policy — never-left / fresh launch:")
check("home never left -> no reset",
      !TabResetPolicy.shouldReset(entering: .home, leftAt: nil, now: t0, hasActiveWorkout: false))
check("workout never left -> no reset",
      !TabResetPolicy.shouldReset(entering: .workout, leftAt: nil, now: t0, hasActiveWorkout: false))
check("coach never left -> no reset",
      !TabResetPolicy.shouldReset(entering: .coach, leftAt: nil, now: t0, hasActiveWorkout: false))

print("Pure policy — threshold boundary (home):")
check("left 1s ago -> preserve",
      !TabResetPolicy.shouldReset(entering: .home, leftAt: at(-1), now: t0, hasActiveWorkout: false))
check("left 4m59s ago -> preserve (accidental switch)",
      !TabResetPolicy.shouldReset(entering: .home, leftAt: at(-299), now: t0, hasActiveWorkout: false))
check("left exactly 5m ago -> preserve (strictly more than)",
      !TabResetPolicy.shouldReset(entering: .home, leftAt: at(-300), now: t0, hasActiveWorkout: false))
check("left 5m01s ago -> reset",
      TabResetPolicy.shouldReset(entering: .home, leftAt: at(-301), now: t0, hasActiveWorkout: false))
check("left 6m ago -> reset",
      TabResetPolicy.shouldReset(entering: .home, leftAt: at(-360), now: t0, hasActiveWorkout: false))
check("left overnight (9h, incl. backgrounded time) -> reset",
      TabResetPolicy.shouldReset(entering: .home, leftAt: at(-9 * 3600), now: t0, hasActiveWorkout: false))
check("clock moved backwards (leftAt in the future) -> preserve, no crash",
      !TabResetPolicy.shouldReset(entering: .home, leftAt: at(60), now: t0, hasActiveWorkout: false))

print("Pure policy — workout tab & active-workout exemption:")
check("workout stale, no active workout -> reset",
      TabResetPolicy.shouldReset(entering: .workout, leftAt: at(-360), now: t0, hasActiveWorkout: false))
check("workout stale, ACTIVE workout -> preserve (exempt)",
      !TabResetPolicy.shouldReset(entering: .workout, leftAt: at(-360), now: t0, hasActiveWorkout: true))
check("workout stale by hours, ACTIVE workout -> still preserve",
      !TabResetPolicy.shouldReset(entering: .workout, leftAt: at(-4 * 3600), now: t0, hasActiveWorkout: true))
check("workout recent, active workout -> preserve",
      !TabResetPolicy.shouldReset(entering: .workout, leftAt: at(-30), now: t0, hasActiveWorkout: true))
check("active workout does NOT shield home",
      TabResetPolicy.shouldReset(entering: .home, leftAt: at(-360), now: t0, hasActiveWorkout: true))

print("Pure policy — coach exemption:")
check("coach stale (1h) -> preserve (chat survives)",
      !TabResetPolicy.shouldReset(entering: .coach, leftAt: at(-3600), now: t0, hasActiveWorkout: false))
check("coach stale, active workout -> preserve",
      !TabResetPolicy.shouldReset(entering: .coach, leftAt: at(-3600), now: t0, hasActiveWorkout: true))
check("coach stale by days -> preserve",
      !TabResetPolicy.shouldReset(entering: .coach, leftAt: at(-3 * 86400), now: t0, hasActiveWorkout: false))

// MARK: - CoachRouter integration (injected clock + defaults)

let suiteName = "tab-reset-logic-check"
func freshDefaults() -> UserDefaults {
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}

func makeRouter(now: Date) -> (CoachRouter, (TimeInterval) -> Void) {
    let router = CoachRouter()
    var clock = now
    router.now = { clock }
    router.defaults = freshDefaults()
    return (router, { clock = clock.addingTimeInterval($0) })
}

print("Router — quick flip preserves:")
do {
    let (router, advance) = makeRouter(now: t0)
    router.selectedTab = .workout          // leave home at t0
    advance(60)
    router.selectedTab = .home             // back after 1 min
    check("epochs untouched after 1-min round trip",
          router.resetEpoch(for: .home) == 0 && router.resetEpoch(for: .workout) == 0)
}

print("Router — stale re-entry resets:")
do {
    let (router, advance) = makeRouter(now: t0)
    router.selectedTab = .workout          // leave home at t0
    advance(301)
    router.selectedTab = .home             // back after 5m01s
    check("home epoch bumped once", router.resetEpoch(for: .home) == 1)
    check("workout epoch untouched (no stamp existed at its first entry)",
          router.resetEpoch(for: .workout) == 0)
    advance(400)
    router.selectedTab = .workout          // workout left 400s ago -> stale
    check("workout epoch bumped on its own stale re-entry",
          router.resetEpoch(for: .workout) == 1)
    advance(301)
    router.selectedTab = .home
    check("epochs are monotonic across repeated stale re-entries",
          router.resetEpoch(for: .home) == 2)
}

print("Router — re-entry re-arms the stamp:")
do {
    let (router, advance) = makeRouter(now: t0)
    router.selectedTab = .workout          // leave home at t0
    advance(301)
    router.selectedTab = .home             // stale -> epoch 1
    advance(10)
    router.selectedTab = .workout          // leave home again at t0+311
    advance(60)
    router.selectedTab = .home             // back after only 1 min
    check("fresh left-at stamp wins over the old one", router.resetEpoch(for: .home) == 1)
}

print("Router — active-workout exemption via defaults key presence:")
do {
    let (router, advance) = makeRouter(now: t0)
    router.defaults.set("anything", forKey: TabResetPolicy.activeWorkoutKey)
    router.selectedTab = .workout          // leave home at t0
    advance(3600)
    router.selectedTab = .home             // home stale (1h) -> resets even mid-workout
    advance(3600)
    router.selectedTab = .workout          // workout left 1h ago BUT active -> preserved
    check("workout never reset while key present", router.resetEpoch(for: .workout) == 0)
    check("home still reset while key present", router.resetEpoch(for: .home) == 1)
    router.defaults.removeObject(forKey: TabResetPolicy.activeWorkoutKey)
    advance(10)
    router.selectedTab = .home             // leave workout again
    advance(301)
    router.selectedTab = .workout          // key gone -> normal rule applies again
    check("workout resets again once key removed", router.resetEpoch(for: .workout) == 1)
}

print("Router — coach exemption end-to-end:")
do {
    let (router, advance) = makeRouter(now: t0)
    router.openPlanning()                  // -> coach
    advance(30)
    router.selectedTab = .home             // leave coach
    advance(20 * 60)                       // away 20 minutes
    router.selectedTab = .coach
    check("coach epoch never bumped", router.resetEpoch(for: .coach) == 0)
    check("openPlanning switched to coach", router.selectedTab == .coach)
}

print("Router — programmatic coach routing records departures:")
do {
    let (router, advance) = makeRouter(now: t0)
    let routine = Routine(name: "Push Day", exercises: ["Bench Press"])
    router.openActiveWorkout(routine: routine, nextExercise: "Bench Press")
    check("openActiveWorkout switched to coach", router.selectedTab == .coach)
    advance(301)
    router.selectedTab = .home             // home was left at t0 via the routing
    check("departure via programmatic routing still stamps left-at",
          router.resetEpoch(for: .home) == 1)
}

print("Router — no-op reselection:")
do {
    let (router, advance) = makeRouter(now: t0)
    router.selectedTab = .workout          // leave home at t0
    advance(301)
    router.selectedTab = .workout          // same value: must be a pure no-op
    advance(10)
    router.selectedTab = .home             // real departure from workout at t0+311
    check("stale home still resets after a workout re-tap",
          router.resetEpoch(for: .home) == 1)
    advance(299)
    // Workout was truly left 299s ago -> preserve. Had the same-value write at
    // t0+301 (wrongly) stamped a departure, this delta would read 309s and bump.
    router.selectedTab = .workout
    check("re-selecting the current tab did not stamp a phantom departure",
          router.resetEpoch(for: .workout) == 0)
}

// MARK: - Verdict

if failures == 0 {
    print("ALL CHECKS PASSED")
    exit(0)
} else {
    print("\(failures) CHECK(S) FAILED")
    exit(1)
}
