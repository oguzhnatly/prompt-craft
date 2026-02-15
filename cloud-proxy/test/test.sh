#!/usr/bin/env bash
# PromptCraft Cloud Proxy — Integration Test Script
# Usage: PROXY_URL=http://localhost:8787 LICENSE_KEY=your-key bash test/test.sh

set -euo pipefail

PROXY_URL="${PROXY_URL:-http://localhost:8787}"
LICENSE_KEY="${LICENSE_KEY:-test-license-key-12345}"
PASS=0
FAIL=0

green() { printf "\033[32m%s\033[0m\n" "$1"; }
red()   { printf "\033[31m%s\033[0m\n" "$1"; }

check() {
  local name="$1" expected_status="$2" actual_status="$3" body="$4"
  if [ "$actual_status" -eq "$expected_status" ]; then
    green "PASS: $name (HTTP $actual_status)"
    PASS=$((PASS + 1))
  else
    red "FAIL: $name — expected $expected_status, got $actual_status"
    echo "  Body: $body"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== PromptCraft Cloud Proxy Tests ==="
echo "Target: $PROXY_URL"
echo ""

# ── 1. Health check ──────────────────────────────────────────────
echo "--- Health Check ---"
RESP=$(curl -s -w "\n%{http_code}" "$PROXY_URL/health")
STATUS=$(echo "$RESP" | tail -1)
BODY=$(echo "$RESP" | head -n -1)
check "GET /health returns 200" 200 "$STATUS" "$BODY"

echo "$BODY" | grep -q '"status":"ok"' && green "  → status: ok" || red "  → missing status field"
echo ""

# ── 2. 404 for unknown route ────────────────────────────────────
echo "--- Unknown Route ---"
RESP=$(curl -s -w "\n%{http_code}" "$PROXY_URL/v1/nonexistent")
STATUS=$(echo "$RESP" | tail -1)
BODY=$(echo "$RESP" | head -n -1)
check "GET /v1/nonexistent returns 404" 404 "$STATUS" "$BODY"
echo ""

# ── 3. Missing app identity header ──────────────────────────────
echo "--- Missing X-PromptCraft-Version ---"
RESP=$(curl -s -w "\n%{http_code}" -X POST "$PROXY_URL/v1/optimize" \
  -H "Content-Type: application/json" \
  -d '{"license_key":"test","model":"pc-standard","messages":[{"role":"user","content":"hello"}]}')
STATUS=$(echo "$RESP" | tail -1)
BODY=$(echo "$RESP" | head -n -1)
check "POST without X-PromptCraft-Version returns 403" 403 "$STATUS" "$BODY"
echo ""

# ── 4. Missing license key ──────────────────────────────────────
echo "--- Missing License Key ---"
RESP=$(curl -s -w "\n%{http_code}" -X POST "$PROXY_URL/v1/optimize" \
  -H "Content-Type: application/json" \
  -H "X-PromptCraft-Version: 1.0.0" \
  -d '{"model":"pc-standard","messages":[{"role":"user","content":"hello"}]}')
STATUS=$(echo "$RESP" | tail -1)
BODY=$(echo "$RESP" | head -n -1)
check "POST without license key returns 401" 401 "$STATUS" "$BODY"
echo ""

# ── 5. Invalid JSON body ────────────────────────────────────────
echo "--- Invalid JSON ---"
RESP=$(curl -s -w "\n%{http_code}" -X POST "$PROXY_URL/v1/optimize" \
  -H "Content-Type: application/json" \
  -H "X-PromptCraft-Version: 1.0.0" \
  -d 'not-json')
STATUS=$(echo "$RESP" | tail -1)
BODY=$(echo "$RESP" | head -n -1)
check "POST with invalid JSON returns 400" 400 "$STATUS" "$BODY"
echo ""

# ── 6. Valid request (with license key in body) ─────────────────
echo "--- Valid Optimize Request (license in body) ---"
RESP=$(curl -s -w "\n%{http_code}" -X POST "$PROXY_URL/v1/optimize" \
  -H "Content-Type: application/json" \
  -H "X-PromptCraft-Version: 1.0.0" \
  -d "{
    \"license_key\": \"$LICENSE_KEY\",
    \"model\": \"pc-standard\",
    \"messages\": [{\"role\": \"user\", \"content\": \"Say hello in one word.\"}],
    \"max_tokens\": 50,
    \"temperature\": 0.5,
    \"stream\": true
  }")
STATUS=$(echo "$RESP" | tail -1)
BODY=$(echo "$RESP" | head -n -1)
echo "  Status: $STATUS"
echo "  Body (first 200 chars): ${BODY:0:200}"
echo ""

# ── 7. Valid request (with Authorization header) ────────────────
echo "--- Valid Optimize Request (Authorization header) ---"
RESP=$(curl -s -w "\n%{http_code}" -X POST "$PROXY_URL/v1/optimize" \
  -H "Content-Type: application/json" \
  -H "X-PromptCraft-Version: 1.0.0" \
  -H "Authorization: Bearer $LICENSE_KEY" \
  -d '{
    "model": "pc-standard",
    "messages": [{"role": "user", "content": "Say hello in one word."}],
    "max_tokens": 50,
    "temperature": 0.5,
    "stream": true
  }')
STATUS=$(echo "$RESP" | tail -1)
BODY=$(echo "$RESP" | head -n -1)
echo "  Status: $STATUS"
echo "  Body (first 200 chars): ${BODY:0:200}"
echo ""

# ── 8. Provider-specific request ────────────────────────────────
echo "--- Provider-Specific Request (OpenAI) ---"
RESP=$(curl -s -w "\n%{http_code}" -X POST "$PROXY_URL/v1/optimize" \
  -H "Content-Type: application/json" \
  -H "X-PromptCraft-Version: 1.0.0" \
  -d "{
    \"license_key\": \"$LICENSE_KEY\",
    \"provider\": \"openai\",
    \"model\": \"gpt-4o-mini\",
    \"messages\": [{\"role\": \"user\", \"content\": \"Say hi.\"}],
    \"max_tokens\": 20,
    \"stream\": true
  }")
STATUS=$(echo "$RESP" | tail -1)
BODY=$(echo "$RESP" | head -n -1)
echo "  Status: $STATUS"
echo "  Body (first 200 chars): ${BODY:0:200}"
echo ""

# ── Summary ─────────────────────────────────────────────────────
echo "==============================="
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
  red "Some tests failed."
  exit 1
else
  green "All basic tests passed!"
fi
