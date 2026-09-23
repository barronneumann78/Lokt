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
- **User memory** (`UserMemoryStore.swift`): tiered digest of the raw history
  (≤14d detailed / 15–90d weekly / lifetime monthly+facts, hard 6KB cap) sent
  with every coach/generator call. Pure function of raw data — never let it
  become a second source of truth; raw data is never compacted or deleted.
- **Coach seams** (in `CoachView.swift`): `savedDraftIDs` (one-shot save),
  `savedRoutineIDsByDraft` (edit-in-place lineage; backend returns
  `editedRoutineID`), `SendMorphRender` (iMessage send morph). Touch carefully.
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
  coach/chat (accepts `savedRoutines` + `memory` + `checkInNote`, returns `editedRoutineID`),
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
gradients, `.shadow(`, glassmorphism, `Color(red:...)` literals outside
Theme.swift. Rules: volt ≤1–2×/screen (chrome; data encoding exempt),
near-black labels on accent fills, `.monospacedDigit()` on every numeral, one
hero number per screen, no gray explainer captions — labels carry the meaning.

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
