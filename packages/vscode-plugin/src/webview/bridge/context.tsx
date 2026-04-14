/**
 * @file React context for VSCode webview ↔ extension host communication.
 *
 * Provides a single entry point for all webview apps to communicate with
 * the extension host. Handles:
 * - Acquiring the VSCode API
 * - Sending the "ready" handshake on mount
 * - Subscribing to incoming messages
 *
 * Usage in each webview app:
 *
 *   // app.tsx (entry point)
 *   <WebviewProvider<MyFromWebview>>
 *     <MyApp />
 *   </WebviewProvider>
 *
 *   // MyApp component
 *   const { postMessage } = useWebview<MyFromWebview>();
 *   useWebviewMessage<MyToWebview>((msg) => { ... });
 */

import React, { createContext, useCallback, useContext, useEffect, useMemo, useReducer, useRef } from "react";

// ─── VSCode API acquisition ─────────────────────────────

type RawVsCodeApi = {
  readonly postMessage: (msg: unknown) => void;
  readonly getState: () => unknown;
  readonly setState: (state: unknown) => void;
};

/** Acquire the VSCode webview API. Called once per webview lifetime. */
const acquireApi = (): RawVsCodeApi => {
  if (!("acquireVsCodeApi" in window)) {
    throw new Error("acquireVsCodeApi is not available — this code must run inside a VSCode webview");
  }
  const acquire = (window as { acquireVsCodeApi: () => RawVsCodeApi }).acquireVsCodeApi;
  return acquire();
};

// ─── Context definition ─────────────────────────────────

type WebviewContextValue = {
  readonly postMessage: (msg: unknown) => void;
  readonly subscribe: (handler: (msg: unknown) => void) => () => void;
};

const WebviewContext = createContext<WebviewContextValue | null>(null);

// ─── Provider ───────────────────────────────────────────

type WebviewProviderProps = {
  readonly children: React.ReactNode;
};

/**
 * Wrap your webview app in this provider. It:
 * 1. Acquires the VSCode API once
 * 2. Sends { type: "ready" } to the extension host on mount
 * 3. Provides postMessage and message subscription to children
 */
export const WebviewProvider = ({ children }: WebviewProviderProps): React.JSX.Element => {
  const apiRef = useRef<RawVsCodeApi | null>(null);
  const listenersRef = useRef<Set<(msg: unknown) => void>>(new Set());

  if (!apiRef.current) {
    apiRef.current = acquireApi();
  }

  const postMessage = useCallback((msg: unknown): void => {
    apiRef.current?.postMessage(msg);
  }, []);

  const subscribe = useCallback((handler: (msg: unknown) => void): (() => void) => {
    listenersRef.current.add(handler);
    return () => {
      listenersRef.current.delete(handler);
    };
  }, []);

  // Listen for messages from the extension host
  useEffect(() => {
    const listener = (event: MessageEvent<unknown>): void => {
      const data = event.data as { type?: string } | undefined;
      // Echo receipt back to extension host for diagnostics
      if (data?.type && data.type !== "__ack") {
        apiRef.current?.postMessage({ type: "__ack", received: data.type });
      }
      for (const handler of listenersRef.current) {
        handler(event.data);
      }
    };
    window.addEventListener("message", listener);
    return () => {
      window.removeEventListener("message", listener);
    };
  }, []);

  // Send "ready" handshake on mount
  useEffect(() => {
    apiRef.current?.postMessage({ type: "ready" });
  }, []);

  const value = useMemo<WebviewContextValue>(() => ({ postMessage, subscribe }), [postMessage, subscribe]);

  return <WebviewContext.Provider value={value}>{children}</WebviewContext.Provider>;
};

// ─── Hooks ──────────────────────────────────────────────

/** Get the postMessage function for sending messages to the extension host. */
export const usePostMessage = <TFromWebview,>(): ((msg: TFromWebview) => void) => {
  const ctx = useContext(WebviewContext);
  if (!ctx) {
    throw new Error("usePostMessage must be used within <WebviewProvider>");
  }
  return ctx.postMessage as (msg: TFromWebview) => void;
};

/** Subscribe to messages from the extension host. Automatically unsubscribes on unmount. */
export const useWebviewMessage = <TToWebview,>(handler: (msg: TToWebview) => void): void => {
  const ctx = useContext(WebviewContext);
  if (!ctx) {
    throw new Error("useWebviewMessage must be used within <WebviewProvider>");
  }
  const handlerRef = useRef(handler);
  handlerRef.current = handler;

  useEffect(() => {
    return ctx.subscribe((msg) => {
      handlerRef.current(msg as TToWebview);
    });
  }, [ctx]);
};

/**
 * Combine useReducer with useWebviewMessage.
 *
 * Incoming messages from the extension host are dispatched as actions to the
 * reducer automatically. The returned `dispatch` can also be called directly
 * for local UI actions.
 *
 * @param reducer  A standard React reducer. `TAction` is typically a union of
 *                 the incoming message type (`TToWebview`) and any local
 *                 component actions.
 * @param initialState  The initial state value.
 * @returns `[state, dispatch]` — same shape as `useReducer`.
 */
export const useWebviewReducer = <TState, TAction>(
  reducer: React.Reducer<TState, TAction>,
  initialState: TState,
): [TState, React.Dispatch<TAction>] => {
  const [state, dispatch] = useReducer(reducer, initialState);

  useWebviewMessage<TAction>((msg) => {
    dispatch(msg);
  });

  return [state, dispatch];
};
