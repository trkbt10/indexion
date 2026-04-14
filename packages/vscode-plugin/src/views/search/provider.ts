/**
 * @file Unified search WebviewViewProvider with SSE streaming.
 *
 * A single sidebar panel that supports 3 search modes:
 * - search:  full-text/semantic search via /search/stream
 * - grep:    KGF token pattern search via /grep/stream
 * - digest:  function search by purpose via /digest/query/stream
 *
 * All modes use SSE streaming for incremental result delivery.
 * Results appear one-by-one as the server produces them,
 * with progress phase indicators during computation.
 */

import * as vscode from "vscode";
import { postStream, type SseEvent } from "@indexion/api-client";
import type { SearchFromWebview, SearchToWebview, SearchResultItem } from "./messages.ts";
import { searchHitToItem, digestMatchToItem, grepMatchToItem } from "./messages.ts";
import type { SearchHit, DigestMatch, GrepMatch } from "@indexion/api-client";
import { buildWebviewHtml } from "../../extension-host/webview-html.ts";
import { createWebviewBridge } from "../../extension-host/webview-bridge.ts";
import { resolveCodiconsUri } from "../../extension-host/codicons.ts";
import { resolveFileUri } from "../../extension-host/resolve-file-uri.ts";

/** Maps SSE item data to SearchResultItem based on search mode. */
const mapSseItem = (data: unknown, mode: "search" | "grep" | "digest"): SearchResultItem => {
  switch (mode) {
    case "search":
      return searchHitToItem(data as SearchHit);
    case "grep":
      return grepMatchToItem(data as GrepMatch);
    case "digest":
      return digestMatchToItem(data as DigestMatch);
  }
};

/** Create the unified search WebviewViewProvider. */
export const createSearchViewProvider = (
  extensionUri: vscode.Uri,
  getBaseUrl: () => string | undefined,
  log?: { readonly appendLine: (msg: string) => void },
): vscode.WebviewViewProvider & { readonly notifyServerStatus: (ready: boolean) => void } => {
  const bridge = createWebviewBridge<SearchToWebview>(log);

  /** Shared streaming handler for search/grep/digest modes. */
  const handleStream = (path: string, body: unknown, mode: "search" | "grep" | "digest"): void => {
    const baseUrl = getBaseUrl();
    if (!baseUrl) {
      bridge.post({ type: "error", message: "Server not ready" });
      return;
    }

    bridge.post({ type: "searching" });

    // Batch incoming items to avoid flooding the webview with postMessage calls.
    // Items are accumulated and flushed every 100ms or when a non-item event arrives.
    const BATCH_INTERVAL_MS = 100;
    const pendingItems: Array<SearchResultItem> = [];
    // eslint-disable-next-line no-restricted-syntax -- mutable timer handle for batching
    let batchTimer: ReturnType<typeof setTimeout> | undefined;

    const flushItems = (): void => {
      if (pendingItems.length > 0) {
        bridge.post({ type: "appendItems", items: [...pendingItems] });
        pendingItems.length = 0;
      }
      if (batchTimer !== undefined) {
        clearTimeout(batchTimer);
        batchTimer = undefined;
      }
    };

    const enqueueItem = (item: SearchResultItem): void => {
      pendingItems.push(item);
      if (batchTimer === undefined) {
        batchTimer = setTimeout(flushItems, BATCH_INTERVAL_MS);
      }
    };

    postStream(baseUrl, path, {
      body,
      onEvent: (event: SseEvent) => {
        switch (event.type) {
          case "progress":
            flushItems();
            bridge.post({ type: "progress", phase: event.phase, detail: event.detail });
            break;
          case "item":
            enqueueItem(mapSseItem(event.data, mode));
            break;
          case "items":
            for (const d of event.data as ReadonlyArray<unknown>) {
              enqueueItem(mapSseItem(d, mode));
            }
            break;
          case "done":
            flushItems();
            bridge.post({ type: "done", total: event.total });
            break;
          case "error":
            flushItems();
            bridge.post({ type: "error", message: event.message });
            break;
        }
      },
    }).catch((err) => {
      flushItems();
      bridge.post({ type: "error", message: err instanceof Error ? err.message : String(err) });
    });
  };

  return {
    notifyServerStatus: (ready: boolean) => {
      log?.appendLine(
        `[search] notifyServerStatus(${ready}) attached=${bridge.isAttached()} ready=${bridge.isReady()}`,
      );
      const result = bridge.post({ type: "serverStatus", ready });
      if (result) {
        result.then(
          (ok) => log?.appendLine(`[search] postMessage delivered=${ok}`),
          (err) => log?.appendLine(`[search] postMessage error: ${err}`),
        );
      } else {
        log?.appendLine("[search] postMessage not sent (queued or no view)");
      }
    },

    resolveWebviewView: (view: vscode.WebviewView) => {
      log?.appendLine("[search] resolveWebviewView");
      view.webview.options = {
        enableScripts: true,
        localResourceRoots: [
          vscode.Uri.joinPath(extensionUri, "dist", "webview"),
          vscode.Uri.joinPath(extensionUri, "node_modules", "@vscode", "codicons", "dist"),
        ],
      };

      const scriptUri = view.webview.asWebviewUri(vscode.Uri.joinPath(extensionUri, "dist", "webview", "search.js"));
      const styleUri = view.webview.asWebviewUri(vscode.Uri.joinPath(extensionUri, "dist", "webview", "style.css"));
      const codiconsUri = resolveCodiconsUri(view.webview, extensionUri);

      view.webview.html = buildWebviewHtml({
        webview: view.webview,
        scriptUri,
        styleUri,
        codiconsUri,
        title: "Search",
        allowInlineStyles: true,
      });

      bridge.attach(view, () => {
        const ready = getBaseUrl() !== undefined;
        log?.appendLine(`[search] webview ready, serverReady=${ready}`);
        bridge.post({ type: "serverStatus", ready });
      });

      // Re-send server status when sidebar becomes visible again.
      // postMessage can be dropped while the webview is hidden.
      view.onDidChangeVisibility(() => {
        log?.appendLine(`[search] visibility changed: visible=${view.visible}`);
        if (view.visible && bridge.isReady()) {
          bridge.post({ type: "serverStatus", ready: getBaseUrl() !== undefined });
        }
      });

      view.webview.onDidReceiveMessage((msg: SearchFromWebview) => {
        log?.appendLine(`[search] received: ${msg.type}`);
        switch (msg.type) {
          case "search":
            handleStream("/search/stream", { query: msg.query, topK: 30 }, "search");
            break;
          case "digest":
            handleStream("/digest/query/stream", { purpose: msg.query, topK: 20 }, "digest");
            break;
          case "grep":
            handleStream("/grep/stream", { pattern: msg.pattern }, "grep");
            break;
          case "openFile": {
            const uri = resolveFileUri(msg.filePath);
            log?.appendLine(`[search] openFile: ${msg.filePath} → ${uri.fsPath}`);
            vscode.workspace.openTextDocument(uri).then(
              (doc) => {
                log?.appendLine(`[search] opened: ${doc.uri.fsPath}`);
                const options: vscode.TextDocumentShowOptions = {};
                if (msg.line !== undefined && msg.line > 0) {
                  const pos = new vscode.Position(msg.line - 1, 0);
                  options.selection = new vscode.Range(pos, pos);
                }
                vscode.window.showTextDocument(doc, options);
              },
              (err) => {
                log?.appendLine(`[search] openFile error: ${err instanceof Error ? err.message : String(err)}`);
              },
            );
            break;
          }
        }
      });
    },
  };
};
