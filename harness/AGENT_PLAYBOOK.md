# Agent Playbook — Lokt

Standing rules for any agent delegated work in this repo. The orchestrator may
add task-specific instructions; these apply always.

## Ground rules

1. Work in the MAIN project dir: `/Users/barronneumann/Desktop/LockIn Set Tracker`
   (branch `main`) — never in a `.claude/worktrees/` copy.
2. Read `CLAUDE.md` before touching anything.
3. **Headless by default.** No simulator driving, no screen control, no
   launching/foregrounding/booting apps or simulators — unless the user
   explicitly permitted it *in the current session*. The user verifies visuals
   in Xcode; give them a hand-check list instead.
4. Never read, print, or commit `backend/.env`. Never hand-edit `project.pbxproj`.
5. Preserve simulator data (`workoutSessions`, routines) on device
   `D512C8EC-0015-4890-825D-C2DB2CE5DA02`.
6. Live OpenAI calls: minimal budget (≤2–3), report exactly how many used.
   Leave the backend RUNNING on :8787 if you restarted it.

## Verification bar (before you claim done)

1. `harness/build.sh` exits 0 (or the equivalent pinned-destination xcodebuild).
2. `harness/checks.sh` passes.
3. New/changed pure logic gets a compiled harness check (see
   `harness/logic-checks/README.md`) — assertions against the REAL source
   files, all passing. UI changes get a written desk-check per surface.
4. Nothing in the protected seams broke (list below) — state this explicitly.

## Protected seams (check before and after)

- Review-before-save: AI drafts persist only on explicit Save/Update.
- Coach: `savedDraftIDs` / `savedRoutineIDsByDraft` / `editedRoutineID` flow /
  `SendMorphRender` animation.
- Set semantics: only `isCompleted` sets count anywhere; legacy nil = completed.
- Stores: single `ExerciseStore()` at app root; no new direct UserDefaults
  access for `"routines"`/`"workoutSessions"`.
- Design tokens: no colors outside `AppTheme`; volt scarcity; banned-list clean.
- `exerciseInsightsV1` cache, discovery-hint keys, user-memory digest shape.

## Commits

- Scoped: stage ONLY files you changed. Never `git add -A`. Leave
  `.DS_Store`/xcuserstate noise unstaged.
- Message: short imperative summary + standard Claude Co-Authored-By trailer.
- Never push. Never create PRs.
- FUSE gotcha: stale empty `.git/*.lock` with no live git process → delete, retry.

## Report format (your final message)

- What changed, per file, one line each.
- Verification evidence: build result, checks result, harness/desk-check outcomes.
- Commit hash.
- Anything left undone or risky — stated explicitly, never implied complete.
- A short hand-check list for the user (they verify in Xcode).
