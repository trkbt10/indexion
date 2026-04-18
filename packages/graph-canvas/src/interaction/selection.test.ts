/**
 * @file Contract tests for the selection reducer.
 *
 * The reducer is the single source of truth for every selection /
 * focus transition. These tests pin down the visible behaviour so it
 * can't silently drift — any future refactor has to keep each of
 * these transitions producing the documented state + effect pair.
 */

import { describe, expect, it } from "vitest";
import type { SelectionState, ViewEdge, ViewNode } from "../types.ts";
import { applySelectionIntent, createSelectionState } from "./selection.ts";

function node(id: string): ViewNode {
  return {
    id,
    label: id,
    kind: "module",
    group: "",
    file: null,
    doc: null,
    metadata: {},
    x: 0,
    y: 0,
    z: 0,
    vx: 0,
    vy: 0,
    vz: 0,
    pinned: false,
  };
}

function edge(source: ViewNode, target: ViewNode): ViewEdge {
  return {
    sourceId: source.id,
    targetId: target.id,
    kind: "depends_on",
    metadata: {},
    source,
    target,
  };
}

function state(): SelectionState {
  return createSelectionState();
}

describe("applySelectionIntent — click", () => {
  it("clicking a node (no shift) selects exactly that node", () => {
    const a = node("a");
    const { state: next, effect } = applySelectionIntent({
      state: state(),
      intent: { type: "click", node: a, shift: false },
      edges: [],
    });
    expect(next.selected.size).toBe(1);
    expect(next.selected.has("a")).toBe(true);
    expect(effect.type).toBe("none");
  });

  it("clicking with shift toggles membership", () => {
    const a = node("a");
    const start = state();
    start.selected.add("b");
    const { state: added } = applySelectionIntent({
      state: start,
      intent: { type: "click", node: a, shift: true },
      edges: [],
    });
    expect(added.selected.has("a")).toBe(true);
    expect(added.selected.has("b")).toBe(true);
    const { state: removed } = applySelectionIntent({
      state: added,
      intent: { type: "click", node: a, shift: true },
      edges: [],
    });
    expect(removed.selected.has("a")).toBe(false);
    expect(removed.selected.has("b")).toBe(true);
  });

  it("clicking empty space (no shift) clears selection", () => {
    const start = state();
    start.selected.add("a");
    const { state: next } = applySelectionIntent({
      state: start,
      intent: { type: "click", node: null, shift: false },
      edges: [],
    });
    expect(next.selected.size).toBe(0);
  });

  it("clicking empty space with shift is a no-op on state", () => {
    const start = state();
    start.selected.add("a");
    const { state: next } = applySelectionIntent({
      state: start,
      intent: { type: "click", node: null, shift: true },
      edges: [],
    });
    expect(next).toBe(start);
  });
});

describe("applySelectionIntent — double-click", () => {
  it("dbl-click on a new node enters focus mode + focus-on-node effect", () => {
    const a = node("a");
    const b = node("b");
    const { state: next, effect } = applySelectionIntent({
      state: state(),
      intent: { type: "double-click", node: a },
      edges: [edge(a, b)],
    });
    expect(next.focusCenter).toBe("a");
    expect(next.focusNeighbors.has("a")).toBe(true);
    expect(next.focusNeighbors.has("b")).toBe(true);
    expect(effect).toEqual({ type: "focus-on-node", nodeId: "a" });
  });

  it("dbl-click on the focus centre itself exits focus + fit-to-view", () => {
    const a = node("a");
    const start = state();
    (start as { focusCenter: string | null }).focusCenter = "a";
    start.focusNeighbors.add("a");
    const { state: next, effect } = applySelectionIntent({
      state: start,
      intent: { type: "double-click", node: a },
      edges: [],
    });
    expect(next.focusCenter).toBeNull();
    expect(next.focusNeighbors.size).toBe(0);
    expect(effect.type).toBe("fit-to-view");
  });

  it("dbl-click on empty space always fit-to-views + clears focus", () => {
    const start = state();
    (start as { focusCenter: string | null }).focusCenter = "a";
    start.focusNeighbors.add("a");
    const { state: next, effect } = applySelectionIntent({
      state: start,
      intent: { type: "double-click", node: null },
      edges: [],
    });
    expect(next.focusCenter).toBeNull();
    expect(effect.type).toBe("fit-to-view");
  });
});

describe("applySelectionIntent — clear", () => {
  it("clears selection and focus when non-empty", () => {
    const start = state();
    start.selected.add("a");
    (start as { focusCenter: string | null }).focusCenter = "b";
    const { state: next } = applySelectionIntent({
      state: start,
      intent: { type: "clear" },
      edges: [],
    });
    expect(next.selected.size).toBe(0);
    expect(next.focusCenter).toBeNull();
  });

  it("clear on already-empty state returns same reference", () => {
    const start = state();
    const { state: next } = applySelectionIntent({
      state: start,
      intent: { type: "clear" },
      edges: [],
    });
    expect(next).toBe(start);
  });
});

describe("idempotence", () => {
  it("same click twice on same node returns the same state reference the second time", () => {
    const a = node("a");
    const first = applySelectionIntent({
      state: state(),
      intent: { type: "click", node: a, shift: false },
      edges: [],
    }).state;
    const second = applySelectionIntent({
      state: first,
      intent: { type: "click", node: a, shift: false },
      edges: [],
    }).state;
    expect(second).toBe(first);
  });
});
