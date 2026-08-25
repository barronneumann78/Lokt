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
  --set "OPENAI_TRANSCRIBE_MODEL=gpt-4o-mini-transcribe"
```

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
  OPENAI_TRANSCRIBE_MODEL=gpt-4o-mini-transcribe
fly deploy
```

URL: `https://<app-name>.fly.dev`. Same smoke test as step 4.

## 6. Point the app at it

1. In the app: **Settings → AI Backend** → paste the full https URL
   (e.g. `https://lokt-backend-production.up.railway.app`). When a non-local
   URL is set, the app talks only to it — no localhost fallback probing.
2. In Xcode: copy `LockIn Set Tracker/AIBackendSecrets.swift.example` to
   `AIBackendSecrets.swift` (if not already there) and set:
   `static let appToken: String? = "...your token..."`.
   The file is gitignored; a shipped app token is abuse-gating, not a true
   secret — rotate it if it leaks.
3. Rebuild the app onto your phone. Generate a workout to confirm end to end.

To go back to local dev: Settings → AI Backend → **Reset to Local Default**
(the token header is ignored by a local server started without `APP_TOKEN`).

## Knobs (already defaulted, change only if needed)

- `RATE_LIMIT_MAX` / `RATE_LIMIT_WINDOW_SEC` — per token+IP sliding window,
  default 40 requests / 600s. `RATE_LIMIT_MAX=0` disables.
- `MAX_BODY_BYTES` — POST body cap, default ~36MB (sized for photo/voice
  base64 payloads).

If the token ever leaks (or a TestFlight friend goes wild): set a new
`APP_TOKEN` on the host, update `AIBackendSecrets.swift`, rebuild.
