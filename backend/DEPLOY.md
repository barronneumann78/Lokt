# Deploying the Lokt AI backend

Goal: get `server.mjs` onto a cloud host with an https URL so the app works
away from your Mac (your iPhone now, TestFlight friends later). Everything is
CLI-deployed from this folder — no GitHub push needed. Budget: ~10 minutes.

**Recommended host: Railway.** Alternative: Fly.io (step 5). Both use the
`Dockerfile` in this folder automatically.

## 1. Rotate your OpenAI key (do this first)

The old key was exposed at one point — replace it, don't reuse it.

1. Go to platform.openai.com → your profile → **API keys**.
2. **Create new secret key**, copy it somewhere safe.
3. **Revoke** the old key.
4. Update your local `backend/.env` with the new key too (the `OPENAI_API_KEY=` line).

## 2. Generate an app token

This is the shared token the app will send with every AI request, so random
internet traffic can't run up your OpenAI bill:

```bash
openssl rand -hex 24
```

Copy the output — you'll paste it twice (host secrets + the app).

## 3. Deploy to Railway

```bash
brew install railway          # or: npm install -g @railway/cli
railway login                 # opens the browser; create the account there
cd backend                    # this folder
railway init                  # create a new project (pick any name, e.g. lokt-backend)
railway up                    # builds the Dockerfile and deploys
railway domain                # generates the public https URL — copy it
```

Then set the secrets (CLI, or the Variables tab in the Railway dashboard):

```bash
railway variables \
  --set "OPENAI_API_KEY=sk-...your NEW key..." \
  --set "APP_TOKEN=...output of openssl rand..." \
  --set "OPENAI_MODEL=gpt-4.1" \
  --set "OPENAI_PHOTO_IMPORT_MODEL=gpt-4.1-mini" \
  --set "OPENAI_TRANSCRIBE_MODEL=gpt-4o-mini-transcribe" \
  --set "REQUIRE_APP_TOKEN=1" \
  --set "TRUST_PROXY=1" \
  --set "RATE_LIMIT_MAX=40" \
  --set "RATE_LIMIT_WINDOW_SEC=600" \
  --set "SHARED_RATE_LIMIT_MAX=80" \
  --set "MEDIA_RATE_LIMIT_MAX=4" \
  --set "SHARED_MEDIA_RATE_LIMIT_MAX=12" \
  --set "MAX_IN_FLIGHT=12" \
  --set "MAX_IN_FLIGHT_PER_KEY=2" \
  --set "MAX_TEXT_BODY_BYTES=1000000" \
  --set "MAX_BODY_BYTES=36000000" \
  --set "MAX_IMAGE_BYTES=5000000" \
  --set "MAX_AUDIO_BYTES=25000000" \
  --set "OPENAI_TIMEOUT_MS=60000"
```

These are deliberately modest defaults for a small friends TestFlight group:
normal use is not cramped, but one installed copy cannot burst expensive calls
forever. `TRUST_PROXY=1` is correct for Railway's public proxy; do not set it
on a server that accepts direct client traffic. The Docker image also sets
`NODE_ENV=production`, so deployment fails closed if `APP_TOKEN` is missing.

Setting variables redeploys automatically (if not: `railway up` again).

## 4. Smoke test

```bash
curl https://<your-url>/health
```

Expect `{"ok":true,"configured":true,...}`. `configured:true` means the
OpenAI key is set. Note `/health` is intentionally open — it does NOT prove
auth works. Verify auth with a validation probe (400 = passed auth and got
rejected by input validation; costs zero OpenAI tokens):

```bash
# With token → 400 "Prompt must be at least 8 characters long."
curl -X POST https://<your-url>/api/ai/workout-generator \
  -H "Content-Type: application/json" -H "x-app-token: <your token>" \
  -d '{"prompt":"hi"}'

# Without token → 401 "Missing or invalid app token."
curl -X POST https://<your-url>/api/ai/workout-generator \
  -H "Content-Type: application/json" -d '{"prompt":"hi"}'
```

## 5. Alternative: Fly.io

```bash
brew install flyctl
fly auth signup               # or: fly auth login
cd backend
fly launch --no-deploy        # accept defaults; uses the Dockerfile
# check fly.toml: internal_port should be 8787
fly secrets set OPENAI_API_KEY="sk-..." APP_TOKEN="..." \
  OPENAI_MODEL=gpt-4.1 OPENAI_PHOTO_IMPORT_MODEL=gpt-4.1-mini \
  OPENAI_TRANSCRIBE_MODEL=gpt-4o-mini-transcribe REQUIRE_APP_TOKEN=1 \
  RATE_LIMIT_MAX=40 RATE_LIMIT_WINDOW_SEC=600 SHARED_RATE_LIMIT_MAX=80 \
  MEDIA_RATE_LIMIT_MAX=4 SHARED_MEDIA_RATE_LIMIT_MAX=12 \
  MAX_IN_FLIGHT=12 MAX_IN_FLIGHT_PER_KEY=2 MAX_TEXT_BODY_BYTES=1000000 \
  MAX_BODY_BYTES=36000000 MAX_IMAGE_BYTES=5000000 MAX_AUDIO_BYTES=25000000 \
  OPENAI_TIMEOUT_MS=60000
fly deploy
```

URL: `https://<app-name>.fly.dev`. Same smoke test as step 4. Set
`TRUST_PROXY=1` only after confirming Fly supplies and overwrites
`x-forwarded-for` at its public proxy; otherwise leave it unset and accept a
coarser per-proxy IP limit.

## 6. Point the app at it

1. Confirm `AIBackendConfiguration.defaultBaseURLString` is the Railway HTTPS
   domain you intend to ship. TestFlight has no editable backend setting and
   no local fallback; changing the backend requires a new app build.
2. In Xcode: copy `LockIn Set Tracker/AIBackendSecrets.swift.example` to
   `AIBackendSecrets.swift` (if not already there) and set:
   `static let appToken: String? = "...your token..."`.
   The file is gitignored; a shipped app token is abuse-gating, not a true
   secret — rotate it if it leaks.
3. Rebuild the app onto your phone. Generate a workout to confirm end to end.

## What the backend now enforces

- Production refuses to start without `APP_TOKEN`; `/api/*` rejects a missing
  or wrong token before it parses a request or contacts OpenAI.
- Normal requests are limited per token+IP (40 per 10 minutes) and the entire
  shared token is limited to 80 requests per 10 minutes. Media imports have
  tighter per-client (4) and shared (12) ceilings in that same window.
- Only photo and voice-upload routes can use the 36MB body allowance. Other
  JSON is capped at 1MB; images must be PNG/JPEG up to 5MB and audio is capped
  at 25MB after base64 decoding. Prompt fields and model-bound objects are
  shortened, and model calls time out after 60 seconds.
- At most 12 AI requests run at once, with at most 2 for the same token+IP.
  Responses are marked `Cache-Control: no-store`.

Set a limit to `0` only for a local diagnostic session; it disables that
specific protection.

## The remaining limits of a shared app token

This is intentionally not an account system. The token is embedded in each
TestFlight build, so a determined recipient can extract it and share it. The
backend cannot tell which friend made a request, give one person a quota,
ban one person without disrupting everyone, or revoke a single installed
copy. Rotation is the emergency control: it invalidates every installed build
until you update `AIBackendSecrets.swift` and ship a new one.

The limits are in memory in one Railway process. A deploy/restart clears them,
and multiple backend instances each keep their own counters. They reduce
bursts; they are not a durable monthly dollar budget or a defense against a
coordinated group holding the shared token. The IP component is only as
trustworthy as the proxy configuration, which is why `TRUST_PROXY=1` is
explicit rather than automatic.

Before inviting friends, put the OpenAI key in a dedicated project and set a
conservative project budget/usage alert in the OpenAI dashboard. Keep an eye
on Railway logs for the server's `[usage]` lines and 429 responses. If usage
looks wrong, rotate `APP_TOKEN` immediately; if you need an immediate hard
stop, revoke the OpenAI key or take the service offline. Move to real accounts
and a server-side identity/quota store before a wider beta or any paid launch.
