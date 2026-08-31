# Monetization plan (decided 2026-08-30)

Costs (estimated; replace with real OpenAI dashboard data after test week):
typical AI user ≈ $0.70/mo, heavy ≈ $2–4/mo. Tracker features cost $0 (on-device).

## Tiers
- **Free, unlimited, forever**: the entire tracker — unlimited routines (direct
  counter to Hevy's 4-routine cap), full analytics, library + cues, export.
  Plus an AI taste: ~3 generations + ~15 coach messages/month.
- **Pro ~$4.99/mo (~$39.99/yr)**: unlimited AI — coach, generation, voice
  import, and the M4 adaptation loop (the headline: "workouts that adjust
  themselves"). Apple Small Business Program → keep ~85%.

## Ads policy
- **v1 → ~10k users: zero ads.** The free tier is acquisition, not revenue;
  "no ads, ever, on free" is itself a marketing line. Protects the
  "Data Not Collected" privacy label (no ad SDK, no ATT prompt).
- **Rewarded refill (liked, deferred)**: when free users hit the AI cap —
  opt-in "watch a 30s ad for +1 generation". Rewarded eCPM ≈ 1–3¢/view vs
  ~1.5¢/generation ≈ break-even. Build ONLY if data shows many users capping
  without converting.
- **Native slot (at scale only)**: if Pro conversion underwhelms at 50k+ free
  users, test ONE labeled "SPONSORED" card at the bottom of Analytics. Never
  the Logger, never Coach, never disguised as a routine card. Pro removes it.

## Principles
- Never unmetered free AI (the only feature with real marginal cost).
- Price ≥3× marginal cost; revisit with real usage data.
- The upgrade pitch is the adaptation loop, not "remove ads".
