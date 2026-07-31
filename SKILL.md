---
name: web-search
description: >
  Search the web via DuckDuckGo and fetch/read JS-rendered pages via Lightpanda.
  Registers search_web, fetch_url, and extract_text as first-class tools.
  Use these tools — never raw ddgr or curl. No API key needed.
license: MIT
compatibility: macOS and Linux. Requires ddgr, lightpanda (or curl fallback).
metadata:
  requires:
    bins:
      - ddgr
    env: []
  install:
    - brew install ddgr
    - kind: script
      script: ./scripts/setup-lightpanda.sh
      description: Install Lightpanda headless browser
---

# Web Search

Provides three agent tools for searching and reading the web. All tools
are first-class functions — call them by name, no path resolution needed.

## Tools

| Tool | Purpose |
|------|---------|
| `search_web(query, num?, recent?, site?)` | Search DuckDuckGo. Returns JSON with title/url/snippet. Supports !bang prefixes (!w, !gh, !so, !yt). |
| `fetch_url(url, timeout?, noCache?, raw?)` | Fetch a URL with JS rendering (Lightpanda). Returns clean plain text. Falls back to curl. Cached 5 min. |
| `extract_text(html)` | Strip HTML tags → clean plain text. Accepts file path or inline HTML string. |

## Rules

- **Always** use `search_web` for web searches. Never use raw `ddgr` or `curl`.
- **Always** use `fetch_url` to read URLs. It renders JS, strips HTML, and caches.
- Combine: search with `search_web`, then `fetch_url` the best results.
- `extract_text` is only needed for raw HTML from other sources (fetch_url does it automatically).

## Prerequisites

```bash
brew install ddgr
./scripts/setup-lightpanda.sh   # optional — fetch_url falls back to curl
```

## Fallback Behavior

- `fetch_url` without Lightpanda: uses curl (no JS rendering, emits a note to stderr)
- `search_web` without ddgr: exits with error message "Install: brew install ddgr"
- `fetch_url` cache: 5-minute TTL in `~/.cache/web-search-skill/`

## Implementation

Source code and full implementation spec: see `SPEC.md`. Shell scripts live in `scripts/`.
