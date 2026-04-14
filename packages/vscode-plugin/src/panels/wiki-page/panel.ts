/**
 * @file WebviewPanel controller for the wiki page viewer.
 *
 * Opens wiki pages in the editor area as a read-only viewer.
 * Reuses a single panel — navigating to a new page updates the content.
 */

import * as vscode from "vscode";
import { fetchWikiPage, type HttpClient } from "@indexion/api-client";
import type { WikiPageToWebview, WikiPageFromWebview } from "./messages.ts";
import { buildWebviewHtml } from "../../extension-host/webview-html.ts";
import { resolveCodiconsUri } from "../../extension-host/codicons.ts";
import { resolveFileUri } from "../../extension-host/resolve-file-uri.ts";

/** Manages a single wiki page panel. Reused across navigations. */
export type WikiPagePanelManager = {
  /** Open (or focus) the panel and load the given page. */
  readonly openPage: (pageId: string) => void;
};

/** Create a wiki page panel manager. */
export const createWikiPagePanelManager = (
  context: vscode.ExtensionContext,
  getClient: () => HttpClient | undefined,
  log?: { readonly appendLine: (msg: string) => void },
): WikiPagePanelManager => {
  // eslint-disable-next-line no-restricted-syntax -- mutable panel lifecycle state
  let panel: vscode.WebviewPanel | undefined;
  // eslint-disable-next-line no-restricted-syntax -- mutable panel lifecycle state
  let panelReady = false;
  const pending: Array<WikiPageToWebview> = [];

  const postToPanel = (msg: WikiPageToWebview): void => {
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

  const loadPage = async (pageId: string): Promise<void> => {
    const client = getClient();
    if (!client) {
      postToPanel({ type: "error", message: "Server not ready" });
      return;
    }
    log?.appendLine(`[wiki-page] loading: ${pageId}`);
    postToPanel({ type: "loading" });
    const result = await fetchWikiPage(client, pageId);
    if (!result.ok) {
      log?.appendLine(`[wiki-page] error: ${result.error}`);
      postToPanel({ type: "error", message: result.error });
      return;
    }
    log?.appendLine(`[wiki-page] loaded: ${result.data.title}`);
    if (panel) {
      panel.title = result.data.title;
    }
    postToPanel({ type: "pageLoaded", page: result.data });
  };

  const ensurePanel = (): vscode.WebviewPanel => {
    if (panel) {
      panel.reveal(vscode.ViewColumn.One, true);
      return panel;
    }

    panel = vscode.window.createWebviewPanel(
      "indexion.wikiPage",
      "Wiki",
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
      light: vscode.Uri.joinPath(context.extensionUri, "media", "wiki-light.svg"),
      dark: vscode.Uri.joinPath(context.extensionUri, "media", "wiki-dark.svg"),
    };

    const scriptUri = panel.webview.asWebviewUri(
      vscode.Uri.joinPath(context.extensionUri, "dist", "webview", "wiki-viewer.js"),
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
      title: "Wiki Page",
      allowInlineStyles: true,
    });

    panelReady = false;
    panel.webview.onDidReceiveMessage(
      (msg: WikiPageFromWebview | { type: "ready" }) => {
        if (msg.type === "ready") {
          panelReady = true;
          flushPending();
          return;
        }
        if (msg.type === "openFile") {
          const uri = resolveFileUri(msg.filePath);
          vscode.workspace.openTextDocument(uri).then((doc) => {
            const options: vscode.TextDocumentShowOptions = {};
            if (msg.line !== undefined) {
              const pos = new vscode.Position(Math.max(0, msg.line - 1), 0);
              options.selection = new vscode.Range(pos, pos);
            }
            vscode.window.showTextDocument(doc, options);
          });
        }
        if (msg.type === "navigate") {
          loadPage(msg.pageId);
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
    openPage: (pageId: string) => {
      log?.appendLine(`[wiki-page] openPage: ${pageId}`);
      ensurePanel();
      loadPage(pageId);
    },
  };
};
