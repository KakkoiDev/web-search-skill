# Web-Search Skill Fix Plan

## Problem

Agents bypass the web-search skill and use raw `ddgr` directly because:

1. **No first-class tools.** Scripts require path resolution (`./scripts/search.sh` relative to skill dir). Agents see `bash` and `read` in their tool list, not `search_web`. Raw `ddgr --json | python3` is zero-path, one command — lower friction.

2. **SKILL.md buries usage under spec.** ~300 lines mixing AI instructions with implementation details. The actual "how to use" commands appear at line ~70, after architecture diagrams and setup. Agents skim and miss it.

3. **Weak trigger.** `"Use when the user asks to search the web"` is broad and passive. When an agent is mid-task researching something, it thinks "run ddgr" not "use the web-search skill."

## Solution

Register `search_web`, `fetch_url`, `extract_text` as first-class Pi extension tools. Restructure SKILL.md: split AI instructions from implementation spec, put quick usage at top. Agents will call tools by name — no path, no `ddgr` raw.

## File Changes

### New Files

#### 1. `extension.ts` (new)

Pi extension registering three tools that wrap the existing shell scripts.

**Path:** `<skill-dir>/extension.ts`

```typescript
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const exec = promisify(execFile);
const __filename = fileURLToPath(import.meta.url);
const SKILL_DIR = dirname(__filename);

function script(name: string): string {
  return join(SKILL_DIR, "scripts", name);
}

export default function (pi: ExtensionAPI) {
  // ── search_web ──
  pi.registerTool({
    name: "search_web",
    label: "Web Search",
    description:
      "Search the web via DuckDuckGo. Returns formatted results with titles, URLs, and snippets. " +
      "Use this instead of raw ddgr or curl — it handles errors, formatting, and edge cases.",
    promptSnippet:
      "Search DuckDuckGo and return formatted results (title, URL, snippet per result)",
    promptGuidelines: [
      "Prefer search_web over raw ddgr or curl for any web search. It handles errors, formatting, and edge cases automatically.",
      "Use search_web when the user asks to look something up online, find current information, " +
        "search for documentation, or get recent news.",
      "When results include a URL the user wants to read, use fetch_url to get the full page content.",
    ],
    parameters: Type.Object({
      query: Type.String({ description: "Search query. Use !bang prefixes for specific sites: !w (Wikipedia), !gh (GitHub), !so (StackOverflow), !yt (YouTube)" }),
      num: Type.Optional(
        Type.Number({
          description: "Number of results (1-25, default 10)",
          minimum: 1,
          maximum: 25,
        })
      ),
      recent: Type.Optional(
        Type.String({
          description: "Time filter: 'd' (day), 'w' (week), 'm' (month)",
        })
      ),
      site: Type.Optional(
        Type.String({
          description: "Restrict to domain, e.g. 'stackoverflow.com' or 'github.com'",
        })
      ),
    }),
    async execute(_toolCallId, params, _signal) {
      const args: string[] = [params.query, "--json"];
      if (params.num) args.push("--num", String(params.num));
      if (params.recent) args.push("--recent", params.recent);
      if (params.site) args.push("--site", params.site);

      const { stdout } = await exec(script("search.sh"), args, {
        timeout: 15_000,
        maxBuffer: 1024 * 1024,
        env: { ...process.env, PATH: process.env.PATH },
      });

      return {
        content: [{ type: "text", text: stdout }],
        details: {},
      };
    },
  });

  // ── fetch_url ──
  pi.registerTool({
    name: "fetch_url",
    label: "Fetch URL",
    description:
      "Fetch a web page with JS rendering (Lightpanda) and return clean plain text. " +
      "Falls back to curl if Lightpanda is unavailable. Results are cached for 5 minutes. " +
      "Use this instead of raw curl or lightpanda — it handles JS rendering, caching, and fallbacks.",
    promptSnippet:
      "Fetch a URL, render JavaScript, and return clean plain text",
    promptGuidelines: [
      "Use fetch_url to read the full content of a URL. Prefer it over raw curl — it renders JavaScript and strips HTML automatically.",
      "Combine with search_web: search first, then fetch_url the most relevant results.",
      "fetch_url caches results for 5 minutes. Use --no-cache to force a fresh fetch.",
    ],
    parameters: Type.Object({
      url: Type.String({ description: "URL to fetch. Scheme auto-added if missing." }),
      timeout: Type.Optional(
        Type.Number({
          description: "Timeout in seconds (default 30)",
          minimum: 5,
          maximum: 120,
        })
      ),
      noCache: Type.Optional(
        Type.Boolean({ description: "Bypass 5-minute cache, force fresh fetch" })
      ),
      raw: Type.Optional(
        Type.Boolean({ description: "Return raw HTML instead of plain text" })
      ),
    }),
    async execute(_toolCallId, params, _signal) {
      const args: string[] = [params.url];
      if (params.timeout) args.push("--timeout", String(params.timeout));
      if (params.noCache) args.push("--no-cache");
      if (params.raw) args.push("--raw");

      const { stdout } = await exec(script("fetch-url.sh"), args, {
        timeout: (params.timeout ?? 30) * 1000 + 5000,
        maxBuffer: 5 * 1024 * 1024,
        env: { ...process.env, PATH: process.env.PATH },
      });

      return {
        content: [{ type: "text", text: stdout }],
        details: {},
      };
    },
  });

  // ── extract_text ──
  pi.registerTool({
    name: "extract_text",
    label: "Extract Text",
    description:
      "Strip HTML tags and return clean plain text from HTML content. " +
      "Removes script, style, nav, footer, and header elements. " +
      "Handles entities, deduplicates lines, and collapses whitespace.",
    promptSnippet: "Strip HTML tags and return clean plain text",
    promptGuidelines: [
      "Use extract_text when you have raw HTML (from curl, a file, or --raw output from fetch_url) and need clean text.",
      "fetch_url already does this automatically — you only need extract_text for separate HTML sources.",
    ],
    parameters: Type.Object({
      html: Type.String({
        description:
          "Raw HTML content to extract text from. Can be a file path or inline HTML string.",
      }),
    }),
    async execute(_toolCallId, params, _signal) {
      // If html looks like a readable file path, use it as file input
      const html = params.html;
      let stdout: string;

      try {
        // Try as file path first
        const { stdout: fileOut } = await exec(
          script("extract-text.sh"),
          [html],
          {
            timeout: 10_000,
            maxBuffer: 5 * 1024 * 1024,
            env: { ...process.env, PATH: process.env.PATH },
          }
        );
        stdout = fileOut;
      } catch {
        // Fall back to stdin pipe — treat html as inline content
        const { stdout: pipeOut } = await exec(
          script("extract-text.sh"),
          [],
          {
            timeout: 10_000,
            maxBuffer: 5 * 1024 * 1024,
            input: html,
            env: { ...process.env, PATH: process.env.PATH },
          }
        );
        stdout = pipeOut;
      }

      return {
        content: [{ type: "text", text: stdout }],
        details: {},
      };
    },
  });
}
```

**Key design decisions in the extension:**

- Wraps existing shell scripts via `execFile` — no reimplementation, scripts remain the source of truth
- Passes `PATH` env explicitly so `ddgr` and `lightpanda` are found
- Timeouts match or exceed script defaults with buffer
- `extract_text` tries file path first, falls back to stdin for inline HTML
- `search_web` always uses `--json` and returns raw JSON (agent parses it better than formatted text)
- Tool descriptions and guidelines explicitly say "use this instead of raw ddgr/curl" to steer the agent

#### 2. `package.json` (new)

Make the skill installable as a Pi package with bundled extension.

**Path:** `<skill-dir>/package.json`

```json
{
  "name": "web-search-skill",
  "version": "2.0.0",
  "description": "Pi skill for web search via DuckDuckGo + Lightpanda JS rendering. Registers search_web, fetch_url, and extract_text as first-class agent tools.",
  "license": "MIT",
  "pi": {
    "extensions": ["./extension.ts"],
    "skills": ["."]
  }
}
```

Note: no `dependencies` needed because the extension uses only Node.js built-ins (`child_process`, `path`, `url`, `util`) and Pi-provided packages (`@earendil-works/pi-coding-agent`, `typebox`).

### Modified Files

#### 3. `SKILL.md` — rewrite for AI agent clarity

**Current:** ~300 lines mixing AI instructions, implementation spec, Python source code, design rationale.

**New:** ~55 lines. AI instructions only. Implementation spec moves to `SPEC.md`.

```markdown
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
```

Key changes from old SKILL.md:
- Frontmatter `description` mentions tools by name ("Registers search_web... Use these tools — never raw ddgr or curl")
- `allowed-tools` removed (no longer needed — tools are registered via extension)
- Quick tools table at top — the first thing agents see
- "Rules" section explicitly says NEVER use raw ddgr/curl
- Drops 250 lines of implementation spec → `SPEC.md`

#### 4. `SPEC.md` (renamed from old SKILL.md content)

Move the entire old SKILL.md body (from `## Architecture Overview` through `## Future Ideas`) into this file. Keep the content unchanged — it's already a good implementation spec.

**Path:** `<skill-dir>/SPEC.md`

Content: lines 24–299 of current SKILL.md (everything after the `---` frontmatter and `# Web Search` title line).

#### 5. `README.md` — update for v2 changes

Add Pi extension info to the README, update install instructions.

Changes:
- Add a "Tools" section between "Why" and "Installation" documenting the three registered tools
- Update installation to mention `pi install` for the package
- Add note that `npx skills add` still works but won't register tools (only loads SKILL.md)

### No Changes Needed

- `scripts/search.sh` — already supports `--json` flag, works correctly
- `scripts/fetch-url.sh` — already handles fallbacks, caching, error cases
- `scripts/extract-text.sh` — already works with file or stdin
- `scripts/search-and-read.sh` — still useful as CLI convenience, extension doesn't wrap it (agents compose `search_web` + `fetch_url` instead)
- `scripts/setup-lightpanda.sh` — unchanged

## Testing Plan

### Unit: Extension Tool Registration

In a Pi session with the extension loaded:

1. `search_web({ query: "pi coding agent hooks", num: 3 })` → returns JSON with 3 results
2. `search_web({ query: "nonexistent-xyzzy-12345" })` → returns "No results found for: ..."
3. `search_web({ query: "!w Claude AI", num: 1 })` → Wikipedia result
4. `fetch_url({ url: "example.com" })` → returns plain text (no HTML tags)
5. `fetch_url({ url: "https://httpstat.us/404" })` → handles error gracefully
6. `extract_text({ html: "<html><body><p>Hello</p><script>x=1</script></body></html>" })` → returns "Hello" (script stripped)
7. All three tools appear in `pi.getAllTools()` output

### Integration: No More Raw ddgr

In a real Pi session:

1. User asks "search for pi coding agent hooks" → agent calls `search_web`, not `bash ddgr`
2. User asks "read this page: https://example.com" → agent calls `fetch_url`, not `bash curl`
3. Agent combines: `search_web` then `fetch_url` on top result URLs
4. Agent never calls `bash ddgr` or `bash curl` for web operations

### Backward Compatibility

1. `npx skills add KakkoiDev/web-search-skill` still works (installs SKILL.md only)
2. Direct script execution still works: `./scripts/search.sh "query"`
3. `./scripts/search-and-read.sh "query"` still works
4. Extension tools and script CLI produce identical output

## Migration Notes

Users upgrading from v1 to v2:

1. `pi install` the package (or `npx skills add` + manually add extension to settings)
2. `/reload` in Pi to pick up the extension
3. Tools appear immediately in agent's available tools
4. No changes needed to `~/.pi/agent/settings.json` — extension auto-discovered if in extensions path

For users who only want SKILL.md (no tools):
- `npx skills add` still works as before
- Agents will see the skill instructions but need to call `search_web`/`fetch_url`/`extract_text` by name
- Without the extension, those tools won't be registered → agent falls back to script paths
- This is acceptable as a transitional state; the SKILL.md still guides the agent
