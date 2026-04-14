/**
 * @file Message types for the unified search WebviewView.
 *
 * Supports 3 search modes:
 * - search:  full-text/semantic search (runSearch)
 * - grep:    KGF token pattern search (runGrep)
 * - digest:  function search by purpose (queryDigest)
 */

import type { DigestMatch, SearchHit, GrepMatch } from "@indexion/api-client";

// ─── Search modes ──────────────────────────────────────

export type SearchMode = "search" | "grep" | "digest";

// ─── Unified result items ──────────────────────────────

/** A single result row displayable in the result tree. */
export type SearchResultItem = {
  readonly label: string;
  readonly description: string;
  readonly detail?: string;
  readonly filePath?: string;
  readonly line?: number;
  readonly score?: number;
  readonly icon: string;
};

// ─── Extension → Webview messages ──────────────────────

export type SearchToWebview =
  | { readonly type: "results"; readonly items: ReadonlyArray<SearchResultItem> }
  | { readonly type: "appendItems"; readonly items: ReadonlyArray<SearchResultItem> }
  | { readonly type: "searching" }
  | { readonly type: "progress"; readonly phase: string; readonly detail: string }
  | { readonly type: "done"; readonly total: number }
  | { readonly type: "error"; readonly message: string }
  | { readonly type: "serverStatus"; readonly ready: boolean };

// ─── Webview → Extension messages ──────────────────────

export type SearchFromWebview =
  | { readonly type: "search"; readonly query: string }
  | { readonly type: "digest"; readonly query: string }
  | { readonly type: "grep"; readonly pattern: string }
  | { readonly type: "openFile"; readonly filePath: string; readonly line?: number };

// ─── Converters ────────────────────────────────────────

/** Convert a SearchHit to a unified result item. */
export const searchHitToItem = (hit: SearchHit): SearchResultItem => ({
  label: hit.title,
  description: `${hit.source}${hit.line > 0 ? `:${hit.line}` : ""}`,
  detail: hit.kind,
  filePath: hit.source,
  line: hit.line,
  score: hit.score,
  icon: "symbol-file",
});

/** Convert a DigestMatch to a unified result item. */
export const digestMatchToItem = (match: DigestMatch): SearchResultItem => ({
  label: match.name,
  description: match.file,
  detail: match.summary,
  filePath: match.file,
  score: match.score,
  icon: "symbol-method",
});

/** Convert a GrepMatch to a unified result item. */
export const grepMatchToItem = (match: GrepMatch): SearchResultItem => ({
  label: match.name ?? match.matched ?? "(match)",
  description: `${match.file}:${match.line}`,
  detail: match.detail ?? match.kind,
  filePath: match.file,
  line: match.line,
  score: undefined,
  icon: "symbol-keyword",
});
