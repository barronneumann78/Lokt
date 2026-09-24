# CLAUDE.md — Lokt / LockIn Set Tracker

Context for Claude Code and agents working in this repo. Read this first.
The repo has an engineering **harness** — see `harness/README.md`. Agents doing
multi-step work should follow `harness/AGENT_PLAYBOOK.md`.

## What this is

**Lokt** (folder "LockIn Set Tracker", display name `Lokt`) is an AI
workout-coach iOS app. Users generate/describe/import workouts → review a
structured draft → confirm → log sessions with checkmark-completed sets → view
analytics. A coach chat can create AND edit saved routines. `BUILD_PLAN.md`
holds the product thesis; the M4 adaptation loop is BUILT (see Architecture).
`BUILD_PLAN.md`'s milestone statuses are stale — trust this file for current state.

## Stack & layout

- **iOS app** — SwiftUI, iOS 18.5 target, Swift 5. Source in `LockIn Set Tracker/`.
  Xcode 16 synchronized folder groups: new `.swift` files are picked up
  automatically — **never hand-edit `project.pbxproj`**.
- **Backend** — `backend/server.mjs`, single-file Node HTTP server proxying
  OpenAI (Responses API, **strict JSON schemas only** — never freeform parsing).
  Key lives ONLY in `backend/.env` (gitignored). Never read/print/commit it.
  Deploy hardening: the production Docker image fails closed without
  `APP_TOKEN`, which gates `/api/*` behind `x-app-token` (401). Limits include
  per token+IP (40/600s), shared-token (80/600s), tighter media limits,
  1MB normal-body / 36MB media-body caps, and in-flight/time-out caps.
  `TRUST_PROXY=1` is required on Railway so its trusted client-IP header is
  used. These are small-TestFlight abuse gates only: the shipped token is
  shared, rotatable, and not user authentication; see `backend/DEPLOY.md`.
  `/health` stays open. Cloud deploy runbook: `backend/DEPLOY.md` (+
  `backend/Dockerfile`).
- **App-side secret** — `LockIn Set Tracker/AIBackendSecrets.swift` (gitignored,
  mirror of the `.env` pattern; copy from the committed
  `AIBackendSecrets.swift.example`) holds the optional `appToken` that
  `sendAIBackendRequest` attaches to every backend call.
- Tests: XCTest targets are stubs and are NOT built by the scheme. Logic
  verification uses compiled harness checks instead — see `harness/`.

## Build & run

```bash
harness/build.sh          # canonical build (destination pinned to OS=18.5 — required,
                          # the active Xcode also ships iOS 26.5 sims with same names)
harness/checks.sh         # fast sensors: banned patterns, dataset integrity, drift
cd backend && npm start   # AI backend on :8787 (harness/backend-check.sh to verify)
harness/backend-hardening-check.sh  # production-token/auth/rate/media/body-cap gates (throwaway instance, zero cost)
```

Always build with the real compiler after Swift changes; fix errors, don't guess.

## Architecture (current, post-refactors)

- **`WorkoutStore`** (`@EnvironmentObject`, app root): the single owner of
  `routines` + `sessions` (UserDefaults keys `"routines"`/`"workoutSessions"`).
  Screens must read and write those collections through the store; do not add
  direct UserDefaults access for these keys.
- **`ExerciseStore`** (`@EnvironmentObject`, app root): the ONE instance decoding
  the bundled `exercises.json` (1,094 exercises + merged customs).
  `harness/checks.sh` enforces exactly one `ExerciseStore()` construction.
  Fuzzy name resolution via `ExerciseNameMatcher` (subset-aware memo cache —
  see commit `3d11076` for why cache keys carry candidate-list size).
- **Models**: `WorkoutSet.completed` is optional — `nil` means completed (legacy
  data). Only `isCompleted` sets count in every metric. ALL new persisted model
  fields must be optional/defaulted (old blobs must keep decoding).
- **Exercise position**: `WorkoutSession.exerciseOrder` (optional) is the
  logger's on-screen order at finish — `logs` is a dictionary, so it is the only
  record of where an exercise sat. `ExercisePositionLogic` derives positions
  (completed sets only; legacy sessions fall back to the routine's current
  order), surfaced ONLY behind Analytics → ADVANCED (`analyticsAdvancedV1`)
  and as a " · usually 3rd, PR came 1st" suffix on the digest's `allTimePRs`
  lines (same digest shape — the backend whitelists fields).
- **User memory** (`UserMemoryStore.swift`): tiered digest of the raw history
  (≤14d detailed / 15–90d weekly / lifetime monthly+facts, hard 6KB cap) sent
  with every coach/generator call. Pure function of raw data — never let it
  become a second source of truth; raw data is never compacted or deleted.
- **Coach seams** (in `CoachView.swift`): `savedDraftIDs` (one-shot save),
  `savedRoutineIDsByDraft` (edit-in-place lineage; backend returns
  `editedRoutineID`), `SendMorphRender` (iMessage send morph). Touch carefully.
  Multi-draft (Coach tab only): `drafts` + `focusedDraftIndex` back the
  computed `currentDraft`; a reply with ≥2 drafts replaces the set, a single
  reply replaces only the focused draft; lineage/`editedRoutineID` apply to the
  first draft, the rest start fresh. Backend guards live in
  `sanitizeCoachDrafts` (cap 5, duplicate drop, planning/draft_editing only —
  the check-in safety branch stays single-draft).
- **Adaptation loop (M4)**: after a session saves, `SessionCheckInSheet` (one
  ultra-light check-in, 2 taps happy path) persists via
  `WorkoutStore.recordCheckIn`, then offers a constrained nudge from
  `/api/ai/workout-nudge` — same exercises, same order, only load/rep/set
  targets move. The explicit **Apply** tap upserts the SAME routine id;
  applied targets + a one-line why live in `ExerciseProgressionState`
  (`suggestedWeightText`/`suggestedRepText`/`nudgeNote`), surface in the
  logger's TARGET chip, and are consumed by the next check-in. Pain or
  `needsRealCheckIn` (repeated too-hard) routes to Coach via
  `CoachRouter.openActiveWorkout(checkInNote:)` instead of nudging; the server
  also refuses pain nudges (422, defense in depth). M5 funnel counters:
  UserDefaults key `adaptationMetricsV1` (`AdaptationMetrics`).
- **Backend endpoints**: workout-generator (+`/revise`, `/explain`), workout-addon,
  workout-nudge (M4: strict echo-verbatim target deltas; 422 on pain check-ins),
  coach/chat (accepts `savedRoutines` + `memory` + `checkInNote`, returns `editedRoutineID`
  and, only when the user clearly asks for more than one workout, `routines` — the
  full ordered 2–5 draft list with `routines[0]` equal to `routine`; null otherwise),
  exercise-coach/answer + `/explain` (cues|simple), photo/voice import, `GET /health`.
  Generator schema: per-exercise required `reasoning` (≤15 words) + `tip`
  (≤12 words); `summary` = one concrete sentence, filler banned.
- Drafts seed set counts at **3** (`defaultReviewSetCount`); the AI's number
  shows as a "Recommended sets: N" chip. Discovery hints (`DiscoveryHints.swift`)
  label the ask/info buttons for new users (<8 sessions, <2 uses).

## Design system — "dark athletic minimal" (volt)

All colors route through `AppTheme` tokens in `Theme.swift`. Flat #0B0B0C bg,
#141416 cards + #26262A hairlines, accent = volt #D6FF3F (user-selectable
schemes exist; volt is default). **Banned** (checks.sh enforces): blue/purple,
`AngularGradient`, glassmorphism, `Color(red:...)` literals outside Theme.swift,
and — in every file EXCEPT Theme.swift — `LinearGradient`/`RadialGradient`/
`.shadow(`. Depth is a token-layer concern: `AppTheme.primaryGradient` +
`.primaryGlow()` (the one primary pill per screen; `PrimaryButtonStyle` renders
them for accent fills), `AppTheme.cardHighlight` (1px inner top highlight inside
`glassCard()`), `.heroGlow()` (radial accent glow behind the hero number). Views
use those tokens and never write gradients or shadows themselves. Rules: volt
≤1–2×/screen (chrome; data encoding exempt), near-black labels on accent fills,
`.monospacedDigit()` on every numeral, one hero number per screen, no gray
explainer captions — labels carry the meaning.

**Concept → code (the "v2 dream app" look).** Palette untouched; depth comes
from glow and highlight only, never new colors or full-screen washes.
Phase 1 (done, global): the tokens above; `Primary/Secondary/TertiaryButtonStyle`
are all capsules and the accent-filled primary is a lime→olive (per-scheme
`AccentScheme.gradientStops` + `glowOpacity`, ice kept subtle) gradient pill
with glow; every `glassCard()` carries the highlight; `.heroGlow()` sits on
Home's week volume and the Analytics headline strip only.
Phase 2 (done, Home): `HomeView` is hero card (week volume + "+8% vs last"
chip + Mon–Sun strip, today's bar = `primaryGradient` under `.barGlow()`, the
one small-mark glow token) → SESSIONS·7D / PRs·30D / STREAK row → RECENT with
a "View Analytics ›" text link. Home has NO gradient pill: the pinned
`START <UP NEXT>` pill from `fa5664f` was removed on owner feedback (build 3
— starting a workout from Home felt wrong); the header's "Up next: X"
subtitle keeps the information without a control. All math is
`HomeInsights` (Foundation-only, logic-checked in
`harness/logic-checks/home-week-strip`): Monday-first weeks, completed-only
tonnage via `AnalyticsMath`, PRs via the Analytics day-scorecard rule, and
"up next" = least-recently-done sibling in the just-done routine's group,
else least-recently-done overall. The start plumbing stays in place unused:
`CoachRouter.requestWorkoutStart(routineID:)` (`WorkoutStartRequest`) is the
tab-reset-safe way to start a routine from another tab, and `WorkoutTabView`
consumes it through its own `requestStartWorkout` guard (replace-in-progress
prompt included) — the Workout tab stays the sole owner of the logger.
Phase 3 (done, Logger, commit `5a5eef2`): recording header (red dot under
`.recordingGlow()`, REST accent chip), 20pt exercise name + TARGET chip,
SET · PREV · LBS · REPS · check set table on elevated rows with the active
row on `activeRowTint`, pinned `COMPLETE SET` / `WRAP UP` gradient pill with
Wrap Up as a `GhostButtonStyle` beneath. Latency architecture untouched.
Phase 4 (done, Coach): `CoachView` header is "Lokt Coach" (22pt) with the
policy caption on the same row; sent messages are hairline bubbles on
`surfaceElevated` (18pt corners, 4pt tail), coach prose is plain 14pt text
with no bubble; the draft card is `glassCard()` under an `accentHairline`
border — WORKOUT DRAFT micro label + the `accentChipFill` "1 OF 2" chip and
accent/hairline dots, 18pt title, exercises • sets meta line (no minutes:
the payload has no time estimate), hairline, numbered mono rows folded to
four behind "+ N more", then the row `Save Workout` / `Update Workout`
gradient pill (swapped for the Saved capsule) beside a fixed-width Revise
ghost (`GhostButtonStyle(verticalPadding: 17)`, focuses the composer) and,
for multi replies, `Save both` / `Save all` as a ghost pill beneath; the
composer is a 50pt card-fill capsule with a 38pt `primaryGradient` send
circle. The multi-draft seams (`drafts`/`focusedDraftIndex`, lineage,
`persistDraft`) are unchanged. The v2 look is complete; further work is
polish, not phases.
Phase 5 (done, Analytics): `AnalyticsView` matches the "Progress — charts with volt depth" board — VOLUME·7D / SETS·30D / PRs·e1RM tiles (16pt `glassCard(cornerRadius:)`), the progression line over `AppTheme.chartFill` with in-card exercise / metric (e1RM · Top set · Volume) / window (7d · 30d · 90d · All) controls, a PRs·e1RM board (tap a row to drill the chart down to that lift), the muscle-split donut and distribution radar each with a 30d · 90d · All switch; every control persists through the `AnalyticsControls` `@AppStorage` keys, the math stays in `AnalyticsSnapshot` parameterized by `AnalyticsWindow`/`ProgressionMetric` (completed sets only), logic-checked in `harness/logic-checks/analytics-controls`.
Phase 6 (done, Workout tab): `WorkoutTabView` matches the "Workouts — rotation groups" board — WORKOUTS accent micro label over "5 ROUTINES · 2 GROUPS" with a 40pt hairline "+" (the manual create-routine entry), group sections (name + hairline, `accentChipFill` "<name> is next" chip, "…" rename/delete menu), routine cards (18pt name, three-exercise preview, "N exercises" + last-done chips, folder menu + "…" edit/delete at the bottom-right) where each group's next member — and the overall next when it is ungrouped — wears the compact gradient START (`PrimaryButtonStyle(isCompact:)`) and every other card a compact `GhostButtonStyle`, a quiet UNGROUPED label only once a group exists, and the pinned GENERATE WORKOUT pill (the create flow's AI path; the preset-plan entry moved into `CreateWorkoutOptionsView`). The rotation math is `WorkoutTabInsights` running `HomeInsights.nextRoutine` over one group's members (never forked), logic-checked in `harness/logic-checks/workout-rotation`.
Phase 7 (done, Exercise page): `ExerciseDetailView` matches the "Exercise — cues in drop-downs" board — quiet title bar (system back), 24pt name over muscle chips (primaries on `accentChipFill`/`accentHairline`, secondaries plain hairline, data from `ExerciseMuscleRoles`), a BEST / e1RM / LAST tile row (16pt `glassCard`, e1RM accent under `.heroGlow()`; hidden until the exercise has a completed set), then drop-down sections on 18pt cards (FORM CUES open by default with 22pt accent-outlined circle numbers, HOW TO · N, IN PLAIN WORDS with the Explain It Simply ghost inside, VARIATIONS · N, HISTORY · N sessions with per-session best sets and the "3rd in session" tag only under `analyticsAdvancedV1`) whose open state persists per app via `ExerciseDetailSection` `@AppStorage` keys, a ghost Add to Routine, and the pinned ASK LOKT composer (50pt card capsule, 38pt `primaryGradient` send circle — the screen's one gradient; Return sends). Math is `ExerciseDetailInsights` (Foundation-only, completed sets via `AnalyticsMath`, positions via `ExercisePositionLogic`), logic-checked in `harness/logic-checks/exercise-detail-stats`. The add-to-routine sheet keeps its `RoutineLibrary` paths under the same vocabulary (card rows, one gradient pill for NEW ROUTINE).
Phase 8 (done, Check-in sheet): `SessionCheckInSheet` matches the "Check-in — two taps, then a nudge" board — a `card`-colored sheet (28pt `presentationCornerRadius`, hairline `presentationBackground`, 40×4 handle, SESSION CHECK-IN micro label over the phase title, the X skip kept) with 64pt effort tiles (`Too easy` / `About right` / `Too hard` — the `CheckInOutcome.label` strings the coach note also reads, so they stay) and 52pt ANYTHING HURT? tiles (`No` / `Yes, something`; selected = `accentChipFill` + `accentHairline` + accent label, the app's chip vocabulary), the loading line in the card's footprint, then the NEXT SESSION card (`surfaceCard(cornerRadius: 18)`, `.heroGlow()` pinned top-trailing behind an empty box — no new token) whose rows print the payload verbatim — `140 → 145 lb × 6-8` from `lastWeight`/`suggestedWeightText`/`repText`, `3 → 4 sets` from `preferredSetCount`/`setCount`, never recomputed — over `overallNote` ("Sized from today's completed sets" only when the payload has none), the APPLY TO ROUTINE gradient pill and a ghost Not now; the safety branch keeps its Talk It Through with Coach pill; settled/failed wear a Saved-style capsule and a ghost Done. `recordCheckIn` → `/api/ai/workout-nudge` → explicit Apply upsert → `ExerciseProgressionState` → TARGET chip, the 422/pain routing and `adaptationMetricsV1` are untouched (`harness/logic-checks/adaptation-loop`).
Phase 9 (done, Onboarding): `OnboardingView` matches the "Onboarding — tap a tile, it slides on" board — a quiet top row (system `‹` back, one 4pt `primaryGradient` segment per step with hairline for the rest, a mono "2 / 7" counter in `textTertiary`), an accent micro label (YOUR STARTING POINT · YOUR FOCUS · WHERE YOU TRAIN · USUAL SESSION · AGE · AREAS TO WORK AROUND · ANYTHING ELSE TO AVOID) over a 30pt two-line question, and big tiles (`glassCard(cornerRadius: 20)`, 18pt padding, 17pt bold title + 13pt factual subtitle, a 26pt mark that is hairline at rest and the gradient with a near-black check when selected; selected tile = `accentChipFill` + `accentHairline`). The four single-choice steps select and slide on after 250ms over a "Tap one — it slides on" / Skip row (Skip is the existing leave-the-quiz action, never on AGE); AGE (auto-focused number pad, the requirement/range hint as one `textSecondary` line), AREAS TO WORK AROUND (multi-select, "None right now" = the empty set) and the note pin the screen's one gradient Continue / Finish Setup pill. Step order, counter, tap-vs-Continue split and the age gate are `OnboardingStep`/`OnboardingFlow` (`OnboardingFlow.swift`, Foundation-only), logic-checked in `harness/logic-checks/onboarding-flow`; `savePreferences` writes the same `aiUserPreferences` keys and values, `hasCompletedOnboarding` still gates `MainTabView`, and Settings → Retake Quiz still restarts here.

## Conventions & guardrails

- **Review-before-save invariant**: AI output never persists without an explicit
  user tap (Save/Update). Edits of saved routines replace by id, never duplicate.
- **Dataset (`exercises.json`)**: casual edits stay banned, but EXPANSION via
  the vetted process is legitimate: research the gap, author schema-complete
  entries (unique id/name, 3 house-style cues, full metadata, no `imageName` —
  the placeholder icon covers it), then keep every gate green:
  `harness/dataset-lint.py` (schema/enums/uniqueness/content floor; new
  duplicate names are banned, 29 legacy duplicate groups are grandfathered
  inside the script), the pinned entry counts in
  `harness/logic-checks/exercise-{muscle-roles,variations,name-matching}`, and
  the name-matching check proving new names don't steal existing fuzzy
  resolutions (append-only + the matcher's strict `>` keeps ties with the
  older entry; verify anyway).
- **Keyboard dismissal** (`KeyboardDismiss.swift`, owner feedback build 3):
  every screen with text inputs gets `.scrollDismissesKeyboard(.interactively)`
  on its scroll view and `.dismissKeyboardOnTap()` at its root (UIKit tap
  recognizer scoped to that screen; never swallows buttons or field taps);
  screens with a number-pad or multi-line field add `.keyboardDoneBar()`
  (one per screen — keyboard toolbar items merge up the hierarchy). The
  logger is the exception: its UIKit cells carry their own accessory toolbar
  and get drag-to-dismiss only, so COMPLETE SET keeps the focus hand-off.
- Scoped commits only (never `git add -A`; leave `.DS_Store`/xcuserstate churn).
  End commit messages with the standard Claude Co-Authored-By trailer. No push
  unless the user asks — GitHub Pages serves this repo's root on push.
- Simulator etiquette: iPhone 16 UDID `D512C8EC-0015-4890-825D-C2DB2CE5DA02`
  carries seeded demo history — PRESERVE `workoutSessions`. Do not drive the
  screen (clicks/typing/foregrounding) unless the user explicitly allows it in
  the current session; default to headless builds + desk-checks.
- FUSE filesystem gotcha: git may hit stale empty `.git/index.lock`/`HEAD.lock`
  with no live git process — safe to delete, then retry. `.fuse_hidden*` files
  are junk; never commit them.
- OpenAI calls cost real money: live-test AI endpoints with a small budget
  (≤2–3 calls) and say how many you used.
- Consistency pass (agent G, 2026-09-24): Settings, routine editing, exercise picking, AI generation, imports + small sheets restyled to the v2 vocabulary; tab bar already token-clean. Look v2 rollout complete.
