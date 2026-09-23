# LAUNCH_CHECKLIST.md — path to TestFlight and beyond (2026-09-16)

Supersedes WEEK_PLAN.md. Statuses are honest as of writing. Owner in [brackets].

## Phase A — Lokt on YOUR phone via TestFlight (today, ~30 min)
- [ ] [Barron] Xcode: target → Signing & Capabilities → Team = paid
      "Barron Neumann" team (not Personal Team)
- [ ] [Barron] Destination "Any iOS Device (arm64)" → Product → Archive →
      Distribute App → App Store Connect → Upload (encryption: exempt/
      standard HTTPS only — also answer the "Missing Compliance" flag in
      the TestFlight tab if it appears)
- [ ] [Barron] App Store Connect → TestFlight → Internal Testing → group →
      add yourself → install via the TestFlight app on iPhone
- [ ] [Barron] Hand-test on the TestFlight build: the logger input feel
      (one-tap focus, select-on-focus, Next auto-advance), quit/resume an
      in-progress workout, the M4 check-in → Apply nudge, Add Exercise
      mid-workout, edit a RECENT session, tab reset after 5 min away.
      (The whole six-task wave + M4 have never been human-verified.)

## Phase B — the friends build (before ANY external invite)
- [ ] [Barron] Railway deploy per backend/DEPLOY.md (~10 min): rotated key
      (done 2026-09-07) + APP_TOKEN into Railway variables, get https URL
- [ ] [Claude] Verify deployed gates (401/400/429 probes) against the URL
- [ ] [Claude] Flip the app's default backend URL to the Railway address
      (AIBackendConfiguration); TestFlight has no editable URL or local
      fallback; build 2
- [ ] [Barron] Upload build 2 → TestFlight → External group "Friends" →
      Test Information (beta description + feedback email) → Beta App
      Review (~1 day) → enable public link → text 2–3 friends
- [ ] [Barron] Collect confusions verbatim; watch OpenAI usage dashboard;
      check-in answer rate (adaptationMetricsV1) = the M5 experiment

## Phase C — code polish (Claude/agents; can ride build 2 or 3)
- [ ] e1RM honesty: numeric post-check server-side (prompting alone failed
      twice — persona reports 2026-08-31 and 2026-09-01)
- [ ] False-premise prose opener still flatters before correcting (cosmetic;
      the "Actual changes:" diff line is already accurate)
- [ ] Time-budget titles inside the 25% accept band still claim the target
      ("30-Minute" at 32.3 min) — retitle threshold or copy tweak
- [ ] Dataset dedup: 33 grandfathered duplicate entries (pending task chip;
      lint baseline shrinks to zero with it)
- [ ] Store-listing screenshot set: an agent died mid-run 2026-09-09 with
      raw captures done, compositor unwritten — resume for Phase D, not
      needed for TestFlight

## Look v2 rollout — whole app (Barron, 2026-09-23: "make the entire app look better, not just the few pages")
Done: tokens+buttons (d1f1425), Home (fa5664f), Logger (5a5eef2), Coach (6aedcf1). Sequential agents, one commit each, then build 4:
- [ ] A. Build-3 feedback: remove Home START pill; keyboard dismissal audit (number pads, composer, tap-outside)
- [ ] B. Analytics: concept board (glowing headline tiles, progression line with accent fill, PR list, muscle-split donut) + per-chart controls (exercise picker, metric e1RM/top set/volume, window 7d/30d/90d/all) using the EXISTING charts
- [ ] C. Workout tab: concept "Workouts — rotation groups" board (count header, group headers with "B is next" chip, exercise-preview line, chips, ghost START on cards / gradient START on the next one, GENERATE WORKOUT pill)
- [ ] D. Exercise detail: muscle chips, BEST/E1RM/LAST tiles, numbered FORM CUES with accent circles, collapsible sections, ASK LOKT capsule
- [ ] E. Session check-in sheet: handle, Easy/Right/Hard tiles, ANYTHING HURT tiles, NEXT SESSION card with glow, APPLY TO ROUTINE pill, Not now ghost
- [ ] F. Onboarding: segmented progress bar, big option tiles with check, tap-to-advance
- [ ] G. Consistency pass, no concept board: Settings, routine editor/CreateRoutineView, SessionEditView, Add Exercise picker/library, Generate Workout + photo/voice import — same vocabulary (glassCard, micro labels, chips, capsule fields, ghost pills, one gradient pill)
- [ ] Build 4 → TestFlight; then Barron pushes (TRUST_PROXY=1 first) so Railway gets multi-draft + hardening

## Phase C+ — polish surfaced by the 2026-09-23 agent chain (Claude, small)
- [ ] Home START pill truncates long AI routine names ("START 45-MINUTE DUMBBELL PUSH DAY (HIP-…") — clamp to a short name or fall back to "START NEXT WORKOUT"
- [ ] Home hero card shows a tall empty gap when the week has no volume (chip hidden) — tighten spacing in the empty case
- [ ] `AnalyticsModels.buildHeadline` still uses inclusive `DateInterval.contains` (a Monday-00:00 session counts in two weeks); HomeInsights already uses half-open — align
- [ ] Coach multi-draft: widen the catalog subset for multi-day asks (a few names came back catalogMatch:false on a 3-day plan; app matcher still resolved them)
- [ ] SessionEditView lists exercises in routine order, not the recorded `exerciseOrder`
- [ ] Glow clipping: a gradient pill inside a glassCard (check-in sheet, Home empty state) loses ~2pt of glow to the card clip — eyeball, then pad or un-clip

## Phase D — post-friends milestones (decided, parked)
- [ ] Accounts (approved 2026-09-09, MONETIZATION.md): OPTIONAL Sign in with
      Apple only, in-app deletion, backend user store + sync. Milestone-sized.
- [ ] Paywall: StoreKit 2 sub ~$4.99/mo, free tier caps (3 gens + 15 coach
      msgs/mo), entitlement via appAccountToken (MONETIZATION.md)
- [ ] App Store submission: support URL (GitHub Pages showcase), screenshots
      (resume Phase C agent), privacy labels (change when accounts land),
      App Review notes, manual release (already selected)
- [ ] M1b: 17 direct store-key accesses remain (checks.sh tracker) — burn
      down opportunistically

## Standing facts
- Backend runs locally on :8787 (token-locked since 2026-09-07 key rotation);
  friends' AI is DEAD until Phase B completes.
- Icon: kettlebell-lock v2 shipped (66c8bcc). Store copy drafted (no em
  dashes) in the 2026-09-09 chat; "no sign-up required" phrasing survives
  the accounts decision.
- Harness gates every commit; dashboard: ./harness/dashboard.sh --open
- Repo is local-only (~60 commits ahead of origin); pushing publishes the
  public Pages repo — decide deliberately.
