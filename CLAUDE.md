# CLAUDE.md — Lokt / LockIn Set Tracker

Context for Claude Code working in this repo. Read this first, then `BUILD_PLAN.md`
for what we're building and why.

## What this is

**Lokt** (folder/project name "LockIn Set Tracker", app display name `Lokt`) is an
AI workout-coach iOS app. The user describes, speaks, or photographs a workout in
plain language; the app turns it into a **structured, editable routine draft** they
review before it's saved, then logs the session. There's also a coach chat.

We are mid-way through repositioning it around a sharper thesis (see `BUILD_PLAN.md`
and the design spine): the differentiator is **confirmation + ownership + an
adaptation loop**, not content or price. The one feature that matters most and does
not exist yet is the post-session adaptation loop (M4).

## Stack & layout

- **iOS app** — SwiftUI, iOS deployment target 18.5, Swift 5. ~15k lines.
  - Source: `LockIn Set Tracker/` (all `.swift`, plus `exercises.csv/json`, `ExerciseGIFs/`).
  - Xcode project: `LockIn Set Tracker.xcodeproj`. **Uses Xcode 16 synchronized
    folder groups** (`PBXFileSystemSynchronizedRootGroup`) — new `.swift` files added
    to the folder are picked up by the target automatically. Do NOT hand-edit
    `project.pbxproj` to register files.
  - Scheme: `LockIn Set Tracker`. Bundle IDs: `LockIn.LockIn-Set-Tracker`.
- **Backend** — `backend/server.mjs`, a single-file Node HTTP server (no framework)
  that proxies OpenAI. Holds the OpenAI key server-side.
- Tests: `LockIn Set TrackerTests/` and `...UITests/` exist but are **empty stubs**.

## Build & run

```bash
# Build the app (from repo root)
xcodebuild -scheme "LockIn Set Tracker" \
  -project "LockIn Set Tracker.xcodeproj" \
  -destination 'platform=iOS Simulator,name=iPhone 16' build

# Run the AI backend (needed for any AI feature)
cd backend
cp .env.example .env         # then put a real OPENAI_API_KEY in .env
npm start                    # node --env-file=.env server.mjs, listens on PORT (default 8787)
```

Prefer running `xcodebuild` to catch compile errors after Swift changes — this is
the main reason we moved to Claude Code. Fix against the real compiler, don't guess.

## Architecture notes

- **Persistence is `UserDefaults`-based** and, historically, scattered: `[Routine]`
  and `[WorkoutSession]` are JSON-encoded under the keys `"routines"` and
  `"workoutSessions"`, read/written directly from ~10 files.
  - **`WorkoutStore.swift` (M1, done) is the intended single source of truth.** It
    owns `routines` + `sessions`, reads/writes those same keys/encoding (so old data
    and not-yet-migrated views still work), and is injected at the app root as an
    `@EnvironmentObject`. **Migrating the remaining direct call sites onto it is
    M1b and NOT done yet** — see the list in `BUILD_PLAN.md`.
  - Do not introduce a second persistence path. Route new reads/writes through
    `WorkoutStore`.
- **Models** (`Models.swift`): `Routine`, `WorkoutSession` (`logs: [String:[WorkoutSet]]`
  keyed by exercise name), `WorkoutSet{weight,reps}` (both `String`), plus the
  adaptation types added in M1: `CheckInOutcome`, `SessionCheckIn`,
  `ExerciseProgressionState`. `Routine.progression` and `WorkoutSession.checkIn` are
  **optional** — keep new persisted fields optional so old saved data still decodes.
- **Backend endpoints** (all `POST` unless noted; see `server.mjs`):
  - `/api/ai/workout-generator`, `/api/ai/workout-addon`
  - `/api/ai/workout-generator/revise` ← reuse this for the M4 adaptation nudge
  - `/api/ai/photo-to-workout/extract`, `/api/ai/workout-import/revise`
  - `/api/ai/coach/chat`, `/api/ai/exercise-swap/suggest`, `/api/ai/exercise-coach/answer`
  - `/api/ai/exercise-coach/explain` (mode `"cues"` → 3 form cues; mode `"simple"` → plain-language explanation)
  - `/api/ai/voice-to-workout/transcribe`
  - `GET /health`
  - Responses use OpenAI's Responses API with **strict JSON schemas** — keep new
    outputs schema-constrained, don't parse freeform text.
- **App→backend base URL is hardcoded to localhost** (`AIWorkoutGeneratorService.swift`:
  default `http://127.0.0.1:8788`, fallbacks `:8787` / `localhost`). There is no
  production backend. Nothing AI works off the dev machine until this is hosted.

## Conventions & guardrails

- Keep the **review-before-save** invariant: AI output never silently becomes a
  saved routine; the user confirms first.
- **No secrets in the app.** The OpenAI key lives only in `backend/.env` (gitignored).
  Don't add keys to Swift or commit `.env`.
- New persisted model fields must be **optional / defaulted** for backward
  compatibility with existing `UserDefaults` blobs.
- Large view files already mix view + logic + persistence (e.g. `WorkoutLoggerView`
  ~1.3k lines). When touching them, pull logic toward services/`WorkoutStore` rather
  than adding more inline persistence.

## Current state

- M1 (persistence foundation) **done**: `WorkoutStore.swift` added; adaptation model
  fields added; store injected at app root. Not yet built against Xcode on this
  machine — **build once and fix any compile errors first.** Most likely nit: if
  strict concurrency flags `@StateObject private var store = WorkoutStore()` (the
  store is `@MainActor`), removing `@MainActor` from the class is the safe fix.
- Everything else in `BUILD_PLAN.md` is pending. Next up: M1b (migrate call sites),
  then M3/M4.

## Housekeeping

- Git history has a pre-work snapshot commit `377dd06`. The M1 changes may be
  uncommitted (they were made in an environment where git couldn't write a lock) —
  check `git status` and commit them.
