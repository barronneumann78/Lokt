#!/bin/bash
# Hardening sensors: production token requirement, auth, per-token+IP and
# media limits, plus route-specific body caps. Boots a THROWAWAY server with
# inline test env (no .env, no OpenAI key — probes resolve at the gate or input
# validation, zero token cost). The normal :8787 dev server is untouched. See
# backend/DEPLOY.md for the deployed setup these gates protect.
set -uo pipefail
cd "$(dirname "$0")/.."
PORT=8901
BASE="http://127.0.0.1:$PORT"
TOKEN="harness-test-token"
FAIL=0

record() {
  echo "{\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"kind\":\"backend-hardening\",\"pass\":$1}" >> harness/history.jsonl
}

NODE_ENV=production OPENAI_API_KEY="dummy-key-gate-probes-only" PORT=0 node backend/server.mjs >/dev/null 2>&1 &
FAIL_CLOSED_PID=$!
sleep 0.25
if kill -0 $FAIL_CLOSED_PID 2>/dev/null; then
  kill $FAIL_CLOSED_PID 2>/dev/null
  wait $FAIL_CLOSED_PID 2>/dev/null || true
  echo "  FAIL  production refuses to start without APP_TOKEN"
  record false
  exit 1
fi
wait $FAIL_CLOSED_PID 2>/dev/null || true
echo "  PASS  production refuses to start without APP_TOKEN"

if lsof -ti tcp:$PORT >/dev/null 2>&1; then
  echo "  FAIL  port $PORT already in use — free it and rerun"
  record false
  exit 1
fi

# Dummy key: routes 500 on a missing key before validation, but every probe
# below resolves at the gate/validation layer — the key is never used.
OPENAI_API_KEY="dummy-key-gate-probes-only" \
APP_TOKEN="$TOKEN" RATE_LIMIT_MAX=6 RATE_LIMIT_WINDOW_SEC=60 \
SHARED_RATE_LIMIT_MAX=20 MEDIA_RATE_LIMIT_MAX=1 SHARED_MEDIA_RATE_LIMIT_MAX=5 \
MAX_BODY_BYTES=1000 MAX_TEXT_BODY_BYTES=200 PORT=$PORT \
  node backend/server.mjs >/dev/null 2>&1 &
SERVER_PID=$!
trap 'kill "${SERVER_PID:-}" "${SHARED_PID:-}" 2>/dev/null' EXIT

UP=0
for _ in $(seq 1 20); do
  if curl -s -m 1 -o /dev/null "$BASE/health"; then UP=1; break; fi
  sleep 0.25
done
if [ $UP -ne 1 ]; then
  echo "  FAIL  throwaway server did not come up on :$PORT"
  record false
  exit 1
fi

probe() { # probe <want_code> <label> <curl args...>
  local want="$1" label="$2"; shift 2
  local code
  code=$(curl -s -m 10 -o /dev/null -w "%{http_code}" "$@")
  if [ "$code" = "$want" ]; then echo "  PASS  $label ($code)"
  else echo "  FAIL  $label: got $code, want $want"; FAIL=1; fi
}

GEN="$BASE/api/ai/workout-generator"
JSON="Content-Type: application/json"

probe 200 "/health open without token" "$BASE/health"
probe 401 "api rejects missing token" -X POST "$GEN" -H "$JSON" -d '{"prompt":"hi"}'
probe 401 "api rejects wrong token" -X POST "$GEN" -H "$JSON" -H "x-app-token: wrong" -d '{"prompt":"hi"}'
BIG_BODY="{\"prompt\":\"$(printf 'a%.0s' $(seq 1 2000))\"}"
probe 413 "normal JSON cap rejects oversized body" -X POST "$GEN" -H "$JSON" -H "x-app-token: $TOKEN" -d "$BIG_BODY"
MEDIA="$BASE/api/ai/photo-to-workout/extract"
probe 400 "malformed media is rejected before AI" -X POST "$MEDIA" -H "$JSON" -H "x-app-token: $TOKEN" -d '{"imageBase64":"not base64","mimeType":"image/png"}'
probe 429 "media-specific limit trips" -X POST "$MEDIA" -H "$JSON" -H "x-app-token: $TOKEN" -d '{"imageBase64":"not base64","mimeType":"image/png"}'
probe 400 "untrusted forwarded IP stays in same bucket (1)" -X POST "$GEN" -H "$JSON" -H "x-app-token: $TOKEN" -H "x-forwarded-for: 203.0.113.10" -d '{"prompt":"hi"}'
probe 400 "untrusted forwarded IP stays in same bucket (2)" -X POST "$GEN" -H "$JSON" -H "x-app-token: $TOKEN" -H "x-forwarded-for: 198.51.100.11" -d '{"prompt":"hi"}'
probe 400 "untrusted forwarded IP stays in same bucket (3)" -X POST "$GEN" -H "$JSON" -H "x-app-token: $TOKEN" -H "x-forwarded-for: 192.0.2.12" -d '{"prompt":"hi"}'
probe 429 "per-client rate limit cannot be bypassed with forwarded IP" -X POST "$GEN" -H "$JSON" -H "x-app-token: $TOKEN" -H "x-forwarded-for: 192.0.2.13" -d '{"prompt":"hi"}'
probe 200 "/health still open after limit" "$BASE/health"

SHARED_PORT=8902
SHARED_BASE="http://127.0.0.1:$SHARED_PORT"
if lsof -ti tcp:$SHARED_PORT >/dev/null 2>&1; then
  echo "  FAIL  port $SHARED_PORT already in use — free it and rerun"
  FAIL=1
else
  # With the trusted-proxy setting on, distinct forwarded client IPs should
  # each receive their own client bucket while still sharing the one app-token
  # ceiling. This proves the aggregate cost guard is not bypassed by IP churn.
  OPENAI_API_KEY="dummy-key-gate-probes-only" \
  APP_TOKEN="$TOKEN" TRUST_PROXY=1 RATE_LIMIT_MAX=10 RATE_LIMIT_WINDOW_SEC=60 \
  SHARED_RATE_LIMIT_MAX=2 MEDIA_RATE_LIMIT_MAX=0 PORT=$SHARED_PORT \
    node backend/server.mjs >/dev/null 2>&1 &
  SHARED_PID=$!

  SHARED_UP=0
  for _ in $(seq 1 20); do
    if curl -s -m 1 -o /dev/null "$SHARED_BASE/health"; then SHARED_UP=1; break; fi
    sleep 0.25
  done

  if [ $SHARED_UP -ne 1 ]; then
    echo "  FAIL  shared-limit probe server did not come up on :$SHARED_PORT"
    FAIL=1
  else
    BASE="$SHARED_BASE"
    GEN="$BASE/api/ai/workout-generator"
    probe 400 "shared-token limit allows first client" -X POST "$GEN" -H "$JSON" -H "x-app-token: $TOKEN" -H "x-forwarded-for: 203.0.113.10" -d '{"prompt":"hi"}'
    probe 400 "shared-token limit allows second client" -X POST "$GEN" -H "$JSON" -H "x-app-token: $TOKEN" -H "x-forwarded-for: 198.51.100.11" -d '{"prompt":"hi"}'
    probe 429 "shared-token limit applies across client IPs" -X POST "$GEN" -H "$JSON" -H "x-app-token: $TOKEN" -H "x-forwarded-for: 192.0.2.12" -d '{"prompt":"hi"}'
  fi

  kill $SHARED_PID 2>/dev/null
  wait $SHARED_PID 2>/dev/null || true
fi

[ $FAIL -eq 0 ] && echo "BACKEND HARDENING CHECKS PASSED"
PASSBOOL=$([ $FAIL -eq 0 ] && echo true || echo false)
record $PASSBOOL
exit $FAIL
