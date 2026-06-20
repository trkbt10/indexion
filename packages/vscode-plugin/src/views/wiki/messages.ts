/**
 * @file Message types for the wiki sidebar WebviewView.
 *
 * The wiki sidebar has two interchangeable views:
 *   - Navigation tree (shown when the filter is empty)
 *   - Search results (shown when the filter is non-empty)
 *
 * Page content is opened in a separate editor-area WebviewPanel via the
 * `indexion.wikiOpenPage` command.
 */

import type { WikiNav } from "@indexion/api-client";

/** Messages from extension host to wiki sidebar webview. */
export type WikiToWebview =
  | { readonly type: "navLoaded"; readonly nav: WikiNav }
  | { readonly type: "searchResults"; readonly results: ReadonlyArray<WikiSearchHit> }
  | { readonly type: "searchUnavailable"; readonly message: string }
  | { readonly type: "loading"; readonly target: "nav" | "search" }
  | { readonly type: "error"; readonly message: string; readonly target: "nav" | "search" }
  | { readonly type: "serverStatus"; readonly ready: boolean };

/** Messages from wiki sidebar webview to extension host. */
export type WikiFromWebview =
  | { readonly type: "requestNav" }
  | { readonly type: "navigate"; readonly pageId: string }
  | { readonly type: "search"; readonly query: string };

/**
 * A single wiki search hit — a section inside a page.
 *
 * Page-level navigation uses `pageId`; a future revision may use
 * `sectionId` to scroll the opened page to the matching section.
 */
export type WikiSearchHit = {
  readonly pageId: string;
  readonly sectionId: string;
  readonly title: string;
  readonly snippet: string;
  readonly level: number;
  readonly score: number;
};

/**
 * Convert raw wiki search API response to typed hits.
 *
 * Server shape: `{ section: { id, title, content, page_id, level }, score }`
 * Tolerant to missing fields so a partial/older server doesn't break the UI.
 */
export const toWikiSearchHits = (raw: ReadonlyArray<Record<string, unknown>>): ReadonlyArray<WikiSearchHit> =>
  raw.map((hit) => {
    const section = (hit["section"] ?? {}) as Record<string, unknown>;
    const content = typeof section["content"] === "string" ? (section["content"] as string) : "";
    return {
      pageId: String(section["page_id"] ?? ""),
      sectionId: String(section["id"] ?? ""),
      title: String(section["title"] ?? section["page_id"] ?? ""),
      snippet: buildSnippet(content),
      level: typeof section["level"] === "number" ? (section["level"] as number) : 0,
      score: typeof hit["score"] === "number" ? (hit["score"] as number) : 0,
    };
  });

/** Collapse whitespace and truncate to a single-line preview. */
const SNIPPET_MAX = 120;
const buildSnippet = (content: string): string => {
  const oneLine = content.replace(/\s+/g, " ").trim();
  if (oneLine.length <= SNIPPET_MAX) {
    return oneLine;
  }
  return oneLine.slice(0, SNIPPET_MAX - 1) + "…";
};
