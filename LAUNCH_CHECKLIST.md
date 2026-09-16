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
      (AIBackendConfiguration), keep localhost fallbacks for dev; build 2
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
