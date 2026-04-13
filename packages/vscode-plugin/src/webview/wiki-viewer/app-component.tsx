/**
 * @file Wiki page viewer — renders markdown content in the editor area.
 *
 * Uses `marked` to convert markdown to HTML. Styled to match VSCode's
 * built-in markdown preview (using the same CSS variables).
 */

import React, { useCallback, useEffect, useMemo, useRef } from "react";
import { marked } from "marked";
import type { WikiPage } from "@indexion/api-client";
import type { WikiPageToWebview, WikiPageFromWebview } from "../../panels/wiki-page/messages.ts";
import { usePostMessage, useWebviewReducer } from "../bridge/context.tsx";

/** Configure marked for safe rendering (no raw HTML pass-through). */
marked.setOptions({ async: false, gfm: true, breaks: false });

// ─── State & reducer ────────────────────────────────────

type WikiViewerState = {
  readonly page: WikiPage | null;
  readonly loading: boolean;
  readonly error: string | null;
  /** Monotonic counter incremented on each page load to trigger scroll reset. */
  readonly pageVersion: number;
};

const initialState: WikiViewerState = {
  page: null,
  loading: false,
  error: null,
  pageVersion: 0,
};

const wikiViewerReducer = (state: WikiViewerState, action: WikiPageToWebview): WikiViewerState => {
  switch (action.type) {
    case "pageLoaded":
      return { ...state, page: action.page, loading: false, error: null, pageVersion: state.pageVersion + 1 };
    case "loading":
      return { ...state, loading: true, error: null };
    case "error":
      return { ...state, error: action.message, loading: false };
    default:
      return state;
  }
};

// ─── Component ──────────────────────────────────────────

export const WikiViewerApp = (): React.JSX.Element => {
  const postMessage = usePostMessage<WikiPageFromWebview>();
  const [state] = useWebviewReducer(wikiViewerReducer, initialState);
  const { page, loading, error, pageVersion } = state;
  const scrollRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (pageVersion > 0) {
      scrollRef.current?.scrollTo(0, 0);
    }
  }, [pageVersion]);

  const handleOpenFile = useCallback(
    (filePath: string, line?: number) => {
      postMessage({ type: "openFile", filePath, line });
    },
    [postMessage],
  );

  const handleNavigate = useCallback(
    (pageId: string) => {
      postMessage({ type: "navigate", pageId });
    },
    [postMessage],
  );

  const html = useMemo(() => {
    if (!page) {
      return "";
    }
    return marked.parse(page.content) as string;
  }, [page]);

  if (loading) {
    return <div style={s.placeholder}>Loading...</div>;
  }
  if (error) {
    return <div style={{ ...s.placeholder, color: "var(--vscode-errorForeground)" }}>{error}</div>;
  }
  if (!page) {
    return <div style={s.placeholder}>No page selected</div>;
  }

  return (
    <div ref={scrollRef} style={s.root}>
      <article className="markdown-body" style={s.article} dangerouslySetInnerHTML={{ __html: html }} />

      {/* Footer: sources and related pages */}
      {(page.sources.length > 0 || page.children.length > 0) && (
        <footer style={s.footer}>
          {page.sources.length > 0 && (
            <div style={s.footerSection}>
              <span style={s.footerLabel}>Sources</span>
              {page.sources.map((src, i) => (
                <button
                  key={i}
                  type="button"
                  style={s.footerLink}
                  onClick={() => handleOpenFile(src.file, src.lines[0])}
                >
                  {src.file}:{src.lines[0]}-{src.lines[1]}
                </button>
              ))}
            </div>
          )}
          {page.children.length > 0 && (
            <div style={s.footerSection}>
              <span style={s.footerLabel}>Related</span>
              {page.children.map((childId) => (
                <button key={childId} type="button" style={s.footerLink} onClick={() => handleNavigate(childId)}>
                  {childId}
                </button>
              ))}
            </div>
          )}
        </footer>
      )}
    </div>
  );
};

const s: Record<string, React.CSSProperties> = {
  root: {
    height: "100%",
    overflow: "auto",
    background: "var(--vscode-editor-background)",
  },
  placeholder: {
    display: "flex",
    alignItems: "center",
    justifyContent: "center",
    height: "100%",
    fontFamily: "var(--vscode-font-family)",
    color: "var(--vscode-descriptionForeground)",
    fontSize: "13px",
  },
  article: {
    padding: "16px 24px",
    fontFamily: "var(--vscode-markdown-font-family, var(--vscode-font-family))",
    fontSize: "var(--vscode-markdown-font-size, 14px)",
    lineHeight: 1.6,
    color: "var(--vscode-foreground)",
    maxWidth: "900px",
  },
  footer: {
    borderTop: "1px solid var(--vscode-panel-border)",
    padding: "12px 24px",
    fontSize: "12px",
  },
  footerSection: {
    display: "flex",
    flexWrap: "wrap" as const,
    alignItems: "center",
    gap: "4px 12px",
    marginBottom: "6px",
  },
  footerLabel: {
    color: "var(--vscode-descriptionForeground)",
    fontWeight: 600,
    textTransform: "uppercase" as const,
    letterSpacing: "0.3px",
    fontSize: "11px",
  },
  footerLink: {
    background: "none",
    border: "none",
    padding: 0,
    color: "var(--vscode-textLink-foreground)",
    cursor: "pointer",
    fontFamily: "var(--vscode-editor-font-family, monospace)",
    fontSize: "12px",
  },
};
