/**
 * @file Wiki sidebar navigation — uses @vscode-elements/elements.
 *
 * <vscode-textfield> for search, <vscode-tree> for nav tree.
 * No custom styling — all appearance inherited from VSCode theme.
 */

import "@vscode-elements/elements/dist/vscode-textfield/index.js";
import "@vscode-elements/elements/dist/vscode-tree/index.js";
import "@vscode-elements/elements/dist/vscode-tree-item/index.js";
import "@vscode-elements/elements/dist/vscode-icon/index.js";
import React, { useCallback, useEffect, useRef } from "react";
import type { WikiNavItem } from "@indexion/api-client";
import type { WikiToWebview, WikiFromWebview, WikiSearchHit } from "../../views/wiki/messages.ts";
import { usePostMessage, useWebviewReducer } from "../bridge/context.tsx";

// ─── Nav tree item (recursive) ──────────────────────────

const NavTreeItem = ({
  item,
  activePageId,
}: {
  readonly item: WikiNavItem;
  readonly activePageId: string | null;
}): React.JSX.Element => {
  const hasBranch = item.children.length > 0;
  return (
    <vscode-tree-item
      branch={hasBranch || undefined}
      open={hasBranch || undefined}
      active={item.id === activePageId || undefined}
      data-page-id={item.id}
    >
      <vscode-icon slot={hasBranch ? "icon-branch" : "icon-leaf"} name={hasBranch ? "folder" : "file"} />
      {item.title}
      {hasBranch &&
        item.children.map((child) => <NavTreeItem key={child.id} item={child} activePageId={activePageId} />)}
    </vscode-tree-item>
  );
};

// ─── State & reducer ────────────────────────────────────

type WikiState = {
  readonly nav: ReadonlyArray<WikiNavItem>;
  readonly activePageId: string | null;
  readonly searchQuery: string;
  readonly searchResults: ReadonlyArray<WikiSearchHit> | null;
  readonly navLoading: boolean;
  readonly searchLoading: boolean;
  readonly serverReady: boolean;
  readonly error: string | null;
};

const initialState: WikiState = {
  nav: [],
  activePageId: null,
  searchQuery: "",
  searchResults: null,
  navLoading: true,
  searchLoading: false,
  serverReady: false,
  error: null,
};

type WikiAction =
  | WikiToWebview
  | { readonly type: "setActivePageId"; readonly pageId: string }
  | { readonly type: "setSearchQuery"; readonly value: string }
  | { readonly type: "clearSearch" };

const wikiReducer = (state: WikiState, action: WikiAction): WikiState => {
  switch (action.type) {
    case "navLoaded":
      return { ...state, nav: action.nav.pages, navLoading: false };
    case "searchResults":
      return { ...state, searchResults: action.results, searchLoading: false };
    case "loading":
      if (action.target === "nav") {
        return { ...state, navLoading: true };
      }
      return { ...state, searchLoading: true };
    case "error":
      if (action.target === "nav") {
        return { ...state, error: action.message, navLoading: false };
      }
      return { ...state, error: action.message, searchLoading: false };
    case "serverStatus":
      return { ...state, serverReady: action.ready };
    case "setActivePageId":
      return { ...state, activePageId: action.pageId };
    case "setSearchQuery":
      if (!action.value) {
        return { ...state, searchQuery: "", searchResults: null };
      }
      return { ...state, searchQuery: action.value };
    case "clearSearch":
      return { ...state, searchQuery: "", searchResults: null };
    default:
      return state;
  }
};

// ─── Main component ─────────────────────────────────────

export const WikiPageApp = (): React.JSX.Element => {
  const postMessage = usePostMessage<WikiFromWebview>();
  const [state, dispatch] = useWebviewReducer(wikiReducer, initialState);
  const { nav, activePageId, searchQuery, searchResults, navLoading, searchLoading, serverReady, error } = state;
  const treeRef = useRef<HTMLElement>(null);

  const handleNavigate = useCallback(
    (pageId: string) => {
      dispatch({ type: "setActivePageId", pageId });
      postMessage({ type: "navigate", pageId });
    },
    [postMessage, dispatch],
  );

  // Listen for vsc-tree-select on the tree element via ref
  useEffect(() => {
    const el = treeRef.current;
    if (!el) {
      return;
    }
    const handler = (e: Event): void => {
      const detail = (e as CustomEvent).detail;
      const items = detail?.selectedItems as ReadonlyArray<HTMLElement> | undefined;
      if (!items || items.length === 0) {
        return;
      }
      const pageId = items[0]?.getAttribute("data-page-id");
      if (pageId) {
        handleNavigate(pageId);
      }
    };
    el.addEventListener("vsc-tree-select", handler);
    return () => el.removeEventListener("vsc-tree-select", handler);
  }, [handleNavigate]);

  const handleSearchKeyDown = useCallback(
    (e: React.KeyboardEvent) => {
      if (e.key === "Enter") {
        const trimmed = searchQuery.trim();
        if (trimmed) {
          postMessage({ type: "search", query: trimmed });
        }
      }
      if (e.key === "Escape") {
        dispatch({ type: "clearSearch" });
      }
    },
    [searchQuery, postMessage, dispatch],
  );

  const handleSearchInput = useCallback(
    (e: React.FormEvent) => {
      dispatch({ type: "setSearchQuery", value: (e.target as HTMLInputElement).value });
    },
    [dispatch],
  );

  const handleClearSearch = useCallback(() => {
    dispatch({ type: "clearSearch" });
  }, [dispatch]);

  return (
    <div style={{ display: "flex", flexDirection: "column", height: "100%" }}>
      <vscode-textfield
        placeholder="Search"
        value={searchQuery}
        disabled={!serverReady || undefined}
        onInput={handleSearchInput}
        onKeyDown={handleSearchKeyDown}
        style={{ margin: 0 }}
      />

      {!serverReady && !searchLoading && <StatusMsg>Server not ready</StatusMsg>}
      {navLoading && serverReady && <StatusMsg>Loading...</StatusMsg>}
      {error && !navLoading && <StatusMsg error>{error}</StatusMsg>}

      {searchResults !== null && (
        <SearchResultsView
          results={searchResults}
          activePageId={activePageId}
          onNavigate={handleNavigate}
          onClear={handleClearSearch}
        />
      )}

      {searchResults === null && !navLoading && !error && nav.length === 0 && <StatusMsg>No wiki pages</StatusMsg>}

      {searchResults === null && !navLoading && !error && nav.length > 0 && (
        <vscode-tree ref={treeRef} style={{ flex: 1, overflow: "auto" }}>
          {nav.map((item) => (
            <NavTreeItem key={item.id} item={item} activePageId={activePageId} />
          ))}
        </vscode-tree>
      )}
    </div>
  );
};

// ─── Search results ─────────────────────────────────────

const SearchResultsView = ({
  results,
  activePageId,
  onNavigate,
  onClear,
}: {
  readonly results: ReadonlyArray<WikiSearchHit>;
  readonly activePageId: string | null;
  readonly onNavigate: (pageId: string) => void;
  readonly onClear: () => void;
}): React.JSX.Element => (
  <div style={{ flex: 1, overflow: "auto" }}>
    <div
      style={{
        display: "flex",
        justifyContent: "space-between",
        padding: "2px 8px",
        fontSize: "11px",
        color: "var(--vscode-descriptionForeground)",
      }}
    >
      <span>{results.length} results</span>
      <button
        type="button"
        onClick={onClear}
        style={{
          background: "none",
          border: "none",
          color: "var(--vscode-textLink-foreground)",
          cursor: "pointer",
          fontSize: "11px",
          padding: 0,
        }}
      >
        Clear
      </button>
    </div>
    <vscode-tree>
      {results.map((hit) => (
        <vscode-tree-item key={hit.id} active={hit.id === activePageId || undefined} onClick={() => onNavigate(hit.id)}>
          <vscode-icon slot="icon-leaf" name="file" />
          {hit.title}
          {hit.snippet && <span slot="description">{hit.snippet}</span>}
        </vscode-tree-item>
      ))}
    </vscode-tree>
  </div>
);

// ─── Status message ─────────────────────────────────────

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
