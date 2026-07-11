/**
 * @file WebviewViewProvider for the wiki sidebar.
 *
 * The sidebar presents a nav tree and a search input in a single React app.
 * The input behaves as a filter: an empty query shows the tree, a non-empty
 * query shows search hits. The extension host loads nav via `fetchWikiNav`
 * and search results via `searchWiki`, and delegates page navigation back to
 * the `indexion.wikiOpenPage` command.
 */

import * as vscode from "vscode";
import { fetchWikiNav, searchWiki, type HttpClient } from "@indexion/api-client";
import type { WikiFromWebview, WikiToWebview } from "./messages.ts";
import { toWikiSearchHits } from "./messages.ts";
import { buildWebviewHtml } from "../../extension-host/webview-html.ts";
import { createWebviewBridge } from "../../extension-host/webview-bridge.ts";
import { resolveCodiconsUri } from "../../extension-host/codicons.ts";

type Log = { readonly appendLine: (msg: string) => void };

const WIKI_SEARCH_INDEX_UNAVAILABLE = "wiki search index not available";
const WIKI_SEARCH_UNAVAILABLE_MESSAGE = "Wiki search is not available yet. The wiki pages are still browsable.";

const isWikiSearchIndexUnavailable = (message: string): boolean =>
  message.toLowerCase().includes(WIKI_SEARCH_INDEX_UNAVAILABLE);

/** Create the wiki sidebar WebviewViewProvider. */
export const createWikiViewProvider = (
  extensionUri: vscode.Uri,
  getClient: () => HttpClient | undefined,
  log?: Log,
): vscode.WebviewViewProvider & {
  readonly notifyServerStatus: (ready: boolean) => void;
  readonly refresh: () => void;
} => {
  const bridge = createWebviewBridge<WikiToWebview>(log);

  const loadNav = async (): Promise<void> => {
    const client = getClient();
    if (!client) {
      bridge.post({ type: "error", target: "nav", message: "Server not ready" });
      return;
    }
    bridge.post({ type: "loading", target: "nav" });
    const result = await fetchWikiNav(client);
    if (!result.ok) {
      log?.appendLine(`[wiki] nav failed: ${result.error}`);
      bridge.post({ type: "error", target: "nav", message: result.error });
      return;
    }
    log?.appendLine(`[wiki] nav loaded: ${result.data.pages.length} pages`);
    bridge.post({ type: "navLoaded", nav: result.data });
  };

  const runSearch = async (query: string): Promise<void> => {
    const client = getClient();
    if (!client) {
      bridge.post({ type: "error", target: "search", message: "Server not ready" });
      return;
    }
    bridge.post({ type: "loading", target: "search" });
    try {
      const result = await searchWiki(client, { query, topK: 20 });
      if (!result.ok) {
        if (isWikiSearchIndexUnavailable(result.error)) {
          log?.appendLine("[wiki] search skipped: search index unavailable");
          bridge.post({
            type: "searchUnavailable",
            message: WIKI_SEARCH_UNAVAILABLE_MESSAGE,
          });
          return;
        }
        log?.appendLine(`[wiki] search failed: ${result.error}`);
        bridge.post({ type: "error", target: "search", message: result.error });
        return;
      }
      const hits = toWikiSearchHits(result.data as ReadonlyArray<Record<string, unknown>>);
      log?.appendLine(`[wiki] search "${query}" → ${hits.length} hits`);
      bridge.post({ type: "searchResults", results: hits });
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      log?.appendLine(`[wiki] search failed: ${message}`);
      bridge.post({ type: "error", target: "search", message });
    }
  };

  return {
    notifyServerStatus: (ready: boolean) => {
      bridge.post({ type: "serverStatus", ready });
      if (ready) {
        loadNav();
      }
    },

    refresh: () => {
      loadNav();
    },

    resolveWebviewView: (view: vscode.WebviewView) => {
      log?.appendLine("[wiki] resolveWebviewView");
      view.webview.options = {
        enableScripts: true,
        localResourceRoots: [
          vscode.Uri.joinPath(extensionUri, "dist", "webview"),
          vscode.Uri.joinPath(extensionUri, "node_modules", "@vscode", "codicons", "dist"),
        ],
      };

      const scriptUri = view.webview.asWebviewUri(
        vscode.Uri.joinPath(extensionUri, "dist", "webview", "wiki-sidebar.js"),
      );
      const styleUri = view.webview.asWebviewUri(vscode.Uri.joinPath(extensionUri, "dist", "webview", "style.css"));
      const codiconsUri = resolveCodiconsUri(view.webview, extensionUri);

      view.webview.html = buildWebviewHtml({
        webview: view.webview,
        scriptUri,
        styleUri,
        codiconsUri,
        title: "Wiki",
        allowInlineStyles: true,
      });

      bridge.attach(view, () => {
        const ready = getClient() !== undefined;
        log?.appendLine(`[wiki] webview ready, serverReady=${ready}`);
        bridge.post({ type: "serverStatus", ready });
        if (ready) {
          loadNav();
        }
      });

      view.onDidChangeVisibility(() => {
        if (view.visible && bridge.isReady()) {
          bridge.post({ type: "serverStatus", ready: getClient() !== undefined });
        }
      });

      view.webview.onDidReceiveMessage((msg: WikiFromWebview) => {
        log?.appendLine(`[wiki] received: ${msg.type}`);
        switch (msg.type) {
          case "requestNav":
            loadNav();
            break;
          case "navigate":
            vscode.commands.executeCommand("indexion.wikiOpenPage", msg.pageId);
            break;
          case "search":
            runSearch(msg.query);
            break;
        }
      });
    },
  };
};
