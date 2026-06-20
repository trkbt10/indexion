/**
 * @file Wiki sidebar — filterable nav + search.
 *
 * Filter mental model:
 *   - Empty query → render the nav tree.
 *   - Non-empty query → submit on Enter, render search hits instead.
 * The same container and row styling apply in both modes so switching
 * between "list" and "search results" is just swapping the child view.
 *
 * Clicking a tree/hit row triggers the `navigate` message; the extension
 * host then calls the `indexion.wikiOpenPage` command.
 */

import React, { useCallback, useMemo } from "react";
import type { WikiNav, WikiNavItem } from "@indexion/api-client";
import type { WikiFromWebview, WikiToWebview, WikiSearchHit } from "../../views/wiki/messages.ts";
import { usePostMessage, useWebviewReducer } from "../bridge/context.tsx";
import { StatusMsg } from "../components/status-msg.tsx";
import { SearchBox } from "../components/search-box.tsx";
import { ResultSummary } from "../components/result-summary.tsx";
import { useTreeSelect } from "../components/use-tree-select.ts";
import layout from "../components/sidebar-layout.module.css";
import styles from "./wiki-sidebar.module.css";

// ─── State & reducer ────────────────────────────────────

type WikiState = {
  readonly nav: WikiNav | null;
  readonly query: string;
  readonly results: ReadonlyArray<WikiSearchHit> | null;
  readonly searching: boolean;
  readonly navLoading: boolean;
  readonly error: string | null;
  readonly notice: string | null;
  readonly serverReady: boolean;
};

const initialState: WikiState = {
  nav: null,
  query: "",
  results: null,
  searching: false,
  navLoading: false,
  error: null,
  notice: null,
  serverReady: false,
};

type WikiAction =
  | WikiToWebview
  | { readonly type: "setQuery"; readonly value: string }
  | { readonly type: "clearSearch" };

const wikiReducer = (state: WikiState, action: WikiAction): WikiState => {
  switch (action.type) {
    case "navLoaded":
      return { ...state, nav: action.nav, navLoading: false, error: null, notice: null };
    case "searchResults":
      return { ...state, results: action.results, searching: false, error: null, notice: null };
    case "searchUnavailable":
      return { ...state, results: [], searching: false, error: null, notice: action.message };
    case "loading":
      if (action.target === "nav") {
        return { ...state, navLoading: true, error: null, notice: null };
      }
      return { ...state, searching: true, error: null, notice: null };
    case "error":
      return {
        ...state,
        error: action.message,
        notice: null,
        searching: action.target === "search" ? false : state.searching,
        navLoading: action.target === "nav" ? false : state.navLoading,
      };
    case "serverStatus":
      return { ...state, serverReady: action.ready };
    case "setQuery":
      // Clear stale results as soon as the query becomes empty — the mental
      // model is "query = active filter".
      if (action.value.length === 0) {
        return { ...state, query: "", results: null, error: null, notice: null };
      }
      return { ...state, query: action.value, notice: null };
    case "clearSearch":
      return { ...state, query: "", results: null, error: null, notice: null };
    default:
      return state;
  }
};

// ─── Nav tree rendering ─────────────────────────────────

const NavTree = ({ items }: { readonly items: ReadonlyArray<WikiNavItem> }): React.JSX.Element => (
  <>
    {items.map((item) => {
      const hasChildren = item.children.length > 0;
      return (
        <vscode-tree-item key={item.id} data-page-id={item.id} open={hasChildren ? true : undefined}>
          <vscode-icon slot={hasChildren ? "icon-branch" : "icon-leaf"} name={hasChildren ? "folder" : "file"} />
          {hasChildren && <vscode-icon slot="icon-leaf" name="folder" />}
          {item.title}
          {hasChildren && <NavTree items={item.children} />}
        </vscode-tree-item>
      );
    })}
  </>
);

// ─── Component ──────────────────────────────────────────

export const WikiSidebarApp = (): React.JSX.Element => {
  const postMessage = usePostMessage<WikiFromWebview>();
  const [state, dispatch] = useWebviewReducer(wikiReducer, initialState);
  const { nav, query, results, searching, navLoading, error, notice, serverReady } = state;

  const trimmed = query.trim();
  const isFilterActive = trimmed.length > 0;

  const handleSubmit = useCallback(() => {
    if (trimmed.length === 0) {
      return;
    }
    postMessage({ type: "search", query: trimmed });
  }, [trimmed, postMessage]);

  const handleCancel = useCallback(() => {
    dispatch({ type: "clearSearch" });
  }, [dispatch]);

  const handleQueryChange = useCallback(
    (value: string) => {
      dispatch({ type: "setQuery", value });
    },
    [dispatch],
  );

  const openPage = useCallback(
    (pageId: string) => {
      postMessage({ type: "navigate", pageId });
    },
    [postMessage],
  );

  const treeRef = useTreeSelect(
    (data) => {
      const pageId = data["pageId"];
      if (pageId) {
        openPage(pageId);
      }
    },
    [openPage, nav, isFilterActive],
  );

  // Group hits by page so navigating through the section headings is natural
  // and the "N hits in M pages" summary is meaningful.
  const hitGroups = useMemo(() => {
    if (!results || results.length === 0) {
      return [];
    }
    const groups: Array<{ pageId: string; items: Array<WikiSearchHit> }> = [];
    const map = new Map<string, Array<WikiSearchHit>>();
    for (const hit of results) {
      const existing = map.get(hit.pageId);
      if (existing) {
        existing.push(hit);
      } else {
        const arr: Array<WikiSearchHit> = [hit];
        map.set(hit.pageId, arr);
        groups.push({ pageId: hit.pageId, items: arr });
      }
    }
    return groups;
  }, [results]);

  const hitCount = results?.length ?? 0;
  const pageCount = hitGroups.length;
  const hasResults = hitCount > 0;
  const awaitingSearch = isFilterActive && results === null && !searching && !error;

  return (
    <div className={layout.sidebarRoot}>
      <SearchBox<never>
        value={query}
        onChange={handleQueryChange}
        onSubmit={handleSubmit}
        onCancel={handleCancel}
        placeholder="Filter pages or press Enter to search…"
        disabled={!serverReady}
        clearable
      />

      {searching && <vscode-progress-bar indeterminate />}

      {!serverReady && <StatusMsg>Waiting for indexion server…</StatusMsg>}
      {error && <StatusMsg error>{error}</StatusMsg>}
      {notice && <StatusMsg>{notice}</StatusMsg>}

      {!isFilterActive && (
        <>
          {navLoading && !nav && <StatusMsg>Loading pages…</StatusMsg>}
          {nav && nav.pages.length === 0 && !navLoading && <StatusMsg>No wiki pages.</StatusMsg>}
          {nav && nav.pages.length > 0 && (
            <vscode-tree ref={treeRef} className={layout.scrollableTree}>
              <NavTree items={nav.pages} />
            </vscode-tree>
          )}
        </>
      )}

      {isFilterActive && (
        <>
          {awaitingSearch && <StatusMsg>Press Enter to search the wiki.</StatusMsg>}
          {!searching && !error && !notice && results !== null && !hasResults && (
            <StatusMsg>No matches for "{trimmed}".</StatusMsg>
          )}
          {hasResults && (
            <>
              <ResultSummary onClear={handleCancel}>
                {hitCount} hit{hitCount === 1 ? "" : "s"} in {pageCount} page{pageCount === 1 ? "" : "s"}
              </ResultSummary>
              <vscode-tree ref={treeRef} className={layout.scrollableTree}>
                {hitGroups.map((group) => (
                  <vscode-tree-item key={group.pageId} open data-page-id={group.pageId}>
                    <vscode-icon slot="icon-branch" name="book" />
                    <vscode-icon slot="icon-leaf" name="book" />
                    {group.pageId}
                    <vscode-badge slot="decoration">{group.items.length}</vscode-badge>
                    {group.items.map((hit) => (
                      <vscode-tree-item key={hit.sectionId} data-page-id={hit.pageId}>
                        <vscode-icon slot="icon-leaf" name="symbol-string" />
                        <span className={styles.hitTitle}>{hit.title}</span>
                        {hit.snippet && <span slot="description">{hit.snippet}</span>}
                        {hit.score > 0 && <vscode-badge slot="decoration">{Math.round(hit.score * 100)}%</vscode-badge>}
                      </vscode-tree-item>
                    ))}
                  </vscode-tree-item>
                ))}
              </vscode-tree>
            </>
          )}
        </>
      )}
    </div>
  );
};
