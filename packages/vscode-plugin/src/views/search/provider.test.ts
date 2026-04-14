/**
 * @file Tests for search WebviewViewProvider.
 *
 * Verifies that:
 * - serverStatus is sent when webview becomes ready
 * - notifyServerStatus before webview ready is queued and delivered
 * - notifyServerStatus after webview ready is delivered immediately
 * - serverStatus is re-sent when sidebar becomes visible (onDidChangeVisibility)
 * - SSE items are batched before posting to webview
 */

import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { createSearchViewProvider } from "./provider.ts";

/** Create a mock WebviewView with visibility simulation. */
const createMockView = () => {
  const posted: Array<unknown> = [];
  const messageHandlers: Array<(msg: unknown) => void> = [];
  const visibilityHandlers: Array<() => void> = [];

  const state = { visible: true };

  const view = {
    get visible() {
      return state.visible;
    },
    webview: {
      options: {},
      html: "",
      postMessage: vi.fn((msg: unknown) => {
        posted.push(msg);
        return Promise.resolve(true);
      }),
      onDidReceiveMessage: (handler: (msg: unknown) => void) => {
        messageHandlers.push(handler);
        return { dispose: () => {} };
      },
      asWebviewUri: (uri: unknown) => uri,
      cspSource: "",
    },
    onDidChangeVisibility: (handler: () => void) => {
      visibilityHandlers.push(handler);
      return { dispose: () => {} };
    },
  } as unknown as import("vscode").WebviewView;

  const simulateMessage = (msg: { type: string }): void => {
    for (const handler of messageHandlers) {
      handler(msg);
    }
  };

  const simulateVisibilityChange = (visible: boolean): void => {
    state.visible = visible;
    for (const handler of visibilityHandlers) {
      handler();
    }
  };

  return { view, posted, simulateMessage, simulateVisibilityChange };
};

/** Create a mock extension URI. */
const createMockExtensionUri = () => {
  const joinPath = (_base: unknown, ...segments: ReadonlyArray<string>) => ({
    fsPath: `/ext/${segments.join("/")}`,
    toString: () => `/ext/${segments.join("/")}`,
  });
  return { joinPath } as unknown as import("vscode").Uri;
};

// Hoisted mocks for postStream
const { mockPostStream } = vi.hoisted(() => ({
  mockPostStream: vi.fn(),
}));

// Mock vscode and extension-host modules to avoid real VSCode dependencies.
const { mockOpenTextDocument, mockShowTextDocument } = vi.hoisted(() => ({
  mockOpenTextDocument: vi.fn(() => Promise.resolve({ uri: { fsPath: "/mock" } })),
  mockShowTextDocument: vi.fn(),
}));

vi.mock("vscode", () => ({
  Uri: {
    joinPath: (base: { fsPath: string }, ...segments: ReadonlyArray<string>) => {
      const joined = `${base.fsPath}/${segments.join("/")}`;
      return { fsPath: joined, toString: () => joined };
    },
    file: (path: string) => ({ fsPath: path, toString: () => path }),
  },
  workspace: {
    workspaceFolders: [{ uri: { fsPath: "/workspace", toString: () => "/workspace" } }],
    openTextDocument: mockOpenTextDocument,
  },
  window: {
    showTextDocument: mockShowTextDocument,
  },
  Position: class {
    constructor(
      public line: number,
      public character: number,
    ) {}
  },
  Range: class {
    constructor(
      public start: unknown,
      public end: unknown,
    ) {}
  },
}));

vi.mock("../../extension-host/webview-html.ts", () => ({
  buildWebviewHtml: () => "<html></html>",
}));

vi.mock("../../extension-host/codicons.ts", () => ({
  resolveCodiconsUri: () => "codicons-uri",
}));

vi.mock("@indexion/api-client", () => ({
  postStream: mockPostStream,
}));

describe("createSearchViewProvider", () => {
  beforeEach(() => {
    vi.useFakeTimers();
    vi.clearAllMocks();
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it("sends serverStatus:true on webview ready when server is already running", () => {
    const extensionUri = createMockExtensionUri();
    const getBaseUrl = () => "http://127.0.0.1:12345";

    const provider = createSearchViewProvider(extensionUri, getBaseUrl);
    const { view, posted, simulateMessage } = createMockView();

    provider.resolveWebviewView(view, {} as never, {} as never);
    expect(posted).toHaveLength(0);

    simulateMessage({ type: "ready" });

    const serverStatusMessages = posted.filter(
      (m) => (m as { type: string }).type === "serverStatus",
    ) as ReadonlyArray<{ type: string; ready: boolean }>;

    expect(serverStatusMessages.length).toBeGreaterThanOrEqual(1);
    expect(serverStatusMessages.some((m) => m.ready === true)).toBe(true);
  });

  it("sends serverStatus:false on webview ready when server is not yet running", () => {
    const extensionUri = createMockExtensionUri();
    const getBaseUrl = () => undefined;

    const provider = createSearchViewProvider(extensionUri, getBaseUrl);
    const { view, posted, simulateMessage } = createMockView();

    provider.resolveWebviewView(view, {} as never, {} as never);
    simulateMessage({ type: "ready" });

    const serverStatusMessages = posted.filter(
      (m) => (m as { type: string }).type === "serverStatus",
    ) as ReadonlyArray<{ type: string; ready: boolean }>;

    expect(serverStatusMessages.length).toBeGreaterThanOrEqual(1);
    expect(serverStatusMessages[serverStatusMessages.length - 1]?.ready).toBe(false);
  });

  it("delivers notifyServerStatus after webview is ready", () => {
    const extensionUri = createMockExtensionUri();
    const getBaseUrl = () => "http://127.0.0.1:12345";

    const provider = createSearchViewProvider(extensionUri, getBaseUrl);
    const { view, posted, simulateMessage } = createMockView();

    provider.resolveWebviewView(view, {} as never, {} as never);
    simulateMessage({ type: "ready" });

    const countBefore = posted.length;
    provider.notifyServerStatus(true);

    expect(posted.length).toBe(countBefore + 1);
    expect(posted[posted.length - 1]).toEqual({ type: "serverStatus", ready: true });
  });

  it("queues notifyServerStatus before webview ready, then flushes on ready", () => {
    const extensionUri = createMockExtensionUri();
    const serverState = { url: undefined as string | undefined };
    const getBaseUrl = () => serverState.url;

    const provider = createSearchViewProvider(extensionUri, getBaseUrl);
    const { view, posted, simulateMessage } = createMockView();

    provider.resolveWebviewView(view, {} as never, {} as never);

    serverState.url = "http://127.0.0.1:12345";
    provider.notifyServerStatus(true);
    expect(posted).toHaveLength(0);

    simulateMessage({ type: "ready" });

    const serverStatusMessages = posted.filter(
      (m) => (m as { type: string }).type === "serverStatus",
    ) as ReadonlyArray<{ type: string; ready: boolean }>;

    expect(serverStatusMessages.length).toBeGreaterThanOrEqual(1);
    expect(serverStatusMessages.every((m) => m.ready === true)).toBe(true);
  });

  it("re-sends serverStatus when sidebar becomes visible", () => {
    const extensionUri = createMockExtensionUri();
    const getBaseUrl = () => "http://127.0.0.1:12345";

    const provider = createSearchViewProvider(extensionUri, getBaseUrl);
    const { view, posted, simulateMessage, simulateVisibilityChange } = createMockView();

    provider.resolveWebviewView(view, {} as never, {} as never);
    simulateMessage({ type: "ready" });

    const countBefore = posted.length;

    // Simulate sidebar hidden, then visible again
    simulateVisibilityChange(false);
    simulateVisibilityChange(true);

    const newMessages = posted.slice(countBefore);
    const serverStatusMessages = newMessages.filter(
      (m) => (m as { type: string }).type === "serverStatus",
    ) as ReadonlyArray<{ type: string; ready: boolean }>;

    // Should have re-sent serverStatus when becoming visible
    expect(serverStatusMessages.length).toBe(1);
    expect(serverStatusMessages[0].ready).toBe(true);
  });

  it("does not send serverStatus on visibility change when hidden", () => {
    const extensionUri = createMockExtensionUri();
    const getBaseUrl = () => "http://127.0.0.1:12345";

    const provider = createSearchViewProvider(extensionUri, getBaseUrl);
    const { view, posted, simulateMessage, simulateVisibilityChange } = createMockView();

    provider.resolveWebviewView(view, {} as never, {} as never);
    simulateMessage({ type: "ready" });

    const countBefore = posted.length;
    simulateVisibilityChange(false);

    expect(posted.length).toBe(countBefore);
  });

  it("batches SSE item events before posting to webview", () => {
    const extensionUri = createMockExtensionUri();
    const getBaseUrl = () => "http://127.0.0.1:12345";

    mockPostStream.mockImplementation((_url: string, _path: string, opts: { onEvent: (e: unknown) => void }) => {
      // Simulate rapid-fire SSE items
      opts.onEvent({ type: "item", data: { id: "1", title: "fn_a", source: "a.ts", line: 1, kind: "fn", score: 0.9 } });
      opts.onEvent({ type: "item", data: { id: "2", title: "fn_b", source: "b.ts", line: 2, kind: "fn", score: 0.8 } });
      opts.onEvent({ type: "item", data: { id: "3", title: "fn_c", source: "c.ts", line: 3, kind: "fn", score: 0.7 } });
      // Don't fire done yet — items should be batched
      return new Promise(() => {
        // never resolves (stream stays open)
      });
    });

    const provider = createSearchViewProvider(extensionUri, getBaseUrl);
    const { view, posted, simulateMessage } = createMockView();

    provider.resolveWebviewView(view, {} as never, {} as never);
    simulateMessage({ type: "ready" });
    posted.length = 0;

    // Trigger search
    simulateMessage({ type: "search", query: "test" } as { type: string });

    // "searching" is posted immediately
    const searchingMessages = posted.filter((m) => (m as { type: string }).type === "searching");
    expect(searchingMessages).toHaveLength(1);

    // Items should NOT be posted yet (batched, waiting for timer)
    const appendMessages = posted.filter((m) => (m as { type: string }).type === "appendItems");
    expect(appendMessages).toHaveLength(0);

    // Advance timer to flush batch
    vi.advanceTimersByTime(100);

    const appendMessagesAfter = posted.filter((m) => (m as { type: string }).type === "appendItems");
    expect(appendMessagesAfter).toHaveLength(1);

    // All 3 items should be in a single batch
    const batchedItems = (appendMessagesAfter[0] as { items: ReadonlyArray<unknown> }).items;
    expect(batchedItems).toHaveLength(3);
  });

  it("resolves relative file paths against workspace root on openFile", async () => {
    const extensionUri = createMockExtensionUri();
    const getBaseUrl = () => "http://127.0.0.1:12345";

    const provider = createSearchViewProvider(extensionUri, getBaseUrl);
    const { view, simulateMessage } = createMockView();

    provider.resolveWebviewView(view, {} as never, {} as never);
    simulateMessage({ type: "ready" });

    // Send openFile with a relative path (as the server returns)
    simulateMessage({ type: "openFile", filePath: "cmd/indexion/explore/cli.mbt" } as unknown as { type: string });

    // Wait for the async openTextDocument + showTextDocument chain
    await vi.advanceTimersByTimeAsync(0);
    await Promise.resolve();

    expect(mockOpenTextDocument).toHaveBeenCalledWith(
      expect.objectContaining({ fsPath: "/workspace/cmd/indexion/explore/cli.mbt" }),
    );
    expect(mockShowTextDocument).toHaveBeenCalled();
  });

  it("handles absolute file paths on openFile", async () => {
    const extensionUri = createMockExtensionUri();
    const getBaseUrl = () => "http://127.0.0.1:12345";

    const provider = createSearchViewProvider(extensionUri, getBaseUrl);
    const { view, simulateMessage } = createMockView();

    provider.resolveWebviewView(view, {} as never, {} as never);
    simulateMessage({ type: "ready" });

    simulateMessage({ type: "openFile", filePath: "/abs/path/file.ts", line: 42 } as unknown as { type: string });

    await vi.advanceTimersByTimeAsync(0);
    await Promise.resolve();

    expect(mockOpenTextDocument).toHaveBeenCalledWith(expect.objectContaining({ fsPath: "/abs/path/file.ts" }));
    expect(mockShowTextDocument).toHaveBeenCalled();
  });

  it("full flow: search → SSE results → click result → file opens at correct line", async () => {
    const extensionUri = createMockExtensionUri();
    const getBaseUrl = () => "http://127.0.0.1:12345";

    // Mock postStream to simulate a search that returns results
    mockPostStream.mockImplementation((_url: string, _path: string, opts: { onEvent: (e: unknown) => void }) => {
      opts.onEvent({ type: "progress", phase: "searching", detail: "Querying..." });
      opts.onEvent({
        type: "item",
        data: {
          id: "1",
          title: "ExploreConfig",
          source: "cmd/indexion/explore/cli.mbt",
          line: 15,
          kind: "Struct",
          score: 0.9,
        },
      });
      opts.onEvent({ type: "done", total: 1 });
      return Promise.resolve();
    });

    const provider = createSearchViewProvider(extensionUri, getBaseUrl);
    const { view, posted, simulateMessage } = createMockView();

    provider.resolveWebviewView(view, {} as never, {} as never);
    simulateMessage({ type: "ready" });
    posted.length = 0;

    // Step 1: User submits a search
    simulateMessage({ type: "search", query: "explore" } as unknown as { type: string });

    // Step 2: SSE stream fires, items are batched
    vi.advanceTimersByTime(100);

    // Verify results were posted to webview
    const appendMessages = posted.filter((m) => (m as { type: string }).type === "appendItems");
    expect(appendMessages.length).toBeGreaterThanOrEqual(1);

    // Step 3: User clicks a result — webview sends openFile with the relative path
    simulateMessage({
      type: "openFile",
      filePath: "cmd/indexion/explore/cli.mbt",
      line: 15,
    } as unknown as { type: string });

    await vi.advanceTimersByTimeAsync(0);
    await Promise.resolve();

    // Step 4: Verify file was opened at the correct resolved path and line 15
    expect(mockOpenTextDocument).toHaveBeenCalledWith(
      expect.objectContaining({ fsPath: "/workspace/cmd/indexion/explore/cli.mbt" }),
    );
    // Line 15 in the API = Position(14, 0) in VSCode (0-indexed)
    expect(mockShowTextDocument).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({
        selection: expect.objectContaining({
          start: expect.objectContaining({ line: 14, character: 0 }),
        }),
      }),
    );
  });
});
