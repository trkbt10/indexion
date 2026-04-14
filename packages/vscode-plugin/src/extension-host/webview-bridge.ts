/**
 * @file Extension host side of the webview handshake protocol.
 *
 * Problem: When a WebviewView's HTML is set, the React app takes time to
 * mount. Any postMessage() calls made before mount are silently lost.
 *
 * Solution: The React app sends a { type: "ready" } message after mounting
 * (via WebviewProvider in webview/bridge/context.tsx). The extension host
 * MUST NOT send messages until "ready" arrives.
 *
 * This module provides WebviewBridge — a typed message sender that
 * automatically queues messages until the React app is ready.
 *
 * All WebviewViewProvider implementations MUST use this:
 *
 *   const bridge = createWebviewBridge<ToWebview>();
 *   // in resolveWebviewView:
 *   bridge.attach(view, onReady);
 *   // to send messages:
 *   bridge.post(msg);  // safe: queues until ready
 *
 * @see src/webview/bridge/context.tsx for the React side.
 */

import type * as vscode from "vscode";

/** The "ready" message that React apps send after mounting. */
export type WebviewReadyMessage = { readonly type: "ready" };

/**
 * A bridge that safely manages message delivery to a WebviewView.
 *
 * - Messages sent before "ready" are queued and flushed on ready.
 * - Messages sent before attach() are discarded (no webview exists).
 * - notifyServerStatus-style calls from extension.ts are safe at any time.
 */
export type WebviewBridge<TToWebview> = {
  /** Attach to a webview view. Call this in resolveWebviewView. */
  readonly attach: (view: vscode.WebviewView, onReady: () => void) => void;
  /** Send a message to the webview. Returns the postMessage promise if sent, undefined otherwise. */
  readonly post: (msg: TToWebview) => Thenable<boolean> | undefined;
  /** Whether the webview has sent "ready". */
  readonly isReady: () => boolean;
  /** Whether a webview is attached. */
  readonly isAttached: () => boolean;
};

/** Mutable internal state for a WebviewBridge. */
type BridgeState<T> = {
  view: vscode.WebviewView | undefined;
  ready: boolean;
  readonly pending: Array<T>;
  readonly log?: { readonly appendLine: (msg: string) => void };
};

/** Create a WebviewBridge for typed message delivery. */
export const createWebviewBridge = <TToWebview>(log?: {
  readonly appendLine: (msg: string) => void;
}): WebviewBridge<TToWebview> => {
  const s: BridgeState<TToWebview> = { view: undefined, ready: false, pending: [], log };

  const flush = (): void => {
    if (!s.view) {
      return;
    }
    for (const msg of s.pending) {
      s.view.webview.postMessage(msg);
    }
    s.pending.length = 0;
  };

  return {
    attach: (webviewView, onReady) => {
      s.view = webviewView;
      s.ready = false;
      s.pending.length = 0;

      s.view.webview.onDidReceiveMessage((msg: { type: string; received?: string }) => {
        if (msg.type === "__ack" && s.log) {
          s.log.appendLine(`[bridge] webview received: ${msg.received}`);
          return;
        }
        if (msg.type === "ready" && !s.ready) {
          s.ready = true;
          onReady();
          flush();
        }
      });
    },

    post: (msg) => {
      if (!s.view) {
        return undefined;
      }
      if (s.ready) {
        return s.view.webview.postMessage(msg);
      }
      s.pending.push(msg);
      return undefined;
    },

    isReady: () => s.ready,
    isAttached: () => s.view !== undefined,
  };
};
