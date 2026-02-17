#!/bin/bash
# PromptCraft Alfred Workflow — Optimize Prompt
#
# Environment variables (set in Alfred workflow configuration):
#   PROMPTCRAFT_TOKEN  — Bearer token from PromptCraft Settings
#   PROMPTCRAFT_PORT   — Local API port (default: 9847)

set -euo pipefail

PORT="${PROMPTCRAFT_PORT:-9847}"
TOKEN="${PROMPTCRAFT_TOKEN:-}"
INPUT="{query}"

if [ -z "$TOKEN" ]; then
  echo '{"items":[{"title":"Missing API token","subtitle":"Set PROMPTCRAFT_TOKEN in the workflow environment variables","valid":false}]}'
  exit 0
fi

if [ -z "$INPUT" ]; then
  echo '{"items":[{"title":"No input provided","subtitle":"Type a prompt to optimize","valid":false}]}'
  exit 0
fi

# Escape input for JSON using python3
ESCAPED=$(python3 -c "import json,sys; print(json.dumps(sys.argv[1]))" "$INPUT")

RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "http://127.0.0.1:${PORT}/optimize" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{\"text\":${ESCAPED}}" 2>/dev/null) || {
  echo '{"items":[{"title":"PromptCraft not running","subtitle":"Start PromptCraft and enable Local API in Settings","valid":false}]}'
  exit 0
}

HTTP_CODE=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | sed '$d')

if [ "$HTTP_CODE" != "200" ]; then
  ERROR=$(echo "$BODY" | python3 -c "import json,sys; print(json.load(sys.stdin).get('error','Unknown error'))" 2>/dev/null || echo "HTTP $HTTP_CODE")
  echo "{\"items\":[{\"title\":\"Optimization failed\",\"subtitle\":\"${ERROR}\",\"valid\":false}]}"
  exit 0
fi

OUTPUT=$(echo "$BODY" | python3 -c "import json,sys; print(json.load(sys.stdin)['output'])" 2>/dev/null)
STYLE=$(echo "$BODY" | python3 -c "import json,sys; print(json.load(sys.stdin).get('style',''))" 2>/dev/null)
DURATION=$(echo "$BODY" | python3 -c "import json,sys; print(json.load(sys.stdin).get('durationMs',''))" 2>/dev/null)

# Output as Alfred Script Filter JSON
cat <<EOF
{
  "items": [
    {
      "title": "Optimized Prompt",
      "subtitle": "${STYLE} — ${DURATION}ms — press Enter to copy",
      "arg": $(python3 -c "import json,sys; print(json.dumps(sys.argv[1]))" "$OUTPUT"),
      "text": {
        "copy": $(python3 -c "import json,sys; print(json.dumps(sys.argv[1]))" "$OUTPUT"),
        "largetype": $(python3 -c "import json,sys; print(json.dumps(sys.argv[1]))" "$OUTPUT")
      },
      "valid": true
    }
  ]
}
EOF
