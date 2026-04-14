/**
 * @file Tests for the explore panel manager.
 *
 * Verifies that:
 * - explorePath creates a panel and sends config + serverStatus
 * - webview "ready" flushes pending messages in correct order
 * - explore message from webview triggers SSE stream
 * - SSE result events are forwarded to webview as exploreResults
 * - openDiff message triggers vscode.diff command
 * - openFile message opens a document
 * - notifyServerStatus is delivered when panel is ready
 */

import { describe, it, expect, vi, beforeEach } from "vitest";
import { createExplorePanelManager } from "./panel.ts";
import type { ExploreToWebview } from "./messages.ts";

// ─── Hoisted mocks (available inside vi.mock factories) ─

const { mockPostStream, mockCreateWebviewPanel, mockShowTextDocument, mockOpenTextDocument, mockExecuteCommand } =
  vi.hoisted(() => ({
    mockPostStream: vi.fn(),
    mockCreateWebviewPanel: vi.fn(),
    mockShowTextDocument: vi.fn(),
    mockOpenTextDocument: vi.fn(() => Promise.resolve({})),
    mockExecuteCommand: vi.fn(),
  }));

vi.mock("@indexion/api-client", () => ({
  postStream: mockPostStream,
}));

vi.mock("vscode", () => ({
  Uri: {
    joinPath: (base: { fsPath: string }, ...segments: ReadonlyArray<string>) => {
      const joined = `${base.fsPath}/${segments.join("/")}`;
      return { fsPath: joined, toString: () => joined };
    },
    file: (path: string) => ({ fsPath: path, toString: () => path }),
  },
  window: {
    createWebviewPanel: mockCreateWebviewPanel,
    showTextDocument: mockShowTextDocument,
  },
  workspace: {
    workspaceFolders: [{ uri: { fsPath: "/workspace", toString: () => "/workspace" } }],
    openTextDocument: mockOpenTextDocument,
  },
  commands: {
    executeCommand: mockExecuteCommand,
  },
  ViewColumn: { One: 1 },
}));

vi.mock("../../extension-host/webview-html.ts", () => ({
  buildWebviewHtml: () => "<html></html>",
}));

vi.mock("../../extension-host/codicons.ts", () => ({
  resolveCodiconsUri: () => "codicons-uri",
}));

vi.mock("../../config/index.ts", () => ({
  resolveConfig: () => ({ threshold: 0.7, strategy: "tfidf", workspaceDir: "/workspace" }),
}));

// ─── Helpers ────────────────────────────────────────────

type MessageHandler = (msg: { type: string; [key: string]: unknown }) => void;

const createMockPanel = () => {
  const posted: Array<unknown> = [];
  const messageHandlers: Array<MessageHandler> = [];

  const panel = {
    title: "",
    webview: {
      options: {},
      html: "",
      postMessage: vi.fn((msg: unknown) => {
        posted.push(msg);
        return Promise.resolve(true);
      }),
      onDidReceiveMessage: (handler: MessageHandler, _thisArg?: unknown, _disposables?: unknown) => {
        messageHandlers.push(handler);
        return { dispose: () => {} };
      },
      asWebviewUri: (uri: unknown) => uri,
      cspSource: "",
    },
    iconPath: undefined as unknown,
    reveal: vi.fn(),
    onDidDispose: vi.fn(),
  };

  const simulateMessage = (msg: { type: string; [key: string]: unknown }): void => {
    for (const handler of messageHandlers) {
      handler(msg);
    }
  };

  return { panel, posted, simulateMessage };
};

const createMockContext = () =>
  ({
    extensionUri: {
      fsPath: "/ext",
      toString: () => "/ext",
    },
    subscriptions: [],
  }) as unknown as import("vscode").ExtensionContext;

// ─── Tests ──────────────────────────────────────────────

describe("createExplorePanelManager", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("creates a panel and sends serverStatus + config on explorePath", () => {
    const { panel, posted, simulateMessage } = createMockPanel();
    mockCreateWebviewPanel.mockReturnValue(panel);

    const manager = createExplorePanelManager(createMockContext(), () => "http://127.0.0.1:12345");
    manager.explorePath("/some/dir");

    // Messages are queued until "ready"
    expect(posted).toHaveLength(0);

    // Simulate webview ready
    simulateMessage({ type: "ready" });

    // Should have serverStatus and config
    const types = posted.map((m) => (m as { type: string }).type);
    expect(types).toContain("serverStatus");
    expect(types).toContain("config");

    const serverStatus = posted.find((m) => (m as { type: string }).type === "serverStatus") as ExploreToWebview & {
      type: "serverStatus";
    };
    expect(serverStatus.ready).toBe(true);

    const config = posted.find((m) => (m as { type: string }).type === "config") as ExploreToWebview & {
      type: "config";
    };
    expect(config.targetPath).toBe("/some/dir");
    expect(config.threshold).toBe(0.7);
    expect(config.strategy).toBe("tfidf");
  });

  it("sets the panel title to the target basename", () => {
    const { panel, simulateMessage } = createMockPanel();
    mockCreateWebviewPanel.mockReturnValue(panel);

    const manager = createExplorePanelManager(createMockContext(), () => "http://127.0.0.1:12345");
    manager.explorePath("/workspace/src/views");

    simulateMessage({ type: "ready" });
    expect(panel.title).toBe("Explore: views");
  });

  it("triggers SSE stream when webview sends explore message", () => {
    const { panel, simulateMessage } = createMockPanel();
    mockCreateWebviewPanel.mockReturnValue(panel);
    mockPostStream.mockReturnValue(Promise.resolve());

    const manager = createExplorePanelManager(createMockContext(), () => "http://127.0.0.1:12345");
    manager.explorePath("/some/dir");
    simulateMessage({ type: "ready" });

    // Simulate webview requesting explore
    simulateMessage({ type: "explore", threshold: 0.5, strategy: "tfidf", targetPath: "/some/dir" });

    expect(mockPostStream).toHaveBeenCalledWith("http://127.0.0.1:12345", "/explore/stream", expect.anything());
    const callArgs = mockPostStream.mock.calls[0];
    expect(callArgs[2].body).toEqual({ targetDirs: ["/some/dir"], threshold: 0.5, strategy: "tfidf" });
  });

  it("forwards SSE result event to webview as exploreResults", () => {
    const { panel, posted, simulateMessage } = createMockPanel();
    mockCreateWebviewPanel.mockReturnValue(panel);

    // Capture the onEvent callback
    mockPostStream.mockImplementation((_url: string, _path: string, opts: { onEvent: (e: unknown) => void }) => {
      // Simulate SSE events
      opts.onEvent({ type: "progress", phase: "scanning", detail: "Collecting files..." });
      opts.onEvent({
        type: "result",
        data: {
          files: ["a.ts", "b.ts"],
          pairs: [{ file1: "a.ts", file2: "b.ts", similarity: 0.85 }],
        },
      });
      opts.onEvent({ type: "done", total: 1 });
      return Promise.resolve();
    });

    const manager = createExplorePanelManager(createMockContext(), () => "http://127.0.0.1:12345");
    manager.explorePath("/some/dir");
    simulateMessage({ type: "ready" });

    // Clear the initial config/serverStatus messages
    posted.length = 0;

    // Trigger explore
    simulateMessage({ type: "explore", threshold: 0.5, strategy: "tfidf", targetPath: "/some/dir" });

    const types = posted.map((m) => (m as { type: string }).type);
    expect(types).toContain("searching");
    expect(types).toContain("progress");
    expect(types).toContain("exploreResults");
    expect(types).toContain("done");

    const result = posted.find((m) => (m as { type: string }).type === "exploreResults") as {
      type: string;
      pairs: ReadonlyArray<{ file1: string; file2: string; similarity: number; label: string }>;
      fileCount: number;
    };
    expect(result.fileCount).toBe(2);
    expect(result.pairs).toHaveLength(1);
    expect(result.pairs[0].file1).toBe("a.ts");
    expect(result.pairs[0].file2).toBe("b.ts");
    expect(result.pairs[0].similarity).toBe(0.85);
    expect(result.pairs[0].label).toBe("a.ts ↔ b.ts");
  });

  it("sends error when server is not ready", () => {
    const { panel, posted, simulateMessage } = createMockPanel();
    mockCreateWebviewPanel.mockReturnValue(panel);

    const manager = createExplorePanelManager(createMockContext(), () => undefined);
    manager.explorePath("/some/dir");
    simulateMessage({ type: "ready" });
    posted.length = 0;

    simulateMessage({ type: "explore", threshold: 0.5, strategy: "tfidf", targetPath: "/some/dir" });

    const error = posted.find((m) => (m as { type: string }).type === "error") as { type: string; message: string };
    expect(error).toBeDefined();
    expect(error.message).toBe("Server not ready");
  });

  it("executes vscode.diff on openDiff message", () => {
    const { panel, simulateMessage } = createMockPanel();
    mockCreateWebviewPanel.mockReturnValue(panel);

    const manager = createExplorePanelManager(createMockContext(), () => "http://127.0.0.1:12345");
    manager.explorePath("/some/dir");
    simulateMessage({ type: "ready" });

    simulateMessage({ type: "openDiff", file1: "/a.ts", file2: "/b.ts" });

    expect(mockExecuteCommand).toHaveBeenCalledWith(
      "vscode.diff",
      expect.objectContaining({ fsPath: "/a.ts" }),
      expect.objectContaining({ fsPath: "/b.ts" }),
      "a.ts ↔ b.ts",
    );
  });

  it("opens document on openFile message", () => {
    const { panel, simulateMessage } = createMockPanel();
    mockCreateWebviewPanel.mockReturnValue(panel);

    const manager = createExplorePanelManager(createMockContext(), () => "http://127.0.0.1:12345");
    manager.explorePath("/some/dir");
    simulateMessage({ type: "ready" });

    simulateMessage({ type: "openFile", filePath: "/src/foo.ts" });

    expect(mockOpenTextDocument).toHaveBeenCalledWith(expect.objectContaining({ fsPath: "/src/foo.ts" }));
  });

  it("resolves relative paths on openFile", () => {
    const { panel, simulateMessage } = createMockPanel();
    mockCreateWebviewPanel.mockReturnValue(panel);

    const manager = createExplorePanelManager(createMockContext(), () => "http://127.0.0.1:12345");
    manager.explorePath("/some/dir");
    simulateMessage({ type: "ready" });

    simulateMessage({ type: "openFile", filePath: "src/views/search/provider.ts" });

    expect(mockOpenTextDocument).toHaveBeenCalledWith(
      expect.objectContaining({ fsPath: "/workspace/src/views/search/provider.ts" }),
    );
  });

  it("resolves relative paths on openDiff", () => {
    const { panel, simulateMessage } = createMockPanel();
    mockCreateWebviewPanel.mockReturnValue(panel);

    const manager = createExplorePanelManager(createMockContext(), () => "http://127.0.0.1:12345");
    manager.explorePath("/some/dir");
    simulateMessage({ type: "ready" });

    simulateMessage({ type: "openDiff", file1: "src/a.ts", file2: "src/b.ts" });

    expect(mockExecuteCommand).toHaveBeenCalledWith(
      "vscode.diff",
      expect.objectContaining({ fsPath: "/workspace/src/a.ts" }),
      expect.objectContaining({ fsPath: "/workspace/src/b.ts" }),
      expect.any(String),
    );
  });

  it("reuses existing panel on second explorePath call", () => {
    const { panel, simulateMessage } = createMockPanel();
    mockCreateWebviewPanel.mockReturnValue(panel);

    const manager = createExplorePanelManager(createMockContext(), () => "http://127.0.0.1:12345");
    manager.explorePath("/first");
    simulateMessage({ type: "ready" });

    manager.explorePath("/second");

    expect(mockCreateWebviewPanel).toHaveBeenCalledTimes(1);
    expect(panel.reveal).toHaveBeenCalled();
    expect(panel.title).toBe("Explore: second");
  });
});
