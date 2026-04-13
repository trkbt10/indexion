/**
 * @file Search sidebar — semantic code search via digest index.
 *
 * Searches functions by purpose description.
 * Example: "parse configuration" finds functions that parse config files.
 */

import "@vscode-elements/elements/dist/vscode-textfield/index.js";
import "@vscode-elements/elements/dist/vscode-tree/index.js";
import "@vscode-elements/elements/dist/vscode-tree-item/index.js";
import "@vscode-elements/elements/dist/vscode-icon/index.js";
import "@vscode-elements/elements/dist/vscode-badge/index.js";
import React, { useCallback } from "react";
import type { SearchToWebview, SearchFromWebview, SearchResultItem } from "../../views/search/messages.ts";
import { usePostMessage, useWebviewReducer } from "../bridge/context.tsx";

// ─── State & reducer ────────────────────────────────────

type SearchState = {
  readonly query: string;
  readonly results: ReadonlyArray<SearchResultItem>;
  readonly searched: boolean;
  readonly searching: boolean;
  readonly error: string | null;
  readonly serverReady: boolean;
};

const initialState: SearchState = {
  query: "",
  results: [],
  searched: false,
  searching: false,
  error: null,
  serverReady: false,
};

type SearchAction =
  | SearchToWebview
  | { readonly type: "setQuery"; readonly value: string }
  | { readonly type: "clearSearch" };

const searchReducer = (state: SearchState, action: SearchAction): SearchState => {
  switch (action.type) {
    case "results":
      return { ...state, results: action.items, searching: false, searched: true, error: null };
    case "searching":
      return { ...state, searching: true, error: null };
    case "error":
      return { ...state, error: action.message, searching: false, searched: true };
    case "serverStatus":
      return { ...state, serverReady: action.ready };
    case "setQuery":
      return { ...state, query: action.value };
    case "clearSearch":
      return { ...state, query: "", results: [], searched: false };
    default:
      return state;
  }
};

// ─── Component ──────────────────────────────────────────

export const SearchApp = (): React.JSX.Element => {
  const postMessage = usePostMessage<SearchFromWebview>();
  const [state, dispatch] = useWebviewReducer(searchReducer, initialState);
  const { query, results, searched, searching, error, serverReady } = state;

  const handleKeyDown = useCallback(
    (e: React.KeyboardEvent) => {
      if (e.key === "Enter") {
        const trimmed = query.trim();
        if (trimmed) {
          postMessage({ type: "search", query: trimmed });
        }
      }
      if (e.key === "Escape") {
        dispatch({ type: "clearSearch" });
      }
    },
    [query, postMessage, dispatch],
  );

  const handleInput = useCallback(
    (e: React.FormEvent) => {
      dispatch({ type: "setQuery", value: (e.target as HTMLInputElement).value });
    },
    [dispatch],
  );

  const handleResultClick = useCallback(
    (item: SearchResultItem) => {
      if (item.filePath) {
        postMessage({ type: "openFile", filePath: item.filePath, line: item.line });
      }
    },
    [postMessage],
  );

  return (
    <div style={{ display: "flex", flexDirection: "column", height: "100%" }}>
      <vscode-textfield
        placeholder="Describe what you're looking for..."
        value={query}
        disabled={!serverReady || undefined}
        onInput={handleInput}
        onKeyDown={handleKeyDown}
        style={{ margin: 0 }}
      />

      {!serverReady && !searching && <StatusMsg>Waiting for indexion server...</StatusMsg>}

      {serverReady && !searching && !searched && (
        <StatusMsg>Search functions by purpose. Enter a description and press Enter.</StatusMsg>
      )}

      {searching && <StatusMsg>Searching...</StatusMsg>}
      {error && <StatusMsg error>{error}</StatusMsg>}

      {searched && !searching && !error && results.length === 0 && <StatusMsg>No matching functions found.</StatusMsg>}

      {results.length > 0 && (
        <>
          <div style={{ padding: "2px 8px", fontSize: "11px", color: "var(--vscode-descriptionForeground)" }}>
            {results.length} results
          </div>
          <vscode-tree style={{ flex: 1, overflow: "auto" }}>
            {results.map((item, i) => (
              <vscode-tree-item key={i} onClick={() => handleResultClick(item)}>
                <vscode-icon slot="icon-leaf" name="symbol-method" />
                {item.label}
                <span slot="description">{item.description}</span>
                {item.score !== undefined && (
                  <vscode-badge slot="decoration">{Math.round(item.score * 100)}%</vscode-badge>
                )}
              </vscode-tree-item>
            ))}
          </vscode-tree>
        </>
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
