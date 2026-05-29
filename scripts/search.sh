#!/usr/bin/env bash
#
# Search DuckDuckGo via ddgr
#
set -euo pipefail

usage() {
  echo "Usage: $0 <query> [--num N] [--recent d|w|m] [--site DOMAIN] [--json]" >&2
  exit 1
}

# Defaults
NUM=10
RECENT=""
SITE=""
JSON=false

# Collect positional args before flags
POSITIONAL=()
while [ $# -gt 0 ]; do
  case "$1" in
    --num)
      NUM="$2"; shift 2 ;;
    --recent)
      RECENT="$2"; shift 2 ;;
    --site)
      SITE="$2"; shift 2 ;;
    --json)
      JSON=true; shift ;;
    --help|-h)
      usage ;;
    *)
      POSITIONAL+=("$1"); shift ;;
  esac
done

if [ "${#POSITIONAL[@]}" -eq 0 ]; then
  usage
fi

# Join positional args into query string
QUERY="${POSITIONAL[*]}"

# Validate NUM
if [ "$NUM" -lt 1 ] || [ "$NUM" -gt 25 ]; then
  echo "Error: --num must be between 1 and 25" >&2
  exit 1
fi

# Check ddgr
if ! command -v ddgr &>/dev/null; then
  echo "Error: ddgr not found. Install: brew install ddgr" >&2
  exit 1
fi

# Build ddgr args
DDGR_ARGS=(--noua --np --json -n "$NUM")
if [ -n "$RECENT" ]; then
  DDGR_ARGS+=(-t "$RECENT")
fi
if [ -n "$SITE" ]; then
  DDGR_ARGS+=(-w "$SITE")
fi

# Run ddgr
# Escape !bang queries — ddgr expects literal !, but bash history expansion may interfere
set +H
OUTPUT=$(ddgr "${DDGR_ARGS[@]}" -- "$QUERY" 2>/dev/null || true)
set -H

if [ -z "$OUTPUT" ] || echo "$OUTPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); exit(0 if len(d)==0 else 1)" 2>/dev/null; then
  echo "No results found for: $QUERY"
  exit 0
fi

if [ "$JSON" = true ]; then
  echo "$OUTPUT"
  exit 0
fi

# Format as numbered list
python3 -c "
import sys, json

data = json.load(sys.stdin)
for i, item in enumerate(data, 1):
    title = item.get('title', '').strip()
    abstract = item.get('abstract', '').strip()
    url = item.get('url', '').strip()
    print(f'{i}. {title}')
    if abstract:
        print(f'   {abstract}')
    print(f'   {url}')
    print()
" <<< "$OUTPUT"
