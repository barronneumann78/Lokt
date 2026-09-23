# BUILD_PLAN.md — Lokt / LockIn Set Tracker

Derived from the product design spine (`PT_App_Design_Spine.docx`). This is the
*how and in what order*; the spine is the *why*. Read `CLAUDE.md` first for repo
context.

## Thesis (don't lose this)

Free workouts and demos are everywhere; that's a commodity. The open lane is
**confirmation and ownership**: the user co-builds a plan they understand (so they
don't quit in week 3), and after each session the app **adapts** the next one
(so it feels like a coach, not a spreadsheet). The adaptation loop is the product;
a plan without it is "a PDF with a nicer screen."

## Scope decision

**Single modality first (bodyweight recommended).** The spine wants bodyweight AND
gym on day one; we deliberately narrowed to one modality to reach the adaptation
loop faster. The loop is the thesis; prove it with one exercise library, then add
the second. Do not build the gym/barbell path or the `height` intake field until
the loop works.

**Critical path to prove the thesis: M1 → M4.** M3 makes it feel like a coach;
M4 makes it be one.

---

## Milestones

### M0 — Prune scope — DONE (decision only)
Bodyweight only for now. Gym/barbell, `height`, and the photo/voice import flows are
deferred (keep the code, off the critical path).

### M1 — Persistence foundation — DONE
Single source of truth so the loop has trustworthy history.
- `WorkoutStore.swift` (new): owns `routines` + `sessions`, reads/writes the legacy
  `"routines"`/`"workoutSessions"` keys, injected at app root as `@EnvironmentObject`.
- `Models.swift`: added `CheckInOutcome`, `SessionCheckIn`, `ExerciseProgressionState`;
  added optional `Routine.progression` and `WorkoutSession.checkIn`.

### M1b — Migrate call sites onto WorkoutStore — DONE
`WorkoutStore` is the actual owner of routines and workout sessions. Creation,
library, logger, analytics, coach, adaptation, and settings flows all read and
write through it; the legacy keys remain an internal persistence detail only.

### M2 — Rebuild intake against the spine table — TODO
Rework `OnboardingView.swift` + `AIUserPreferences.swift` to exactly the intake
fields, each doing the job the spine's table specifies, nothing that doesn't change
the plan:
- Goal · training condition/experience · age · constraints(equipment/time/injuries) · current weight
- Drop `height` (bodyweight scope). Make **age** and **injury flags** first-class —
  M3 gating and the M4 safety branch depend on them.

### M3 — Plan engine with surfaced reasoning — TODO
Ownership comes from understanding each pick.
- Backend `server.mjs` `/api/ai/workout-generator`: accept the structured intake;
  apply spine §5 (condition+goal → template family → constraints filter →
  age/injury gate). Add **per-exercise `reasoning`** to the workout JSON schema
  (you already return `rationale`/`routineNotes`; make it per-exercise).
- App: turn the existing review-before-save screen into a "walk through the plan"
  flow — each exercise shows its why; user can ask "why this?" (reuse
  `ExerciseCoachService` / `/api/ai/exercise-coach/answer`) or push back before it locks.

### M4 — The adaptation loop (the actual product) — TODO
- At end of `WorkoutLoggerView`, show ONE short check-in: overall
  too-easy/about-right/too-hard + "did anything hurt?" → build a `SessionCheckIn`.
- Persist via `WorkoutStore.recordCheckIn(_:forSessionID:)` (already exists; updates
  `ExerciseProgressionState`).
- Feed check-in + that exercise's history into `/api/ai/workout-generator/revise`,
  **constrained to load/volume nudges within the same template — not a replan.**
- Safety branch (spine §6): repeated "too hard" or a pain flag
  (`ExerciseProgressionState.needsRealCheckIn`) triggers a real check-in, not a
  silent adjust — especially for age/injury-flagged users.
- Next session reflects the adjustment.

### M5 — Test the one risky assumption — TODO
The whole thesis rests on the check-in being short enough that a real beginner
answers it **every** session (spine §7, untested). Instrument answered-vs-skipped;
iterate the copy. Treat this as a product experiment, not a detail.

---

## Cross-cutting (before real users, parallel track)
- **Host the backend + set a real base URL.** `AIWorkoutGeneratorService.swift` is
  hardcoded to `127.0.0.1`; nothing AI works off the dev machine. Add an app token,
  rate limiting, and HTTPS before it's public (backend currently has none).
- **Add tests.** Targets are empty stubs. Cover the M3 gating logic and the M4
  progression/nudge math — pure logic, cheap to protect.

## Explicitly deferred
Gym modality · barbell/height mechanics · photo & voice import polish ·
exercise-swap suggestions. Kept in the codebase, none on the MVP path.
