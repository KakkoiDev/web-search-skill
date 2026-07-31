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
