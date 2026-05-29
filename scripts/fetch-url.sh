#!/usr/bin/env bash
#
# Fetch a URL with JS rendering via Lightpanda, return plain text
#
set -euo pipefail

usage() {
  echo "Usage: $0 <url> [--timeout SECS] [--no-cache] [--raw]" >&2
  exit 1
}

# Defaults
TIMEOUT=30
NO_CACHE=false
RAW=false

# Collect positional args
POSITIONAL=()
while [ $# -gt 0 ]; do
  case "$1" in
    --timeout)
      TIMEOUT="$2"; shift 2 ;;
    --no-cache)
      NO_CACHE=true; shift ;;
    --raw)
      RAW=true; shift ;;
    --help|-h)
      usage ;;
    *)
      POSITIONAL+=("$1"); shift ;;
  esac
done

if [ "${#POSITIONAL[@]}" -eq 0 ]; then
  usage
fi

URL="${POSITIONAL[0]}"

# Add https:// if no scheme
if [[ "$URL" != http://* && "$URL" != https://* ]]; then
  URL="https://${URL}"
fi

# Cache dir
CACHE_DIR="${HOME}/.cache/web-search-skill"
mkdir -p "$CACHE_DIR"
CACHE_KEY=$(echo -n "$URL" | md5 -q 2>/dev/null || echo -n "$URL" | md5sum | cut -d' ' -f1)
CACHE_FILE="${CACHE_DIR}/${CACHE_KEY}.txt"
CACHE_TTL=300  # 5 minutes

# Check cache
if [ "$NO_CACHE" = false ] && [ -f "$CACHE_FILE" ]; then
  AGE=$(( $(date +%s) - $(stat -f%m "$CACHE_FILE" 2>/dev/null || stat -c%Y "$CACHE_FILE" 2>/dev/null) ))
  if [ "$AGE" -lt "$CACHE_TTL" ]; then
    cat "$CACHE_FILE"
    exit 0
  fi
fi

# Find lightpanda
LIGHTPANDA=""
if command -v lightpanda &>/dev/null; then
  LIGHTPANDA="lightpanda"
elif [ -x "${HOME}/.local/bin/lightpanda" ]; then
  LIGHTPANDA="${HOME}/.local/bin/lightpanda"
fi

FETCHED_HTML=""
FETCH_OK=false

if [ -n "$LIGHTPANDA" ]; then
  # Run lightpanda with timeout
  FETCHED_HTML=$(timeout "$TIMEOUT" "$LIGHTPANDA" fetch --dump "$URL" 2>/dev/null || true)
  if [ -n "$FETCHED_HTML" ]; then
    FETCH_OK=true
  fi
fi

# Fallback to curl
if [ "$FETCH_OK" = false ]; then
  FETCHED_HTML=$(curl -sL -A "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" --max-time "$TIMEOUT" "$URL" 2>/dev/null || true)
  if [ -z "$FETCHED_HTML" ]; then
    echo "Error: Page returned empty content" >&2
    exit 1
  fi
  # If lightpanda wasn't available, note the fallback
  if [ -z "$LIGHTPANDA" ]; then
    echo "[Note: Lightpanda not installed. Used curl fallback — JS not rendered.]" >&2
  else
    echo "[Note: Lightpanda failed. Used curl fallback — JS not rendered.]" >&2
  fi
fi

# Output
if [ "$RAW" = true ]; then
  echo "$FETCHED_HTML"
  # Cache raw HTML
  echo "$FETCHED_HTML" > "$CACHE_FILE"
else
  # Extract text
  PLAIN_TEXT=$(echo "$FETCHED_HTML" | "$(dirname "$0")/extract-text.sh" 2>/dev/null || echo "$FETCHED_HTML")
  echo "$PLAIN_TEXT"
  # Cache plain text
  echo "$PLAIN_TEXT" > "$CACHE_FILE"
fi
