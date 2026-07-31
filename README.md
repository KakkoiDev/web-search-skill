# Web Search Skill

[![skills.sh](https://skills.sh/b/KakkoiDev/web-search-skill)](https://skills.sh/KakkoiDev/web-search-skill)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

A Pi agent skill for searching the web and reading JS-rendered pages. No API keys needed.

Uses [ddgr](https://github.com/jarun/ddgr) (DuckDuckGo CLI) for search and [Lightpanda](https://lightpanda.io/) (headless browser) for fetching pages with JavaScript rendering — news sites, SPAs, docs, all work.

## Why

Modern websites rely on JavaScript for rendering. Plain HTTP requests return empty shells. Existing solutions require API keys (Nansen, Brave, Serper). This skill:

- **Zero config** — install two binaries, no accounts
- **Real rendering** — Lightpanda executes JavaScript, not just curl
- **Agent-native** — outputs plain text, not HTML, so LLMs can read it directly
- **Composable** — search, fetch, extract are independent scripts

## Tools (v2 — Pi Extension)

When installed as a Pi extension (`pi install`), this skill registers three
first-class agent tools. Call them by name — no path resolution needed.

| Tool | Purpose |
|------|---------|
| `search_web(query, num?, recent?, site?)` | Search DuckDuckGo. Returns JSON with title/url/snippet. Supports !bang prefixes. |
| `fetch_url(url, timeout?, noCache?, raw?)` | Fetch a URL with JS rendering (Lightpanda). Returns clean plain text. Cached 5 min. |
| `extract_text(html)` | Strip HTML tags → clean plain text. Accepts file path or inline HTML. |

## Installation

### With Pi extension (v2 — recommended)

```bash
pi install /path/to/web-search-skill
# or from a registry:
# pi install web-search-skill
```

This registers `search_web`, `fetch_url`, and `extract_text` as first-class
agent tools. The agent will call them by name — no `ddgr` or `curl` needed.

### Without extension (v1 — SKILL.md only)

```bash
npx skills add KakkoiDev/web-search-skill
```

This loads the SKILL.md instructions only (no registered tools). The agent
will still know how to use the scripts, but needs to call them via `bash`.

### Prerequisites

```bash
# DuckDuckGo CLI
brew install ddgr

# Lightpanda headless browser
./scripts/setup-lightpanda.sh
```

## Quick Start

```bash
# Search the web
./scripts/search.sh "Japan news" --recent w --num 5

# Fetch a page
./scripts/fetch-url.sh https://www.asahi.com/ajw/

# Search + fetch top results in one command
./scripts/search-and-read.sh "Tokyo inflation BOJ policy"
```

## How It Works

```
User query → ddgr search → JSON results → Lightpanda renders each page →
extract-text strips HTML → plain text → agent reads + summarizes
```

## Scripts

| Script | Purpose |
|--------|---------|
| `search.sh` | Search DuckDuckGo, return formatted or JSON results |
| `fetch-url.sh` | Fetch a URL with JS rendering, return plain text |
| `extract-text.sh` | Convert HTML to clean plain text |
| `search-and-read.sh` | Search + fetch top 3 results in one pass |
| `setup-lightpanda.sh` | One-time Lightpanda installation |

## vs. Other Web Search Skills

| | [ddgr-skill](https://skills.sh/ysm-dev/ddgr-skill/ddgr) | [web-scraping](https://skills.sh/mindrally/skills/web-scraping) | **web-search (this)** |
|---|---|---|---|
| Skill type | Instructions only | General guidance | **Wrapper scripts + Pi extension** |
| Web search | ✅ ddgr | ❌ | ✅ ddgr |
| Page fetch | ❌ | ❌ | ✅ Lightpanda + curl fallback |
| Text extraction | ❌ | ❌ (suggests BS4) | ✅ Python stdlib HTML parser |
| JS rendering | ❌ | ❌ (manual Selenium) | ✅ Automatic via Lightpanda |
| Combined workflow | ❌ | ❌ | ✅ `search-and-read` single pass |
| First-class tools | ❌ | ❌ | ✅ **3 registered Pi tools** |
| API keys needed | None | None | None |
| Agent-native output | Semi (ddgr raw JSON) | Depends on user script | **Clean plain text** |

## Credits

- [ddgr](https://github.com/jarun/ddgr) by jarun — terminal DuckDuckGo client
- [Lightpanda](https://github.com/lightpanda-io/browser) — headless browser for AI
- [lightpanda-proxy](https://github.com/KakkoiDev/lightpanda-proxy) — companion proxy for w3m/text browsers

## License

MIT
