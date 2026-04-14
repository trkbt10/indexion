/**
 * @file Explore results panel — shows file similarity analysis results.
 *
 * Layout:
 *   [target path display]
 *   [threshold slider] [strategy selector] [Run button]
 *   [progress bar when analyzing]
 *   [result summary + clear]
 *   [pair result tree with diff actions]
 *
 * Triggered from file explorer context menu ("Find Similar Files").
 * Opens as a WebviewPanel in the editor area.
 */

import React, { useCallback, useEffect, useRef } from "react";
import type { ComparisonStrategy } from "@indexion/api-client";
import type { ExploreToWebview, ExploreFromWebview, ExplorePairItem } from "../../views/explore/messages.ts";
import { usePostMessage, useWebviewReducer } from "../bridge/context.tsx";
import { StatusMsg } from "../components/status-msg.tsx";
import styles from "./app.module.css";

const STRATEGIES: ReadonlyArray<ComparisonStrategy> = ["tfidf", "hybrid", "apted", "tsed", "ncd"];

const basename = (path: string): string => {
  const i = path.lastIndexOf("/");
  return i >= 0 ? path.slice(i + 1) : path;
};

const dirname = (path: string): string => {
  const i = path.lastIndexOf("/");
  return i >= 0 ? path.slice(0, i) : "";
};

// ─── State & reducer ────────────────────────────────────

type ExploreState = {
  readonly targetPath: string;
  readonly threshold: number;
  readonly strategy: ComparisonStrategy;
  readonly pairs: ReadonlyArray<ExplorePairItem>;
  readonly fileCount: number;
  readonly searched: boolean;
  readonly searching: boolean;
  readonly progressDetail: string | null;
  readonly error: string | null;
  readonly serverReady: boolean;
  readonly autoRunVersion: number;
};

const initialState: ExploreState = {
  targetPath: "",
  threshold: 0.7,
  strategy: "tfidf",
  pairs: [],
  fileCount: 0,
  searched: false,
  searching: false,
  progressDetail: null,
  error: null,
  serverReady: false,
  autoRunVersion: 0,
};

type ExploreAction =
  | ExploreToWebview
  | { readonly type: "setThreshold"; readonly value: number }
  | { readonly type: "setStrategy"; readonly value: ComparisonStrategy }
  | { readonly type: "clearResults" };

const exploreReducer = (state: ExploreState, action: ExploreAction): ExploreState => {
  switch (action.type) {
    case "config":
      return {
        ...state,
        threshold: action.threshold,
        strategy: action.strategy,
        targetPath: action.targetPath,
        autoRunVersion: state.autoRunVersion + 1,
      };
    case "searching":
      return {
        ...state,
        searching: true,
        error: null,
        progressDetail: null,
        pairs: [],
        fileCount: 0,
        searched: false,
      };
    case "progress":
      return { ...state, progressDetail: action.detail };
    case "exploreResults":
      return {
        ...state,
        pairs: action.pairs,
        fileCount: action.fileCount,
        searching: false,
        searched: true,
        progressDetail: null,
        error: null,
      };
    case "done":
      return { ...state, searching: false, progressDetail: null };
    case "error":
      return { ...state, error: action.message, searching: false, searched: true, progressDetail: null };
    case "serverStatus":
      return { ...state, serverReady: action.ready };
    case "setThreshold":
      return { ...state, threshold: action.value };
    case "setStrategy":
      return { ...state, strategy: action.value };
    case "clearResults":
      return { ...state, pairs: [], fileCount: 0, searched: false, error: null, progressDetail: null };
    default:
      return state;
  }
};

// ─── Component ──────────────────────────────────────────

export const ExploreApp = (): React.JSX.Element => {
  const postMessage = usePostMessage<ExploreFromWebview>();
  const [state, dispatch] = useWebviewReducer(exploreReducer, initialState);
  const {
    targetPath,
    threshold,
    strategy,
    pairs,
    fileCount,
    searched,
    searching,
    progressDetail,
    error,
    serverReady,
    autoRunVersion,
  } = state;

  const handleRun = useCallback(() => {
    if (!targetPath || !serverReady) {
      return;
    }
    postMessage({ type: "explore", threshold, strategy, targetPath });
  }, [targetPath, threshold, strategy, serverReady, postMessage]);

  // Auto-run when config arrives (panel just opened with a target)
  const prevAutoRunVersion = useRef(0);
  useEffect(() => {
    if (autoRunVersion > prevAutoRunVersion.current && targetPath && serverReady) {
      prevAutoRunVersion.current = autoRunVersion;
      postMessage({ type: "explore", threshold, strategy, targetPath });
    }
  }, [autoRunVersion, targetPath, serverReady, threshold, strategy, postMessage]);

  const handleOpenDiff = useCallback(
    (pair: ExplorePairItem) => {
      postMessage({ type: "openDiff", file1: pair.file1, file2: pair.file2 });
    },
    [postMessage],
  );

  const handleOpenFile = useCallback(
    (filePath: string) => {
      postMessage({ type: "openFile", filePath });
    },
    [postMessage],
  );

  const hasResults = pairs.length > 0;

  return (
    <div className={styles.root}>
      {/* ── Target path ── */}
      <div className={styles.header}>
        <vscode-icon name="file-code" size={16} />
        <span className={styles.targetPath} title={targetPath}>
          {targetPath ? basename(targetPath) : "No target selected"}
        </span>
        <span className={styles.targetDir}>{targetPath ? dirname(targetPath) : ""}</span>
      </div>

      {/* ── Controls ── */}
      <div className={styles.controls}>
        <div className={styles.controlRow}>
          <vscode-label className={styles.controlLabel}>Threshold: {Math.round(threshold * 100)}%</vscode-label>
          <input
            type="range"
            min={0}
            max={100}
            value={Math.round(threshold * 100)}
            onChange={(e) => dispatch({ type: "setThreshold", value: Number(e.target.value) / 100 })}
            className={styles.thresholdSlider}
          />
        </div>

        <div className={styles.controlRow}>
          <vscode-label className={styles.controlLabel}>Strategy:</vscode-label>
          <vscode-single-select
            value={strategy}
            className={styles.strategySelect}
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

          <vscode-button onClick={handleRun} disabled={!serverReady || !targetPath || searching || undefined}>
            {searching ? "Analyzing..." : "Run"}
          </vscode-button>
        </div>
      </div>

      {/* ── Progress indicator ── */}
      {searching && <vscode-progress-bar indeterminate className={styles.progressBar} />}
      {searching && progressDetail && <div className={styles.progressDetail}>{progressDetail}</div>}

      {/* ── Status messages ── */}
      {!serverReady && !searching && (
        <StatusMsg>Waiting for indexion server... Check the Output panel (indexion) for details.</StatusMsg>
      )}
      {error && <StatusMsg error>{error}</StatusMsg>}
      {searched && !searching && !error && !hasResults && <StatusMsg>No similar files found.</StatusMsg>}

      {/* ── Result summary ── */}
      {hasResults && (
        <div className={styles.resultSummary}>
          <span>
            {pairs.length} pairs in {fileCount} files
          </span>
          <button type="button" className={styles.clearButton} onClick={() => dispatch({ type: "clearResults" })}>
            Clear
          </button>
        </div>
      )}

      {/* ── Results: explore pairs ── */}
      {pairs.length > 0 && (
        <vscode-tree className={styles.resultTree}>
          {pairs.map((pair, i) => (
            <vscode-tree-item key={i} onClick={() => handleOpenDiff(pair)}>
              <vscode-icon slot="icon-branch" name="diff" />
              <vscode-icon slot="icon-leaf" name="diff" />
              {pair.label}
              <vscode-badge slot="decoration">{Math.round(pair.similarity * 100)}%</vscode-badge>
              <vscode-tree-item
                onClick={(e: React.MouseEvent) => {
                  e.stopPropagation();
                  handleOpenFile(pair.file1);
                }}
              >
                <vscode-icon slot="icon-leaf" name="file" />
                {basename(pair.file1)}
                <span slot="description">{dirname(pair.file1)}</span>
              </vscode-tree-item>
              <vscode-tree-item
                onClick={(e: React.MouseEvent) => {
                  e.stopPropagation();
                  handleOpenFile(pair.file2);
                }}
              >
                <vscode-icon slot="icon-leaf" name="file" />
                {basename(pair.file2)}
                <span slot="description">{dirname(pair.file2)}</span>
              </vscode-tree-item>
            </vscode-tree-item>
          ))}
        </vscode-tree>
      )}
    </div>
  );
};
