# Persona focus group — synthetic user research

Five synthetic users with different workout goals run real journeys against the
real backend, then complain — in character, with evidence — to the developer.
**Complaints are the product**: qualitative leads pointing at where the AI coach
fails real constraints (injuries, time caps, experience level, taste).

## What a sweep does

Per persona (all requests mirror the APP's exact payload shapes — preferences
from the quiz, `UserMemoryStore`-shaped memory digests):

1. **generate** — initial workout from the persona's own prompt + saved prefs
2. **revise** — an in-character edit complaint ("that pinched my shoulder")
3. **coach** — a question or second edit against the saved routine
   (3b. **multi** — only for personas with a `multiDraftMessage`: one message
   asking for more than one workout; asserts 2–5 distinct complete drafts in
   `routines` with `routines[0]` equal to `routine`, in `steps[].checks`)
4. **voice** — one rambling persona-phrased transcript through voice parse
5. **followup** — three simulated weeks later, an evolving memory digest
   (check-ins + pain notes generated per temperament) rides along and the coach
   is asked what to do next — this is the M4 adaptation-loop probe
6. **checkin** — the M4 loop itself: the persona's last simulated session
   supplies an end-of-workout check-in (same deterministic stream as the
   digest) and `/api/ai/workout-nudge` is called with the revised routine +
   last logged numbers. Clean outcomes expect a constrained nudge (verbatim
   echo, sane deltas — asserted in `steps[].checks`); pain reporters
   (painRate ≥ 0.5) MUST get the 422 `safety:"pain_check_in"` refusal, then
   the runner mirrors the app's coach handoff (`checkin_coach` step) with the
   check-in note leading

Then each persona reviews its own journey log and files complaints + likes
(one gpt-4.1-mini call, direct to OpenAI — NOT through the backend, so the
research tooling never pollutes the system under test), and one final mini
call triages everything into a ranked, deduped issue list.

## Run it

```bash
# backend must be running on :8787 (cd backend && npm start)
node --env-file=backend/.env harness/personas/run-personas.mjs
```

The `--env-file` gives the process `OPENAI_API_KEY` (complaint/triage calls)
and `APP_TOKEN` (x-app-token header) without any file ever being read or
printed by the tooling. Flags:

- `--dry-run` — build every payload including memory digests, zero network
- `--personas marcus-shoulder-45,frank-powerlifter` — subset
- `--skip-complaints` — journeys only (no direct OpenAI calls)
- `--base URL` — non-default backend

Outputs land in `runs/<stamp>/` (**gitignored** — journey logs are large):
`<id>.journey.json` (every request/response pair), `<id>.complaints.json`,
`triage.json`, `summary.json` (calls + measured $ spend). Human-written
reports go in `reports/YYYY-MM-DD.md` (**committed**).

## Cost & pacing

A full 5-persona sweep ≈ 31 backend calls (gpt-4.1 + one mini voice-parse per
persona, incl. the M4 check-in step) + 6 direct mini calls ≈
**$0.30–0.50, ~15 minutes**. The runner
prices the backend's `[usage]` log lines (`/tmp/lokt-backend.log`) and its own
direct-call usage, and prints measured spend. Calls are spaced ≥2.1 s with 429
`retryAfter` handling so a sweep never trips the backend's 40/600 s rate limit
out from under the real phone. Hard guard at 45 backend calls per run.

## Adding a persona

Drop a `<id>.json` next to the runner (see any existing file for the shape):

- `preferences` — exactly what the app's quiz saves (`AIUserPreferencesPayload`)
- `checkInTemperament` — weighted check-in outcomes, `painRate`, `painNotes`,
  optional `missedSessionsPerWeek`; this drives the simulated history
- `history.liftPool` — plausible lifts w/ weekly progression for the digest
- `journey` — five in-character texts: `initialPrompt`, `editPrompt`,
  `coachMessage`, `followUpMessage`, `voiceTranscript`; optional
  `painCoachMessage` and `multiDraftMessage` (adds the `multi` step, +1 call)

Keep the roster diverse in goals AND temperament — at least one persona should
persistently report pain / "too hard" (adaptation-loop fodder), one should
under-report ("too easy"), one should be a total beginner.

## Triage discipline

**Complaints are leads, not verdicts.** Before filing engineering work:

1. Open the journey log and verify the cited evidence actually shows the issue
   (the model can misquote or dramatize — personas are unreliable narrators by
   design).
2. Split honestly: **CONFIRMED** (the response text demonstrably does what the
   complaint says — violates a stated constraint, math/consistency error,
   contradicts the memory it was sent) vs **PERSONA-OPINION** (taste,
   temperament, or an expectation the product never promised).
3. Only CONFIRMED items become work items; PERSONA-OPINION items are signal
   about positioning/tone, batched and revisited when multiple personas agree.
4. Likes are signal too — do not "fix" what every persona praised.

## Guardrails

- Synthetic data only — never feed a real user's memory digest or routines in.
- Never read or print `backend/.env`; the runner scans every file it writes
  and aborts on any credential material.
- Don't point a sweep at production with a user actively on their phone —
  shared rate-limit window.
