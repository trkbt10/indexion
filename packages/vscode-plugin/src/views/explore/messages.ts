/**
 * @file Message types for the explore results WebviewPanel.
 *
 * The explore panel shows similarity analysis results for a target file
 * or directory. It opens in the editor area (not sidebar) and is triggered
 * from the file explorer context menu.
 */

import type { ComparisonStrategy, SimilarityPair } from "@indexion/api-client";

// ─── Explore pair item ────────────────────────────────

/** A similarity pair displayable in the result tree. */
export type ExplorePairItem = {
  readonly file1: string;
  readonly file2: string;
  readonly similarity: number;
  readonly label: string;
};

// ─── Extension → Webview messages ──────────────────────

export type ExploreToWebview =
  | {
      readonly type: "config";
      readonly threshold: number;
      readonly strategy: ComparisonStrategy;
      readonly targetPath: string;
    }
  | { readonly type: "searching" }
  | { readonly type: "progress"; readonly phase: string; readonly detail: string }
  | { readonly type: "exploreResults"; readonly pairs: ReadonlyArray<ExplorePairItem>; readonly fileCount: number }
  | { readonly type: "done"; readonly total: number }
  | { readonly type: "error"; readonly message: string }
  | { readonly type: "serverStatus"; readonly ready: boolean };

// ─── Webview → Extension messages ──────────────────────

export type ExploreFromWebview =
  | { readonly type: "explore"; readonly threshold: number; readonly strategy: string; readonly targetPath: string }
  | { readonly type: "openFile"; readonly filePath: string }
  | { readonly type: "openDiff"; readonly file1: string; readonly file2: string };

// ─── Converters ────────────────────────────────────────

/** Convert a SimilarityPair to an explore pair item. */
export const similarityPairToItem = (pair: SimilarityPair): ExplorePairItem => {
  const basename = (path: string): string => {
    const parts = path.split("/");
    return parts[parts.length - 1] ?? path;
  };
  return {
    file1: pair.file1,
    file2: pair.file2,
    similarity: pair.similarity,
    label: `${basename(pair.file1)} ↔ ${basename(pair.file2)}`,
  };
};
