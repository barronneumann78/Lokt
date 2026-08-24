#!/bin/bash
# Backend sensors that cost zero OpenAI tokens: liveness + request validation
# (validation rejections return 400 before any model call).
set -uo pipefail
BASE="http://127.0.0.1:8787"
FAIL=0

HEALTH=$(curl -s -m 5 "$BASE/health")
if echo "$HEALTH" | grep -q '"ok":true'; then
  echo "  PASS  /health ok ($(echo "$HEALTH" | head -c 60)...)"
else
  echo "  FAIL  backend not responding on :8787 — start it: cd backend && npm start"
  exit 1
fi

# Validation probes — must 400 without touching OpenAI.
CODE=$(curl -s -m 10 -o /dev/null -w "%{http_code}" -X POST "$BASE/api/ai/workout-generator" \
  -H "Content-Type: application/json" -d '{"prompt":"hi"}')
[ "$CODE" = "400" ] && echo "  PASS  generator rejects short prompt (400)" || { echo "  FAIL  generator short-prompt: got $CODE, want 400"; FAIL=1; }

CODE=$(curl -s -m 10 -o /dev/null -w "%{http_code}" -X POST "$BASE/api/ai/exercise-coach/explain" \
  -H "Content-Type: application/json" -d '{"exercise":{"name":"Push-Up"},"mode":"bogus"}')
[ "$CODE" = "400" ] && echo "  PASS  explain rejects invalid mode (400)" || { echo "  FAIL  explain invalid-mode: got $CODE, want 400"; FAIL=1; }

CODE=$(curl -s -m 10 -o /dev/null -w "%{http_code}" -X POST "$BASE/api/ai/workout-generator/explain" \
  -H "Content-Type: application/json" -d '{"routine":{}}')
[ "$CODE" = "400" ] && echo "  PASS  routine-explain rejects empty routine (400)" || { echo "  FAIL  routine-explain empty: got $CODE, want 400"; FAIL=1; }

[ $FAIL -eq 0 ] && echo "BACKEND CHECKS PASSED"
exit $FAIL
