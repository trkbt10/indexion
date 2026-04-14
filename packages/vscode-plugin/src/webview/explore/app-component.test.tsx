/**
 * @file Tests for the explore webview app component.
 */

import React from "react";
import { render, screen, fireEvent, act } from "@testing-library/react";
import { WebviewProvider } from "../bridge/context.tsx";
import { postedMessages, resetMessages } from "../test-setup.ts";
import type { ComparisonStrategy } from "@indexion/api-client";

const renderWithProvider = (ui: React.ReactElement) => render(<WebviewProvider>{ui}</WebviewProvider>);

const postFromHost = (data: unknown): void => {
  act(() => {
    window.dispatchEvent(new MessageEvent("message", { data }));
  });
};

// Dynamic import to ensure test-setup runs first.
let ExploreApp: React.FC;

beforeAll(async () => {
  const mod = await import("./app-component.tsx");
  ExploreApp = mod.ExploreApp;
});

beforeEach(() => {
  resetMessages();
});

describe("ExploreApp", () => {
  it("shows waiting message when server is not ready", () => {
    renderWithProvider(<ExploreApp />);
    expect(screen.getByText(/Waiting for indexion server/)).toBeInTheDocument();
  });

  it("hides waiting message after serverStatus ready", () => {
    renderWithProvider(<ExploreApp />);
    postFromHost({ type: "serverStatus", ready: true });
    expect(screen.queryByText(/Waiting for indexion server/)).not.toBeInTheDocument();
  });

  it("displays target path from config message", () => {
    renderWithProvider(<ExploreApp />);
    postFromHost({ type: "serverStatus", ready: true });
    postFromHost({
      type: "config",
      threshold: 0.7,
      strategy: "tfidf" as ComparisonStrategy,
      targetPath: "/workspace/src/views",
    });
    expect(screen.getByText("views")).toBeInTheDocument();
  });

  it("auto-runs explore when config arrives with server ready", () => {
    renderWithProvider(<ExploreApp />);
    postFromHost({ type: "serverStatus", ready: true });
    postFromHost({
      type: "config",
      threshold: 0.7,
      strategy: "tfidf" as ComparisonStrategy,
      targetPath: "/workspace/src",
    });

    expect(postedMessages).toContainEqual({
      type: "explore",
      threshold: 0.7,
      strategy: "tfidf",
      targetPath: "/workspace/src",
    });
  });

  it("displays explore results", () => {
    renderWithProvider(<ExploreApp />);
    postFromHost({ type: "serverStatus", ready: true });
    postFromHost({
      type: "exploreResults",
      pairs: [{ file1: "/a/foo.ts", file2: "/a/bar.ts", similarity: 0.85, label: "foo.ts ↔ bar.ts" }],
      fileCount: 2,
    });

    expect(screen.getByText("foo.ts ↔ bar.ts")).toBeInTheDocument();
    expect(screen.getByText("1 pairs in 2 files")).toBeInTheDocument();
  });

  it("sends openDiff when pair is clicked", () => {
    renderWithProvider(<ExploreApp />);
    postFromHost({ type: "serverStatus", ready: true });
    postFromHost({
      type: "exploreResults",
      pairs: [{ file1: "/a.ts", file2: "/b.ts", similarity: 0.9, label: "a.ts ↔ b.ts" }],
      fileCount: 2,
    });

    fireEvent.click(screen.getByText("a.ts ↔ b.ts"));
    expect(postedMessages).toContainEqual({ type: "openDiff", file1: "/a.ts", file2: "/b.ts" });
  });

  it("shows no results message when explored but no pairs found", () => {
    renderWithProvider(<ExploreApp />);
    postFromHost({ type: "serverStatus", ready: true });
    postFromHost({ type: "exploreResults", pairs: [], fileCount: 5 });
    expect(screen.getByText("No similar files found.")).toBeInTheDocument();
  });

  it("shows error message", () => {
    renderWithProvider(<ExploreApp />);
    postFromHost({ type: "error", message: "Server not ready" });
    expect(screen.getByText("Server not ready")).toBeInTheDocument();
  });

  it("shows progress detail during analysis", () => {
    renderWithProvider(<ExploreApp />);
    postFromHost({ type: "serverStatus", ready: true });
    postFromHost({ type: "searching" });
    postFromHost({ type: "progress", phase: "comparing", detail: "Analyzing similarity..." });
    expect(screen.getByText("Analyzing similarity...")).toBeInTheDocument();
  });
});
