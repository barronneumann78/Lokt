#!/bin/bash
# Hardening sensors: app-token auth, per-token+IP rate limiting, body-size cap.
# Boots a THROWAWAY server instance with inline test env (no .env, no OpenAI
# key — every probe resolves at the gate or input validation, zero token cost)
# and asserts the gate behavior end to end. The normal :8787 dev server is
# untouched. See backend/DEPLOY.md for the deployed setup these gates protect.
set -uo pipefail
cd "$(dirname "$0")/.."
PORT=8901
BASE="http://127.0.0.1:$PORT"
TOKEN="harness-test-token"
FAIL=0

record() {
  echo "{\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"kind\":\"backend-hardening\",\"pass\":$1}" >> harness/history.jsonl
}

if lsof -ti tcp:$PORT >/dev/null 2>&1; then
  echo "  FAIL  port $PORT already in use — free it and rerun"
  record false
  exit 1
fi

# Dummy key: routes 500 on a missing key before validation, but every probe
# below resolves at the gate/validation layer — the key is never used.
OPENAI_API_KEY="dummy-key-gate-probes-only" \
APP_TOKEN="$TOKEN" RATE_LIMIT_MAX=3 RATE_LIMIT_WINDOW_SEC=60 MAX_BODY_BYTES=1000 PORT=$PORT \
  node backend/server.mjs >/dev/null 2>&1 &
SERVER_PID=$!
trap 'kill $SERVER_PID 2>/dev/null' EXIT

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
probe 400 "valid token reaches validation (short prompt)" -X POST "$GEN" -H "$JSON" -H "x-app-token: $TOKEN" -d '{"prompt":"hi"}'
BIG_BODY="{\"prompt\":\"$(printf 'a%.0s' $(seq 1 2000))\"}"
probe 413 "body cap rejects oversized body" -X POST "$GEN" -H "$JSON" -H "x-app-token: $TOKEN" -d "$BIG_BODY"
probe 400 "third request still allowed" -X POST "$GEN" -H "$JSON" -H "x-app-token: $TOKEN" -d '{"prompt":"hi"}'
probe 429 "rate limit trips on request 4 of 3" -X POST "$GEN" -H "$JSON" -H "x-app-token: $TOKEN" -d '{"prompt":"hi"}'
probe 200 "/health still open after limit" "$BASE/health"

[ $FAIL -eq 0 ] && echo "BACKEND HARDENING CHECKS PASSED"
PASSBOOL=$([ $FAIL -eq 0 ] && echo true || echo false)
record $PASSBOOL
exit $FAIL
