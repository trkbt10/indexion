/**
 * @file Tests for the search webview app component.
 */

import React from "react";
import { render, screen, fireEvent, act } from "@testing-library/react";
import { WebviewProvider } from "../bridge/context.tsx";
import { postedMessages, resetMessages } from "../test-setup.ts";

const renderWithProvider = (ui: React.ReactElement) => render(<WebviewProvider>{ui}</WebviewProvider>);

const postFromHost = (data: unknown): void => {
  act(() => {
    window.dispatchEvent(new MessageEvent("message", { data }));
  });
};

// Dynamic import to ensure test-setup runs first.
let SearchApp: React.FC;

beforeAll(async () => {
  const mod = await import("./app-component.tsx");
  SearchApp = mod.SearchApp;
});

beforeEach(() => {
  resetMessages();
});

describe("SearchApp", () => {
  it("shows waiting message when server is not ready", () => {
    renderWithProvider(<SearchApp />);
    expect(screen.getByText(/Waiting for indexion server/)).toBeInTheDocument();
  });

  it("hides waiting message after serverStatus ready", () => {
    renderWithProvider(<SearchApp />);
    postFromHost({ type: "serverStatus", ready: true });
    expect(screen.queryByText(/Waiting for indexion server/)).not.toBeInTheDocument();
  });

  it("sends search message on Enter", () => {
    renderWithProvider(<SearchApp />);
    postFromHost({ type: "serverStatus", ready: true });

    const input = screen.getByPlaceholderText("Search code, wiki, docs...");
    fireEvent.change(input, { target: { value: "test query" } });
    fireEvent.keyDown(input, { key: "Enter" });

    expect(postedMessages).toContainEqual({ type: "search", query: "test query" });
  });

  it("sends grep message in grep mode", () => {
    renderWithProvider(<SearchApp />);
    postFromHost({ type: "serverStatus", ready: true });

    // Switch to grep mode
    const grepButton = screen.getByTitle("KGF Token Grep");
    fireEvent.click(grepButton);

    const input = screen.getByPlaceholderText(/Token pattern/);
    fireEvent.change(input, { target: { value: "pub fn Ident" } });
    fireEvent.keyDown(input, { key: "Enter" });

    expect(postedMessages).toContainEqual({ type: "grep", pattern: "pub fn Ident" });
  });

  it("sends digest message in digest mode", () => {
    renderWithProvider(<SearchApp />);
    postFromHost({ type: "serverStatus", ready: true });

    const digestButton = screen.getByTitle("Search by Purpose");
    fireEvent.click(digestButton);

    const input = screen.getByPlaceholderText(/Describe function purpose/);
    fireEvent.change(input, { target: { value: "parse config" } });
    fireEvent.keyDown(input, { key: "Enter" });

    expect(postedMessages).toContainEqual({ type: "digest", query: "parse config" });
  });

  it("displays search results grouped by file", () => {
    renderWithProvider(<SearchApp />);
    postFromHost({ type: "serverStatus", ready: true });
    postFromHost({
      type: "appendItems",
      items: [
        { label: "fn_a", description: "src/a.ts:10", filePath: "src/a.ts", line: 10, icon: "symbol-method" },
        { label: "fn_b", description: "src/a.ts:20", filePath: "src/a.ts", line: 20, icon: "symbol-method" },
        { label: "fn_c", description: "src/b.ts:5", filePath: "src/b.ts", line: 5, icon: "symbol-method" },
      ],
    });

    expect(screen.getByText("fn_a")).toBeInTheDocument();
    expect(screen.getByText("fn_b")).toBeInTheDocument();
    expect(screen.getByText("fn_c")).toBeInTheDocument();
  });

  it("shows no results message when searched but empty", () => {
    renderWithProvider(<SearchApp />);
    postFromHost({ type: "serverStatus", ready: true });
    postFromHost({ type: "searching" });
    postFromHost({ type: "done", total: 0 });
    expect(screen.getByText("No results found.")).toBeInTheDocument();
  });

  it("renders data-line attribute on child tree items", () => {
    const { container } = renderWithProvider(<SearchApp />);
    postFromHost({ type: "serverStatus", ready: true });
    postFromHost({
      type: "appendItems",
      items: [
        { label: "fn_a", description: "src/a.ts:10", filePath: "src/a.ts", line: 10, icon: "symbol-method" },
        { label: "fn_b", description: "src/a.ts:20", filePath: "src/a.ts", line: 20, icon: "symbol-method" },
      ],
    });

    const items = container.querySelectorAll("[data-line]");
    expect(items.length).toBe(2);
    expect(items[0].getAttribute("data-line")).toBe("10");
    expect(items[1].getAttribute("data-line")).toBe("20");
    expect(items[0].getAttribute("data-file-path")).toBe("src/a.ts");
  });

  it("sends openFile with line number on tree item select", () => {
    const { container } = renderWithProvider(<SearchApp />);
    postFromHost({ type: "serverStatus", ready: true });
    postFromHost({
      type: "appendItems",
      items: [{ label: "my_fn", description: "src/x.ts:42", filePath: "src/x.ts", line: 42, icon: "symbol-method" }],
    });

    // Find the tree item with data-file-path and simulate vsc-tree-select
    const treeItem = container.querySelector('[data-file-path="src/x.ts"][data-line="42"]');
    expect(treeItem).not.toBeNull();

    const tree = container.querySelector("vscode-tree");
    expect(tree).not.toBeNull();

    act(() => {
      tree!.dispatchEvent(new CustomEvent("vsc-tree-select", { detail: [treeItem] }));
    });

    expect(postedMessages).toContainEqual({ type: "openFile", filePath: "src/x.ts", line: 42 });
  });

  it("shows error message", () => {
    renderWithProvider(<SearchApp />);
    postFromHost({ type: "error", message: "Something went wrong" });
    expect(screen.getByText("Something went wrong")).toBeInTheDocument();
  });

  it("clears results on Escape", () => {
    renderWithProvider(<SearchApp />);
    postFromHost({ type: "serverStatus", ready: true });
    postFromHost({
      type: "appendItems",
      items: [{ label: "fn_x", description: "x.ts:1", filePath: "x.ts", line: 1, icon: "symbol-method" }],
    });
    expect(screen.getByText("fn_x")).toBeInTheDocument();

    const input = screen.getByPlaceholderText("Search code, wiki, docs...");
    fireEvent.keyDown(input, { key: "Escape" });
    expect(screen.queryByText("fn_x")).not.toBeInTheDocument();
  });
});
