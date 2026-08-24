# CLAUDE.md — Lokt / LockIn Set Tracker

Context for Claude Code and agents working in this repo. Read this first.
The repo has an engineering **harness** — see `harness/README.md`. Agents doing
multi-step work should follow `harness/AGENT_PLAYBOOK.md`.

## What this is

**Lokt** (folder "LockIn Set Tracker", display name `Lokt`) is an AI
workout-coach iOS app. Users generate/describe/import workouts → review a
structured draft → confirm → log sessions with checkmark-completed sets → view
analytics. A coach chat can create AND edit saved routines. `BUILD_PLAN.md`
holds the product thesis (adaptation loop = M4, still pending); its milestone
statuses are stale — trust this file for current state.

## Stack & layout

- **iOS app** — SwiftUI, iOS 18.5 target, Swift 5. Source in `LockIn Set Tracker/`.
  Xcode 16 synchronized folder groups: new `.swift` files are picked up
  automatically — **never hand-edit `project.pbxproj`**.
- **Backend** — `backend/server.mjs`, single-file Node HTTP server proxying
  OpenAI (Responses API, **strict JSON schemas only** — never freeform parsing).
  Key lives ONLY in `backend/.env` (gitignored). Never read/print/commit it.
- Tests: XCTest targets are stubs and are NOT built by the scheme. Logic
  verification uses compiled harness checks instead — see `harness/`.

## Build & run

```bash
harness/build.sh          # canonical build (destination pinned to OS=18.5 — required,
                          # the active Xcode also ships iOS 26.5 sims with same names)
harness/checks.sh         # fast sensors: banned patterns, dataset integrity, drift
cd backend && npm start   # AI backend on :8787 (harness/backend-check.sh to verify)
```

Always build with the real compiler after Swift changes; fix errors, don't guess.

## Architecture (current, post-refactors)

- **`WorkoutStore`** (`@EnvironmentObject`, app root): intended single owner of
  `routines` + `sessions` (UserDefaults keys `"routines"`/`"workoutSessions"`).
  M1b migration is PARTIAL — some screens still read/write those keys directly;
  bridge with `store.reload()` before reading if staleness matters. Do not add
  new direct UserDefaults access for these keys.
- **`ExerciseStore`** (`@EnvironmentObject`, app root): the ONE instance decoding
  the bundled `exercises.json` (1,036 exercises + merged customs).
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
- **Backend endpoints**: workout-generator (+`/revise`, `/explain`), workout-addon,
  coach/chat (accepts `savedRoutines` + `memory`, returns `editedRoutineID`),
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
