/**
 * @file Tests for the wiki sidebar WebviewViewProvider.
 *
 * These tests exercise the nav loading + search dispatch paths without
 * mounting a real VSCode webview — we stub the bridge by capturing the
 * messages the provider posts (via the webview the test attaches).
 */

import { describe, it, expect, vi } from "vitest";
import type { HttpClient, ApiResponse } from "@indexion/api-client";
import { createWikiViewProvider } from "./provider.ts";
import type { WikiToWebview, WikiFromWebview } from "./messages.ts";

type Captured = Array<WikiToWebview>;

const mockClient = (routes: {
  nav?: unknown;
  navError?: string;
  search?: unknown;
  searchError?: string;
}): HttpClient => {
  const get = vi.fn(async (path: string): Promise<ApiResponse<unknown>> => {
    if (path === "/wiki/nav") {
      if (routes.navError) {
        return { ok: false, error: routes.navError };
      }
      return { ok: true, data: routes.nav ?? { pages: [] } };
    }
    return { ok: false, error: "unknown" };
  });
  const post = vi.fn(async (path: string): Promise<ApiResponse<unknown>> => {
    if (path === "/wiki/search") {
      if (routes.searchError) {
        return { ok: false, error: routes.searchError };
      }
      return { ok: true, data: routes.search ?? [] };
    }
    return { ok: false, error: "unknown" };
  });
  return { get, post } as unknown as HttpClient;
};

/**
 * Build a minimal WebviewView stub. The bridge calls `onDidReceiveMessage`
 * and `postMessage`; we capture posted messages and drive the "ready"
 * handshake + incoming messages manually.
 */
const makeView = (): {
  readonly view: {
    webview: {
      options: unknown;
      html: string;
      postMessage: ReturnType<typeof vi.fn>;
      asWebviewUri: (u: unknown) => unknown;
      cspSource: string;
      onDidReceiveMessage: (handler: (msg: unknown) => void) => void;
    };
    onDidChangeVisibility: (handler: () => void) => void;
    visible: boolean;
  };
  readonly captured: Captured;
  readonly sendFromWebview: (msg: WikiFromWebview | { type: "ready" }) => void;
  readonly resolve: () => void;
} => {
  const captured: Captured = [];
  const handlers: Array<(msg: unknown) => void> = [];

  const view = {
    webview: {
      options: undefined as unknown,
      html: "",
      postMessage: vi.fn(async (msg: WikiToWebview) => {
        captured.push(msg);
        return true;
      }),
      asWebviewUri: (u: unknown) => u,
      cspSource: "vscode-webview:",
      onDidReceiveMessage: (handler: (msg: unknown) => void) => {
        handlers.push(handler);
        return { dispose: () => {} };
      },
    },
    onDidChangeVisibility: () => ({ dispose: () => {} }),
    visible: true,
  };

  return {
    view,
    captured,
    sendFromWebview: (msg) => {
      for (const h of handlers) {
        h(msg);
      }
    },
    resolve: () => {},
  };
};

const extensionUri = { fsPath: "/ext", scheme: "file" } as unknown as import("vscode").Uri;

const settle = (): Promise<void> => new Promise((r) => setTimeout(r, 0));

describe("createWikiViewProvider", () => {
  it("loads nav on ready and posts navLoaded", async () => {
    const nav = {
      pages: [
        { id: "overview", title: "Overview", children: [] },
        { id: "arch", title: "Architecture", children: [] },
      ],
    };
    const client = mockClient({ nav });
    const provider = createWikiViewProvider(extensionUri, () => client);
    const { view, captured, sendFromWebview } = makeView();

    provider.resolveWebviewView(view as unknown as import("vscode").WebviewView, {} as never, {} as never);
    sendFromWebview({ type: "ready" });
    await settle();

    const navLoaded = captured.find((m) => m.type === "navLoaded");
    expect(navLoaded).toBeDefined();
    if (navLoaded?.type === "navLoaded") {
      expect(navLoaded.nav.pages).toHaveLength(2);
    }
  });

  it("posts error when nav fetch fails", async () => {
    const client = mockClient({ navError: "boom" });
    const provider = createWikiViewProvider(extensionUri, () => client);
    const { view, captured, sendFromWebview } = makeView();

    provider.resolveWebviewView(view as unknown as import("vscode").WebviewView, {} as never, {} as never);
    sendFromWebview({ type: "ready" });
    await settle();

    const err = captured.find((m) => m.type === "error");
    expect(err).toBeDefined();
    if (err?.type === "error") {
      expect(err.target).toBe("nav");
      expect(err.message).toBe("boom");
    }
  });

  it("dispatches search and posts searchResults", async () => {
    const search = [
      {
        section: { id: "p#s1", page_id: "p", title: "Intro", content: "hello world", level: 2 },
        score: 0.5,
      },
    ];
    const client = mockClient({ nav: { pages: [] }, search });
    const provider = createWikiViewProvider(extensionUri, () => client);
    const { view, captured, sendFromWebview } = makeView();

    provider.resolveWebviewView(view as unknown as import("vscode").WebviewView, {} as never, {} as never);
    sendFromWebview({ type: "ready" });
    await settle();

    captured.length = 0;
    sendFromWebview({ type: "search", query: "hello" });
    await settle();

    const results = captured.find((m) => m.type === "searchResults");
    expect(results).toBeDefined();
    if (results?.type === "searchResults") {
      expect(results.results).toHaveLength(1);
      expect(results.results[0]?.pageId).toBe("p");
      expect(results.results[0]?.title).toBe("Intro");
    }
  });

  it("reports missing wiki search index without posting an error", async () => {
    const client = mockClient({
      nav: { pages: [] },
      searchError: "Wiki search index not available",
    });
    const provider = createWikiViewProvider(extensionUri, () => client);
    const { view, captured, sendFromWebview } = makeView();

    provider.resolveWebviewView(view as unknown as import("vscode").WebviewView, {} as never, {} as never);
    sendFromWebview({ type: "ready" });
    await settle();

    captured.length = 0;
    sendFromWebview({ type: "search", query: "hello" });
    await settle();

    const unavailable = captured.find((m) => m.type === "searchUnavailable");
    expect(unavailable).toBeDefined();
    const err = captured.find((m) => m.type === "error");
    expect(err).toBeUndefined();
  });

  it("emits error when client is missing on search", async () => {
    const provider = createWikiViewProvider(extensionUri, () => undefined);
    const { view, captured, sendFromWebview } = makeView();

    provider.resolveWebviewView(view as unknown as import("vscode").WebviewView, {} as never, {} as never);
    sendFromWebview({ type: "ready" });
    await settle();

    captured.length = 0;
    sendFromWebview({ type: "search", query: "x" });
    await settle();

    const err = captured.find((m) => m.type === "error");
    expect(err?.type).toBe("error");
    if (err?.type === "error") {
      expect(err.target).toBe("search");
    }
  });
});
