/**
 * @file Explore sidebar — uses @vscode-elements/elements.
 *
 * Threshold slider, strategy selector, directory picker,
 * and results displayed in <vscode-tree>.
 */

import "@vscode-elements/elements/dist/vscode-textfield/index.js";
import "@vscode-elements/elements/dist/vscode-button/index.js";
import "@vscode-elements/elements/dist/vscode-single-select/index.js";
import "@vscode-elements/elements/dist/vscode-option/index.js";
import "@vscode-elements/elements/dist/vscode-tree/index.js";
import "@vscode-elements/elements/dist/vscode-tree-item/index.js";
import "@vscode-elements/elements/dist/vscode-icon/index.js";
import "@vscode-elements/elements/dist/vscode-badge/index.js";
import "@vscode-elements/elements/dist/vscode-label/index.js";
import React, { useCallback } from "react";
import type { SimilarityPair, ComparisonStrategy } from "@indexion/api-client";
import type { ExploreToWebview, ExploreFromWebview } from "../../views/explore/messages.ts";
import { usePostMessage, useWebviewReducer } from "../bridge/context.tsx";

const STRATEGIES: ReadonlyArray<ComparisonStrategy> = ["tfidf", "hybrid", "apted", "tsed", "ncd"];

// ─── State & reducer ────────────────────────────────────

type ExploreState = {
  readonly threshold: number;
  readonly strategy: ComparisonStrategy;
  readonly targetDir: string;
  readonly pairs: ReadonlyArray<SimilarityPair>;
  readonly fileCount: number;
  readonly searching: boolean;
  readonly error: string | null;
  readonly serverReady: boolean;
};

const initialState: ExploreState = {
  threshold: 0.7,
  strategy: "tfidf",
  targetDir: "",
  pairs: [],
  fileCount: 0,
  searching: false,
  error: null,
  serverReady: false,
};

type ExploreAction =
  | ExploreToWebview
  | { readonly type: "setThreshold"; readonly value: number }
  | { readonly type: "setStrategy"; readonly value: ComparisonStrategy };

const exploreReducer = (state: ExploreState, action: ExploreAction): ExploreState => {
  switch (action.type) {
    case "results":
      return { ...state, pairs: action.pairs, fileCount: action.fileCount, searching: false, error: null };
    case "searching":
      return { ...state, searching: true, error: null };
    case "error":
      return { ...state, error: action.message, searching: false };
    case "directoryPicked":
      return { ...state, targetDir: action.path };
    case "serverStatus":
      return { ...state, serverReady: action.ready };
    case "config":
      return { ...state, threshold: action.threshold, strategy: action.strategy };
    case "setThreshold":
      return { ...state, threshold: action.value };
    case "setStrategy":
      return { ...state, strategy: action.value };
    default:
      return state;
  }
};

// ─── Component ──────────────────────────────────────────

export const ExploreApp = (): React.JSX.Element => {
  const postMessage = usePostMessage<ExploreFromWebview>();
  const [state, dispatch] = useWebviewReducer(exploreReducer, initialState);
  const { threshold, strategy, targetDir, pairs, fileCount, searching, error, serverReady } = state;

  const handleRun = useCallback(() => {
    if (!targetDir) {
      return;
    }
    postMessage({ type: "run", threshold, strategy, targetDir });
  }, [postMessage, threshold, strategy, targetDir]);

  const handleOpenDiff = useCallback(
    (pair: SimilarityPair) => {
      postMessage({ type: "openDiff", file1: pair.file1, file2: pair.file2 });
    },
    [postMessage],
  );

  const handlePickDir = useCallback(() => {
    postMessage({ type: "pickDirectory" });
  }, [postMessage]);

  const basename = (path: string): string => {
    const parts = path.split("/");
    return parts[parts.length - 1] ?? path;
  };

  return (
    <div style={{ display: "flex", flexDirection: "column", height: "100%", gap: "4px" }}>
      {/* Controls */}
      <div
        style={{
          display: "flex",
          flexDirection: "column",
          gap: "4px",
          padding: "4px 0",
          borderBottom: "1px solid var(--vscode-panel-border)",
        }}
      >
        <div style={{ display: "flex", gap: "4px" }}>
          <vscode-textfield placeholder="Select directory..." value={targetDir} readonly style={{ flex: 1 }} />
          <vscode-button onClick={handlePickDir} style={{ flexShrink: 0 }}>
            ...
          </vscode-button>
        </div>

        <div style={{ display: "flex", alignItems: "center", gap: "4px", padding: "0 2px" }}>
          <vscode-label style={{ fontSize: "11px", flexShrink: 0 }}>
            Threshold: {Math.round(threshold * 100)}%
          </vscode-label>
          <input
            type="range"
            min={0}
            max={100}
            value={Math.round(threshold * 100)}
            onChange={(e) => dispatch({ type: "setThreshold", value: Number(e.target.value) / 100 })}
            style={{ flex: 1, accentColor: "var(--vscode-button-background)" }}
          />
        </div>

        <vscode-single-select
          value={strategy}
          onChange={(e: React.FormEvent) =>
            dispatch({ type: "setStrategy", value: (e.target as HTMLSelectElement).value as ComparisonStrategy })
          }
        >
          {STRATEGIES.map((s) => (
            <vscode-option key={s} value={s}>
              {s}
            </vscode-option>
          ))}
        </vscode-single-select>

        <vscode-button onClick={handleRun} disabled={!serverReady || !targetDir || searching || undefined}>
          {searching ? "Analyzing..." : "Run Explore"}
        </vscode-button>
      </div>

      {/* Status */}
      {!serverReady && <StatusMsg>Server not ready</StatusMsg>}
      {error && <StatusMsg error>{error}</StatusMsg>}
      {pairs.length > 0 && (
        <div style={{ padding: "2px 8px", fontSize: "11px", color: "var(--vscode-descriptionForeground)" }}>
          {pairs.length} pairs in {fileCount} files
        </div>
      )}

      {/* Results */}
      {pairs.length > 0 && (
        <vscode-tree style={{ flex: 1, overflow: "auto" }}>
          {pairs.map((pair, i) => (
            <vscode-tree-item key={i} onClick={() => handleOpenDiff(pair)}>
              <vscode-icon slot="icon-leaf" name="diff" />
              {basename(pair.file1)} ↔ {basename(pair.file2)}
              <vscode-badge slot="decoration">{Math.round(pair.similarity * 100)}%</vscode-badge>
              <span slot="description">{pair.file1}</span>
            </vscode-tree-item>
          ))}
        </vscode-tree>
      )}
    </div>
  );
};

const StatusMsg = ({
  children,
  error: isError,
}: {
  readonly children: React.ReactNode;
  readonly error?: boolean;
}): React.JSX.Element => (
  <div
    style={{
      padding: "8px",
      textAlign: "center",
      fontSize: "12px",
      color: isError ? "var(--vscode-errorForeground)" : "var(--vscode-descriptionForeground)",
    }}
  >
    {children}
  </div>
);
