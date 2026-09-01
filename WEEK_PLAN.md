# Week Plan — ship Lokt to real testing (created 2026-08-30)

STATUS (updated 2026-09-01): Day 1 done EXCEPT key rotation + Railway (user).
Phone install ✅, data export ✅, field testing ✅ (ahead of schedule — produced
the voice-import fix and the dataset/alias/AI-grounding trilogy, i.e. Day 4
polish landed early). **M4 BUILT** — end-of-workout check-in → constrained
nudge (Apply = explicit save) → next session shows targets + why; pain /
repeated too-hard routes to Coach; M5 answered-vs-skipped counters recording
locally (`adaptationMetricsV1`). Days 5–7 untouched.

Goal for the week: the app running on real phones, the AI working away from the
Mac, the M4 adaptation loop built, and 2–3 friends testing by the weekend.
Roles: **YOU** = accounts, money, testing, judgment. **CLAUDE** = all build work
via agents (per harness/AGENT_PLAYBOOK.md).

## Day 1 — off the Mac (~30 min of YOU-time)
- [ ] YOU: rotate the OpenAI key (platform.openai.com), update `backend/.env`
- [ ] YOU: `openssl rand -hex 24` → app token
- [ ] YOU: Railway deploy per `backend/DEPLOY.md` (login, init, up, domain, set 5 vars)
- [ ] CLAUDE: verify the deployed gates (401/400/429 probes) once URL exists
- [ ] YOU: URL → Settings → AI Backend; token → `AIBackendSecrets.swift`; ⌘R to
      your iPhone (free provisioning — Xcode: add Apple ID, pick personal team)
- [ ] CLAUDE (parallel): **data export** — Settings button sharing full history
      as JSON (testers' trust insurance; protects against delete-the-app data loss)

## Days 2–3 — M4: the adaptation loop (CLAUDE builds, YOU train)
- [ ] YOU: use Lokt for your real workouts; note every friction point (this is
      BUILD_PLAN's M5 experiment run on yourself — is the flow light enough?)
- [ ] CLAUDE: **M4 per BUILD_PLAN.md** — the one unbuilt thesis milestone:
      - end-of-workout check-in: ONE short screen (too easy / about right /
        too hard + "did anything hurt?") → `SessionCheckIn` via the existing
        `WorkoutStore.recordCheckIn` plumbing
      - feed check-in + exercise history into `/api/ai/workout-generator/revise`,
        constrained to load/volume nudges within the same template — not a replan
      - safety branch: repeated "too hard" or a pain flag
        (`ExerciseProgressionState.needsRealCheckIn`) triggers a real
        conversation with coach, not a silent adjustment
      - next session's logger shows the adjusted targets + one line of why
      - M5 instrumentation: count check-ins answered vs skipped (local)
- [ ] CLAUDE: fix whatever Day-1 phone testing surfaced

## Day 4 — polish, aimed by evidence
- [ ] YOU: send field notes + (optionally) Hevy screenshots for the side-by-side
- [ ] CLAUDE: fix the top friction items from YOUR notes — not speculative polish

## Day 5 — Apple Developer + TestFlight prep
- [ ] YOU: buy the Apple Developer membership ($99), create the app record in
      App Store Connect
- [ ] CLAUDE: release-build prep (version/build numbers, icons/launch screen
      check, archive instructions), privacy-label answer sheet (local-only data
      story), short tester instructions
- [ ] YOU: upload first TestFlight build (Xcode → Archive → Distribute)

## Days 6–7 — first outside testers
- [ ] YOU: invite 2–3 friends (internal TestFlight — instant, no review wait);
      tell them nothing about how it works — watch what they can't find
- [ ] YOU: collect every confusion/complaint verbatim
- [ ] CLAUDE: triage into next week's plan; check-in answer rate = the number
      that decides M5

## Standing
- Harness runs itself (pre-commit); dashboard: `./harness/dashboard.sh --open`
- Decide on repo backup (pushing publishes to the public Pages repo — a private
  mirror is the alternative)
- OpenAI spend: glance at platform.openai.com usage after friends join
