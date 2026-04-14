/**
 * @file Unified search sidebar — supports search, grep, and digest modes.
 *
 * Layout:
 *   [search icon] [input field] [mode toggle icons]
 *   [progress bar when searching]
 *   [result summary + clear]
 *   [result tree]
 *
 * Mode toggles work like VSCode's search options (case, word, regex) —
 * icon buttons that toggle active state.
 */

import React, { useCallback, useRef, useEffect } from "react";
import type { SearchToWebview, SearchFromWebview, SearchResultItem, SearchMode } from "../../views/search/messages.ts";
import { usePostMessage, useWebviewReducer } from "../bridge/context.tsx";
import { StatusMsg } from "../components/status-msg.tsx";
import layout from "../components/sidebar-layout.module.css";
import styles from "./app.module.css";

const basename = (path: string): string => {
  const i = path.lastIndexOf("/");
  return i >= 0 ? path.slice(i + 1) : path;
};

const dirname = (path: string): string => {
  const i = path.lastIndexOf("/");
  return i >= 0 ? path.slice(0, i) : "";
};

// ─── State & reducer ────────────────────────────────────

type SearchState = {
  readonly mode: SearchMode;
  readonly query: string;
  readonly results: ReadonlyArray<SearchResultItem>;
  readonly searched: boolean;
  readonly searching: boolean;
  readonly progressDetail: string | null;
  readonly error: string | null;
  readonly serverReady: boolean;
};

const initialState: SearchState = {
  mode: "search",
  query: "",
  results: [],
  searched: false,
  searching: false,
  progressDetail: null,
  error: null,
  serverReady: false,
};

type SearchAction =
  | SearchToWebview
  | { readonly type: "setMode"; readonly value: SearchMode }
  | { readonly type: "setQuery"; readonly value: string }
  | { readonly type: "clearSearch" };

const searchReducer = (state: SearchState, action: SearchAction): SearchState => {
  switch (action.type) {
    case "results":
      return {
        ...state,
        results: action.items,
        searching: false,
        searched: true,
        progressDetail: null,
        error: null,
      };
    case "appendItems":
      return { ...state, results: [...state.results, ...action.items], searched: true };
    case "searching":
      return {
        ...state,
        searching: true,
        error: null,
        progressDetail: null,
        results: [],
        searched: false,
      };
    case "progress":
      return { ...state, progressDetail: action.detail };
    case "done":
      return { ...state, searching: false, searched: true, progressDetail: null };
    case "error":
      return { ...state, error: action.message, searching: false, searched: true, progressDetail: null };
    case "serverStatus":
      return { ...state, serverReady: action.ready };
    case "setMode":
      return {
        ...state,
        mode: action.value,
        results: [],
        searched: false,
        searching: false,
        error: null,
        progressDetail: null,
      };
    case "setQuery":
      return { ...state, query: action.value };
    case "clearSearch":
      return {
        ...state,
        query: "",
        results: [],
        searched: false,
        error: null,
        progressDetail: null,
      };
    default:
      return state;
  }
};

// ─── Mode definitions ───────────────────────────────────

type ModeInfo = {
  readonly id: SearchMode;
  readonly icon: string;
  readonly title: string;
  readonly placeholder: string;
};

const MODES: ReadonlyArray<ModeInfo> = [
  { id: "search", icon: "search", title: "Semantic Search", placeholder: "Search code, wiki, docs..." },
  { id: "grep", icon: "regex", title: "KGF Token Grep", placeholder: "Token pattern (e.g. pub fn Ident)..." },
  { id: "digest", icon: "symbol-method", title: "Search by Purpose", placeholder: "Describe function purpose..." },
];

const findMode = (id: SearchMode): ModeInfo => MODES.find((m) => m.id === id) ?? MODES[0];

// ─── Component ──────────────────────────────────────────

export const SearchApp = (): React.JSX.Element => {
  const postMessage = usePostMessage<SearchFromWebview>();
  const [state, dispatch] = useWebviewReducer(searchReducer, initialState);
  const { mode, query, results, searched, searching, progressDetail, error, serverReady } = state;

  const currentMode = findMode(mode);

  const handleSubmit = useCallback(() => {
    const trimmed = query.trim();
    if (!trimmed) {
      return;
    }
    switch (mode) {
      case "search":
        postMessage({ type: "search", query: trimmed });
        break;
      case "grep":
        postMessage({ type: "grep", pattern: trimmed });
        break;
      case "digest":
        postMessage({ type: "digest", query: trimmed });
        break;
    }
  }, [mode, query, postMessage]);

  const handleKeyDown = useCallback(
    (e: React.KeyboardEvent) => {
      if (e.key === "Enter") {
        handleSubmit();
      }
      if (e.key === "Escape") {
        dispatch({ type: "clearSearch" });
      }
    },
    [handleSubmit, dispatch],
  );

  const handleInput = useCallback(
    (e: React.ChangeEvent<HTMLInputElement>) => {
      dispatch({ type: "setQuery", value: e.target.value });
    },
    [dispatch],
  );

  const toggleMode = useCallback(
    (id: SearchMode) => {
      dispatch({ type: "setMode", value: id });
    },
    [dispatch],
  );

  // Listen for vsc-tree-select events on the tree element.
  // vscode-tree-item internally calls stopPropagation on click,
  // so React onClick never fires. The correct API is vsc-tree-select.
  // Ref to the vscode-tree custom element for listening to vsc-tree-select events.
  // Typed as HTMLElement because vscode-elements' VscodeTree type is too strict for ref assignment.
  const treeRef = useRef<HTMLElement | null>(null);
  useEffect(() => {
    const el = treeRef.current;
    if (!el) {
      return;
    }
    const handler = (e: Event): void => {
      const detail = (e as CustomEvent).detail as ReadonlyArray<HTMLElement> | undefined;
      if (!detail || detail.length === 0) {
        return;
      }
      const selected = detail[0];
      const filePath = selected.getAttribute("data-file-path");
      const lineAttr = selected.getAttribute("data-line");
      if (filePath) {
        const line = lineAttr ? Number(lineAttr) : undefined;
        postMessage({ type: "openFile", filePath, line });
      }
    };
    el.addEventListener("vsc-tree-select", handler);
    return () => {
      el.removeEventListener("vsc-tree-select", handler);
    };
    // Re-run when results change — tree mounts only when results exist.
  }, [postMessage, results]);

  const hasResults = results.length > 0;
  const resultCount = results.length;

  // Group results by file for tree display
  const fileGroups = React.useMemo(() => {
    if (results.length === 0) {
      return [];
    }
    const groups: Array<{ file: string; items: ReadonlyArray<SearchResultItem> }> = [];
    const map = new Map<string, Array<SearchResultItem>>();
    const order: Array<string> = [];
    for (const item of results) {
      const key = item.filePath ?? "";
      const existing = map.get(key);
      if (existing) {
        existing.push(item);
      } else {
        const arr: Array<SearchResultItem> = [item];
        map.set(key, arr);
        order.push(key);
      }
    }
    for (const key of order) {
      groups.push({ file: key, items: map.get(key)! });
    }
    return groups;
  }, [results]);

  const fileCount = fileGroups.length;

  return (
    <div className={layout.sidebarRoot}>
      {/* ── Search input composite (icon + input + toggle buttons in one border) ── */}
      <div className={styles.searchBox}>
        <span className={styles.searchBoxIcon}>
          <vscode-icon name="search" size={16} />
        </span>
        <input
          type="text"
          className={styles.searchInput}
          placeholder={currentMode.placeholder}
          value={query}
          disabled={!serverReady}
          onChange={handleInput}
          onKeyDown={handleKeyDown}
        />
        <div className={styles.modeToggles}>
          {MODES.map((m) => (
            <button
              key={m.id}
              type="button"
              title={m.title}
              className={`${styles.modeToggle} ${mode === m.id ? styles.modeToggleActive : ""}`}
              onClick={() => toggleMode(m.id)}
            >
              <vscode-icon name={m.icon} size={14} />
            </button>
          ))}
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
      {searched && !searching && !error && !hasResults && <StatusMsg>No results found.</StatusMsg>}

      {/* ── Result summary ── */}
      {hasResults && (
        <div className={layout.resultSummarySpaced}>
          <span>
            {resultCount} results in {fileCount} files
          </span>
          <button type="button" className={layout.textLinkButton} onClick={() => dispatch({ type: "clearSearch" })}>
            Clear
          </button>
        </div>
      )}

      {/* ── Results: grouped by file ── */}
      {fileGroups.length > 0 && (
        <vscode-tree
          ref={(el: unknown) => {
            treeRef.current = el as HTMLElement | null;
          }}
          className={layout.scrollableTree}
        >
          {fileGroups.map((group) => (
            <vscode-tree-item key={group.file} open data-file-path={group.file}>
              <vscode-icon slot="icon-branch" name="file" />
              <vscode-icon slot="icon-leaf" name="file" />
              {basename(group.file)}
              <span slot="description">{dirname(group.file)}</span>
              <vscode-badge slot="decoration">{group.items.length}</vscode-badge>
              {group.items.map((item, j) => (
                <vscode-tree-item key={j} data-file-path={item.filePath} data-line={item.line}>
                  <vscode-icon slot="icon-leaf" name="symbol-method" />
                  {item.label}
                  {item.score !== undefined && (
                    <vscode-badge slot="decoration">{Math.round(item.score * 100)}%</vscode-badge>
                  )}
                </vscode-tree-item>
              ))}
            </vscode-tree-item>
          ))}
        </vscode-tree>
      )}
    </div>
  );
};
