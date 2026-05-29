#!/usr/bin/env bash
#
# Search + fetch top results in one pass
#
set -euo pipefail

usage() {
  echo "Usage: $0 <query> [--num N] [--recent PERIOD]" >&2
  exit 1
}

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Defaults
NUM=3
RECENT=""
SEARCH_ARGS=()
POSITIONAL=()

# Parse flags (before and after query)
while [ $# -gt 0 ]; do
  case "$1" in
    --num)
      NUM="$2"; shift 2 ;;
    --recent)
      RECENT="$2"
      SEARCH_ARGS+=(--recent "$2")
      shift 2 ;;
    --help|-h)
      usage ;;
    -*)
      echo "Unknown flag: $1" >&2
      exit 1 ;;
    *)
      POSITIONAL+=("$1")
      shift ;;
  esac
done

if [ "${#POSITIONAL[@]}" -eq 0 ]; then
  usage
fi

QUERY="${POSITIONAL[*]}"

echo "========================================"
echo "Search: $QUERY"
echo "========================================"
echo ""

# Run search with JSON output
SEARCH_JSON=$("${SCRIPT_DIR}/search.sh" "$QUERY" --json ${SEARCH_ARGS[@]+"${SEARCH_ARGS[@]}"} --num "$NUM" 2>/dev/null || true)

if [ -z "$SEARCH_JSON" ] || echo "$SEARCH_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); exit(0 if len(d)==0 else 1)" 2>/dev/null; then
  echo "No results found."
  exit 0
fi

# Print formatted search results
"${SCRIPT_DIR}/search.sh" "$QUERY" ${SEARCH_ARGS[@]+"${SEARCH_ARGS[@]}"} --num "$NUM" 2>/dev/null || true

# Extract top N URLs from search results
URLS=()
while IFS= read -r url; do
  [ -n "$url" ] && URLS+=("$url")
done < <(echo "$SEARCH_JSON" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for item in data[:${NUM}]:
    url = item.get('url', '').strip()
    if url:
        print(url)
")

echo ""
echo "========================================"
echo "Fetching pages..."
echo "========================================"

for url in "${URLS[@]}"; do
  echo ""
  echo "--- ${url} ---"
  echo ""
  "${SCRIPT_DIR}/fetch-url.sh" "$url" --timeout 30 2>&1 || echo "[Failed to fetch ${url}]"
  echo ""
done

echo "========================================"
echo "Done."
echo "========================================"
