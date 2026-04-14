/**
 * @file WebviewPanel controller for explore (similarity analysis) results.
 *
 * Opens in the editor area when triggered from file explorer context menu.
 * Reuses a single panel — running explore again updates the content.
 * Uses SSE streaming for incremental result delivery.
 */

import * as vscode from "vscode";
import { postStream, type SseEvent } from "@indexion/api-client";
import type { ExploreToWebview, ExploreFromWebview, ExplorePairItem } from "./messages.ts";
import { similarityPairToItem } from "./messages.ts";
import type { SimilarityPair, ExploreResult } from "@indexion/api-client";
import { buildWebviewHtml } from "../../extension-host/webview-html.ts";
import { resolveCodiconsUri } from "../../extension-host/codicons.ts";
import { resolveConfig } from "../../config/index.ts";
import { resolveFileUri } from "../../extension-host/resolve-file-uri.ts";

/** Manages the explore results panel lifecycle. */
export type ExplorePanelManager = {
  /** Open the panel and start exploring similar files for the given path. */
  readonly explorePath: (targetPath: string) => void;
  /** Notify the panel of server readiness changes. */
  readonly notifyServerStatus: (ready: boolean) => void;
};

/** Create an explore panel manager. */
export const createExplorePanelManager = (
  context: vscode.ExtensionContext,
  getBaseUrl: () => string | undefined,
): ExplorePanelManager => {
  // eslint-disable-next-line no-restricted-syntax -- mutable panel lifecycle state
  let panel: vscode.WebviewPanel | undefined;
  // eslint-disable-next-line no-restricted-syntax -- mutable panel lifecycle state
  let panelReady = false;
  const pending: Array<ExploreToWebview> = [];

  const postToPanel = (msg: ExploreToWebview): void => {
    if (!panel) {
      return;
    }
    if (panelReady) {
      panel.webview.postMessage(msg);
    } else {
      pending.push(msg);
    }
  };

  const flushPending = (): void => {
    if (!panel) {
      return;
    }
    for (const msg of pending) {
      panel.webview.postMessage(msg);
    }
    pending.length = 0;
  };

  const handleExploreStream = (threshold: number, strategy: string, targetPath: string): void => {
    const baseUrl = getBaseUrl();
    if (!baseUrl) {
      postToPanel({ type: "error", message: "Server not ready" });
      return;
    }

    postToPanel({ type: "searching" });

    postStream(baseUrl, "/explore/stream", {
      body: { targetDirs: [targetPath], threshold, strategy },
      onEvent: (event: SseEvent) => {
        switch (event.type) {
          case "progress":
            postToPanel({ type: "progress", phase: event.phase, detail: event.detail });
            break;
          case "result": {
            const exploreResult = event.data as ExploreResult;
            const pairs: ReadonlyArray<ExplorePairItem> = exploreResult.pairs.map((p: SimilarityPair) =>
              similarityPairToItem(p),
            );
            postToPanel({ type: "exploreResults", pairs, fileCount: exploreResult.files.length });
            break;
          }
          case "done":
            postToPanel({ type: "done", total: event.total });
            break;
          case "error":
            postToPanel({ type: "error", message: event.message });
            break;
        }
      },
    }).catch((err) => {
      postToPanel({ type: "error", message: err instanceof Error ? err.message : String(err) });
    });
  };

  const basename = (path: string): string => {
    const i = path.lastIndexOf("/");
    return i >= 0 ? path.slice(i + 1) : path;
  };

  const ensurePanel = (): vscode.WebviewPanel => {
    if (panel) {
      panel.reveal(vscode.ViewColumn.One, true);
      return panel;
    }

    panel = vscode.window.createWebviewPanel(
      "indexion.explore",
      "Explore Similar",
      { viewColumn: vscode.ViewColumn.One, preserveFocus: true },
      {
        enableScripts: true,
        localResourceRoots: [
          vscode.Uri.joinPath(context.extensionUri, "dist", "webview"),
          vscode.Uri.joinPath(context.extensionUri, "node_modules", "@vscode", "codicons", "dist"),
        ],
      },
    );

    panel.iconPath = {
      light: vscode.Uri.joinPath(context.extensionUri, "media", "search-light.svg"),
      dark: vscode.Uri.joinPath(context.extensionUri, "media", "search-dark.svg"),
    };

    const scriptUri = panel.webview.asWebviewUri(
      vscode.Uri.joinPath(context.extensionUri, "dist", "webview", "explore.js"),
    );
    const styleUri = panel.webview.asWebviewUri(
      vscode.Uri.joinPath(context.extensionUri, "dist", "webview", "style.css"),
    );
    const codiconsUri = resolveCodiconsUri(panel.webview, context.extensionUri);

    panel.webview.html = buildWebviewHtml({
      webview: panel.webview,
      scriptUri,
      styleUri,
      codiconsUri,
      title: "Explore Similar Files",
      allowInlineStyles: true,
    });

    panelReady = false;

    panel.webview.onDidReceiveMessage(
      (msg: ExploreFromWebview | { type: "ready" }) => {
        if (msg.type === "ready") {
          panelReady = true;
          flushPending();
          return;
        }
        switch (msg.type) {
          case "explore":
            handleExploreStream(msg.threshold, msg.strategy, msg.targetPath);
            break;
          case "openFile": {
            vscode.workspace.openTextDocument(resolveFileUri(msg.filePath)).then((doc) => {
              vscode.window.showTextDocument(doc, { preserveFocus: true });
            });
            break;
          }
          case "openDiff":
            vscode.commands.executeCommand(
              "vscode.diff",
              resolveFileUri(msg.file1),
              resolveFileUri(msg.file2),
              `${basename(msg.file1)} ↔ ${basename(msg.file2)}`,
            );
            break;
        }
      },
      undefined,
      context.subscriptions,
    );

    panel.onDidDispose(
      () => {
        panel = undefined;
        panelReady = false;
        pending.length = 0;
      },
      undefined,
      context.subscriptions,
    );

    return panel;
  };

  return {
    explorePath: (targetPath: string) => {
      ensurePanel();

      const config = resolveConfig();
      const threshold = config?.threshold ?? 0.7;
      const strategy = config?.strategy ?? "tfidf";

      postToPanel({ type: "serverStatus", ready: getBaseUrl() !== undefined });
      postToPanel({ type: "config", threshold, strategy, targetPath });

      if (panel) {
        panel.title = `Explore: ${basename(targetPath)}`;
      }
    },

    notifyServerStatus: (ready: boolean) => {
      postToPanel({ type: "serverStatus", ready });
    },
  };
};
