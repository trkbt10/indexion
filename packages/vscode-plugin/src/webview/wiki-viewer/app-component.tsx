/**
 * @file Wiki page viewer — renders markdown content in the editor area.
 *
 * Uses the shared WikiContent component from @indexion/wiki with a
 * VSCode-specific environment that routes link clicks and file opens
 * through the extension host via postMessage.
 */

import React, { useCallback, useEffect, useMemo, useRef } from "react";
import {
  WikiContent,
  WikiContentEnvProvider,
  type WikiContentEnv,
} from "@indexion/wiki/components";
import type { WikiPage } from "@indexion/api-client";
import type { WikiPageToWebview, WikiPageFromWebview } from "../../panels/wiki-page/messages.ts";
import { usePostMessage, useWebviewReducer } from "../bridge/context.tsx";
import { StatusMsg } from "../components/status-msg.tsx";
import { FileLink } from "../components/file-link.tsx";
import styles from "./wiki-viewer.module.css";

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

  const env = useMemo(
    (): WikiContentEnv => ({
      renderWikiLink: (pageId, children) => (
        <button
          type="button"
          className={styles.wikiLink}
          onClick={() => handleNavigate(pageId)}
        >
          {children}
        </button>
      ),
      renderSourceBadge: (source) => (
        <FileLink
          filePath={source.file}
          label={
            source.lines[1] > 0
              ? `${source.file}:${source.lines[0]}-${source.lines[1]}`
              : source.file
          }
          onClick={() => handleOpenFile(source.file, source.lines[0])}
        />
      ),
      sourceFilesLabel: "Relevant source files",
      relatedPagesLabel: "Related",
    }),
    [handleOpenFile, handleNavigate],
  );

  if (loading) {
    return (
      <div className={styles.centered}>
        <StatusMsg>Loading...</StatusMsg>
      </div>
    );
  }
  if (error) {
    return (
      <div className={styles.centered}>
        <StatusMsg error>{error}</StatusMsg>
      </div>
    );
  }
  if (!page) {
    return (
      <div className={styles.centered}>
        <StatusMsg>No page selected</StatusMsg>
      </div>
    );
  }

  return (
    <div ref={scrollRef} className={styles.root}>
      <WikiContentEnvProvider value={env}>
        <WikiContent page={page} />
      </WikiContentEnvProvider>
    </div>
  );
};
