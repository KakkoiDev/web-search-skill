---
name: web-search
description: Search the web via DuckDuckGo (ddgr) and fetch/read JS-rendered pages via Lightpanda. Provides wrappers for search, page fetch, and HTML-to-text extraction. Use when the user asks to search the web, look something up, read a URL, get current news, or find information online. No API key needed.
license: MIT
compatibility: macOS and Linux. Requires ddgr (brew install ddgr) and lightpanda (./setup.sh).
allowed-tools: Bash(ddgr:*), Bash(lightpanda:*), Bash(python3:*)
metadata:
  requires:
    bins:
      - ddgr
      - lightpanda
    env: []
  install:
    - brew install ddgr
    - kind: script
      script: ./scripts/setup-lightpanda.sh
      description: Install Lightpanda headless browser
---

# Web Search

**Disclaimer: This file serves dual purpose — it is both the skill instructions for the AI agent AND the implementation spec. A human or flash model should be able to implement all scripts from this document alone.**

## Architecture Overview

```
User asks agent → Agent runs ddgr → Gets search results (JSON) →
Agent runs fetch-url → Lightpanda renders JS → Gets rendered HTML →
Agent runs extract-text → Gets clean plain text → Agent reads + summarizes
```

Three shell scripts that compose into a full web search + read pipeline:

| Script | Tool | Purpose |
|--------|------|---------|
| `scripts/search.sh` | `ddgr` | Web search via DuckDuckGo |
| `scripts/fetch-url.sh` | `lightpanda` | Fetch JS-rendered page content |
| `scripts/extract-text.sh` | `python3` | Strip HTML tags → plain text |

No API keys. No external services. Entirely local.

## Setup (one-time)

Run setup script to install Lightpanda:

```bash
./scripts/setup-lightpanda.sh
```

This downloads the Lightpanda binary for the current platform (macOS arm64/x86_64, Linux x86_64/aarch64) to `$HOME/.local/bin/lightpanda`.

## Usage

### 1. Search the web

```bash
./scripts/search.sh <query> [--num N] [--recent d|w|m] [--site example.com]
```

**Flags:**
- `--num N` — number of results (1-25, default 10)
- `--recent PERIOD` — time filter: `d` (day), `w` (week), `m` (month)
- `--site DOMAIN` — restrict to domain (e.g., `stackoverflow.com`)
- `--json` — output raw JSON instead of formatted

**Returns:** Formatted or JSON list of `[title, url, abstract]` per result.

**Bangs (DDG shortcuts):**
```
./scripts/search.sh "!w Claude AI"          # Wikipedia
./scripts/search.sh "!so python asyncio"    # StackOverflow
./scripts/search.sh "!gh lightpanda"        # GitHub
./scripts/search.sh "!yt coding tutorial"   # YouTube
```

### 2. Fetch a page (with JS rendering)

```bash
./scripts/fetch-url.sh <url> [--timeout SECS] [--no-cache]
```

**Flags:**
- `--timeout SECS` — render timeout (default 30)
- `--no-cache` — bypass cache, force re-render
- `--raw` — output raw HTML instead of plain text

**Returns:** Plain text of the rendered page (or raw HTML with `--raw`).

**Fallback:** If Lightpanda fails, falls back to `curl` for simple pages.

### 3. Extract text from HTML

```bash
./scripts/extract-text.sh <html-file>       # from file
cat page.html | ./scripts/extract-text.sh   # from stdin
```

**Returns:** Clean plain text, `script`/`style`/`nav`/`footer` tags removed.

### 4. Combined: search + fetch top results

```bash
./scripts/search-and-read.sh <query> [--num N] [--recent PERIOD]
```

Shortcut that searches, fetches top 3 results, extracts text, and outputs everything.

## Implementation Spec

### `scripts/search.sh`

**Input:** query string + optional flags
**Output:** formatted or JSON search results

**Behavior:**
1. Parse args: query (positional), `--num N`, `--recent d|w|m`, `--site DOMAIN`, `--json`
2. Build ddgr command: `ddgr --noua --np --json -n N [-t SPAN] [-w SITE] "query"`
3. Run ddgr, capture stdout
4. If `--json`: output raw JSON
5. Else: parse JSON, format as numbered list:
   ```
   1. Title
      Abstract text here...
      https://url.example.com
   ```
6. Error handling: if ddgr fails, suggest `brew install ddgr` or `pip install ddgr`

**Key ddgr flags:**
- `--noua` — disable user agent (always)
- `--np` — no interactive prompt
- `--json` — JSON output for parsing

**Edge cases:**
- Empty results → print "No results found for: <query>"
- Query with special chars → quote properly
- `!bangs` → escape `!` with backslash in bash

### `scripts/fetch-url.sh`

**Input:** URL string + optional flags
**Output:** plain text of rendered page

**Behavior:**
1. Parse args: URL (positional), `--timeout N`, `--no-cache`, `--raw`
2. Check `lightpanda` is installed (in PATH or `$HOME/.local/bin/lightpanda`)
3. Build cache key: md5(url) → `~/.cache/web-search-skill/<hash>.txt`
4. If cache exists + not expired (5min) + not `--no-cache`: serve cached text
5. Else: run `lightpanda fetch --dump "$URL"` (with timeout env)
6. If lightpanda fails (non-zero exit / timeout): run `curl -sL -A "Mozilla/5.0" "$URL"` as fallback
7. If `--raw`: output raw HTML
8. Else: pipe through `extract-text.sh`, return plain text
9. Cache result (plain text version)

**Cache:** `~/.cache/web-search-skill/` directory, 5-minute TTL.

**Edge cases:**
- URL without scheme → prepend `https://`
- CAPTCHA/blocked page → return partial content with warning
- Timeout → fallback to curl, then warn if curl also fails
- Empty page → return "Page returned empty content"

### `scripts/extract-text.sh`

**Input:** HTML from file or stdin
**Output:** plain text, one paragraph per line

**Behavior:**
1. Read from file (arg1) or stdin
2. Python script:
   - Parse with `html.parser` (stdlib)
   - Skip tags: `script`, `style`, `nav`, `footer`, `header`, `noscript`
   - Collect text from remaining tags
   - `html.unescape()` entities
   - Collapse whitespace: `re.sub(r'\n\s*\n', '\n\n', text)`
   - Deduplicate consecutive identical lines
3. Output plain text

**Python code (embedded in shell script or as separate file):**
```python
#!/usr/bin/env python3
import sys, re
from html import unescape
from html.parser import HTMLParser

class TextExtractor(HTMLParser):
    def __init__(self):
        super().__init__()
        self.text = []
        self.skip = {'script', 'style', 'nav', 'footer', 'header', 'noscript'}
        self.current = None
    
    def handle_starttag(self, tag, attrs):
        self.current = tag
    
    def handle_endtag(self, tag):
        self.current = None
    
    def handle_data(self, data):
        if self.current not in self.skip:
            t = data.strip()
            if t and len(t) > 1:
                self.text.append(t)
    
    def get_text(self):
        text = '\n'.join(self.text)
        text = unescape(text)
        text = re.sub(r'\n{3,}', '\n\n', text)
        # Dedup
        lines = []
        for line in text.split('\n'):
            if line not in lines:
                lines.append(line)
        return '\n'.join(lines)

def main():
    html = sys.stdin.read() if len(sys.argv) < 2 else open(sys.argv[1]).read()
    parser = TextExtractor()
    parser.feed(html)
    print(parser.get_text())

if __name__ == '__main__':
    main()
```

### `scripts/search-and-read.sh`

**Input:** query + optional flags
**Output:** search results followed by extracted text from top 3

**Behavior:**
1. Run `search.sh "$@"` to get results
2. Parse top 3 URLs from JSON output
3. For each URL: echo separator, run `fetch-url.sh <url>`
4. Output everything as a single document

### `scripts/setup-lightpanda.sh`

**Input:** none
**Output:** installs lightpanda binary

**Behavior:**
1. Determine platform from `uname -s` and `uname -m`
2. Map to Lightpanda nightly URL:
   - Darwin-arm64 → `https://github.com/lightpanda-io/browser/releases/download/nightly/lightpanda-aarch64-macos`
   - Darwin-x86_64 → `https://github.com/lightpanda-io/browser/releases/download/nightly/lightpanda-x86_64-macos`
   - Linux-x86_64 → `https://github.com/lightpanda-io/browser/releases/download/nightly/lightpanda-x86_64-linux`
   - Linux-aarch64 → `https://github.com/lightpanda-io/browser/releases/download/nightly/lightpanda-aarch64-linux`
3. Create `$HOME/.local/bin` if not exists
4. Download binary, chmod +x
5. Print instructions to add to PATH if needed

## Key Design Decisions (for the implementor)

1. **No API keys.** ddgr is free, Lightpanda is local. Zero-config after setup.
2. **Composable.** Each script does one thing and outputs to stdout. Can pipe together.
3. **Caching.** fetch-url caches rendered pages for 5 minutes. Avoids hammering sites.
4. **Fallbacks.** Lightpanda → curl fallback. JS failure → serve raw HTML. Graceful degradation.
5. **Plain text output.** Agents parse text, not HTML. extract-text.sh is the bridge.
6. **Single-binary deps.** ddgr and lightpanda are single binaries. No npm install, no venv.

## Why This Beats Raw Python Scraping

| Raw Python + requests | This skill |
|---|---|
| JS sites return empty/partial | Lightpanda renders full JS |
| CAPTCHAs invisible | Lightpanda browser profile |
| Manual HTML parsing each time | Standardized extract-text |
| No caching | 5-min built-in cache |
| One-off scripts | Reusable composable tools |

## Testing (for implementor)

```bash
# Search
./scripts/search.sh "Japan news" --recent w --num 5

# Fetch
./scripts/fetch-url.sh https://www.asahi.com/ajw/

# Search + read (combined)
./scripts/search-and-read.sh "Japan news today" --num 3
```

Expected: real headlines and article text from JS-heavy Japanese news sites.

## Agent Usage Pattern

When installed as a Pi skill, the agent should:

1. For "search for X": run `./scripts/search.sh "X"`
2. For "what's on this page": run `./scripts/fetch-url.sh <url>`
3. For "summarize what you find about X": run `./scripts/search-and-read.sh "X"`
4. Always prefer search-and-read for "tell me about" / "what's happening with" queries
5. Quote URLs to fetch from search results when user asks about a specific result
6. If ddgr not installed: guide user to `brew install ddgr`
7. If lightpanda not installed: guide user to `./scripts/setup-lightpanda.sh`

## Future Ideas (not in MVP)

- Configurable search engine (startpage, google via googler)
- Result ranking/filtering
- Recursive depth ("fetch and also follow links")
- Image search
- PDF/text file download from search results
- Parallel multi-URL fetch
- Dark mode / human-readable formatting
