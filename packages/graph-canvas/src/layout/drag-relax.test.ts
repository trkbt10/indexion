/**
 * @file Contract tests for the drag-time local relaxation.
 *
 * Dragging a node should not trigger a full layout re-solve — we
 * apply a tiny one-step nudge to its immediate neighbours so edges
 * don't stretch awkwardly. Pinned neighbours stay put; neighbours
 * already inside the spring rest length don't move.
 */

import { describe, expect, it } from "vitest";
import type { ViewEdge, ViewGraph, ViewNode } from "../types.ts";
import { relaxNeighbours } from "./drag-relax.ts";

function mkNode(
  id: string,
  pos: { x: number; y: number; z: number },
): ViewNode {
  return {
    id,
    label: id,
    kind: "module",
    group: "",
    file: null,
    doc: null,
    metadata: {},
    x: pos.x,
    y: pos.y,
    z: pos.z,
    vx: 0,
    vy: 0,
    vz: 0,
    pinned: false,
  };
}

function mkEdge(source: ViewNode, target: ViewNode): ViewEdge {
  return {
    sourceId: source.id,
    targetId: target.id,
    kind: "depends_on",
    metadata: {},
    source,
    target,
  };
}

function mkGraph(nodes: ViewNode[], edges: ViewEdge[]): ViewGraph {
  const nodeIndex = new Map<string, ViewNode>();
  for (const n of nodes) {
    nodeIndex.set(n.id, n);
  }
  return { nodes, edges, nodeIndex };
}

describe("relaxNeighbours", () => {
  it("pulls a far neighbour closer to the dragged node", () => {
    // a at origin, b at distance 500 — far beyond REST_LENGTH (80).
    // b should move toward a.
    const a = mkNode("a", { x: 0, y: 0, z: 0 });
    const b = mkNode("b", { x: 500, y: 0, z: 0 });
    const graph = mkGraph([a, b], [mkEdge(a, b)]);
    const dx0 = b.x - a.x;
    relaxNeighbours(graph, a);
    const dx1 = b.x - a.x;
    expect(dx1).toBeLessThan(dx0);
    expect(dx1).toBeGreaterThan(0); // still on the positive side
  });

  it("leaves a neighbour inside rest length alone", () => {
    // b at distance 40, less than REST_LENGTH=80 → no nudge.
    const a = mkNode("a", { x: 0, y: 0, z: 0 });
    const b = mkNode("b", { x: 40, y: 0, z: 0 });
    const graph = mkGraph([a, b], [mkEdge(a, b)]);
    relaxNeighbours(graph, a);
    expect(b.x).toBe(40);
    expect(b.y).toBe(0);
    expect(b.z).toBe(0);
  });

  it("does not move pinned neighbours", () => {
    const a = mkNode("a", { x: 0, y: 0, z: 0 });
    const b = mkNode("b", { x: 500, y: 0, z: 0 });
    b.pinned = true;
    const graph = mkGraph([a, b], [mkEdge(a, b)]);
    relaxNeighbours(graph, a);
    expect(b.x).toBe(500);
  });

  it("ignores edges that don't touch the dragged node", () => {
    // a drag; b—c edge must not move b or c.
    const a = mkNode("a", { x: 0, y: 0, z: 0 });
    const b = mkNode("b", { x: 500, y: 0, z: 0 });
    const c = mkNode("c", { x: 600, y: 0, z: 0 });
    const graph = mkGraph([a, b, c], [mkEdge(b, c)]);
    const beforeB = { x: b.x, y: b.y, z: b.z };
    const beforeC = { x: c.x, y: c.y, z: c.z };
    relaxNeighbours(graph, a);
    expect(b).toMatchObject(beforeB);
    expect(c).toMatchObject(beforeC);
  });

  it("works symmetrically whether the dragged node is source or target", () => {
    const a = mkNode("a", { x: 0, y: 0, z: 0 });
    const b = mkNode("b", { x: 500, y: 0, z: 0 });
    // Edge direction reversed — a is target, b is source.
    const graph = mkGraph([a, b], [mkEdge(b, a)]);
    const before = b.x;
    relaxNeighbours(graph, a);
    expect(b.x).toBeLessThan(before);
  });

  it("keeps positions finite even for extreme distances", () => {
    const a = mkNode("a", { x: 0, y: 0, z: 0 });
    const b = mkNode("b", { x: 1e6, y: 1e6, z: 1e6 });
    const graph = mkGraph([a, b], [mkEdge(a, b)]);
    relaxNeighbours(graph, a);
    expect(Number.isFinite(b.x)).toBe(true);
    expect(Number.isFinite(b.y)).toBe(true);
    expect(Number.isFinite(b.z)).toBe(true);
  });

  it("does not move the dragged node itself", () => {
    const a = mkNode("a", { x: 10, y: 20, z: 30 });
    const b = mkNode("b", { x: 500, y: 0, z: 0 });
    const graph = mkGraph([a, b], [mkEdge(a, b)]);
    relaxNeighbours(graph, a);
    expect(a.x).toBe(10);
    expect(a.y).toBe(20);
    expect(a.z).toBe(30);
  });

  it("clamps per-frame movement to a maximum step", () => {
    // Far neighbour: 5000 units away. Without a step cap, the spring
    // pull would yank it hundreds of units in one frame, producing
    // the visible "neighbours fly to the cursor" failure mode that
    // the previous design exhibited.
    const a = mkNode("a", { x: 0, y: 0, z: 0 });
    const b = mkNode("b", { x: 5000, y: 0, z: 0 });
    const graph = mkGraph([a, b], [mkEdge(a, b)]);
    relaxNeighbours(graph, a);
    const movedBy = 5000 - b.x;
    // The cap is 18; allow some slack but anything above ~30 is a
    // regression of the cap.
    expect(movedBy).toBeGreaterThan(0);
    expect(movedBy).toBeLessThanOrEqual(20);
  });

  it("repels neighbour pairs that overlap so they don't collapse onto each other", () => {
    // Two neighbours on top of each other at the same spot, both
    // far from the dragged node. The spring would pull both toward
    // `a` along the same vector → without repulsion they'd stay
    // overlapped. With repulsion, they should end up separated.
    const a = mkNode("a", { x: 0, y: 0, z: 0 });
    const b = mkNode("b", { x: 200, y: 1, z: 0 });
    const c = mkNode("c", { x: 200, y: -1, z: 0 });
    const graph = mkGraph([a, b, c], [mkEdge(a, b), mkEdge(a, c)]);
    relaxNeighbours(graph, a);
    const sep = Math.hypot(b.x - c.x, b.y - c.y, b.z - c.z);
    // Initially separated by ~2 units; after repulsion the
    // separation should grow (towards REPEL_DISTANCE = 60).
    expect(sep).toBeGreaterThan(2);
  });

  it("does not collapse a long fan of neighbours onto the dragged node over many frames", () => {
    // The original bug: dragging a hub repeatedly pulled every 1-hop
    // neighbour ever-closer until they stacked on the cursor. Repeat
    // many drag frames and assert that some pair-wise separation
    // remains.
    const hub = mkNode("hub", { x: 0, y: 0, z: 0 });
    const fan: ViewNode[] = [];
    const edges: ViewEdge[] = [];
    const N = 8;
    for (let i = 0; i < N; i++) {
      const angle = (2 * Math.PI * i) / N;
      const n = mkNode(`n${i}`, {
        x: Math.cos(angle) * 600,
        y: Math.sin(angle) * 600,
        z: 0,
      });
      fan.push(n);
      edges.push(mkEdge(hub, n));
    }
    const graph = mkGraph([hub, ...fan], edges);
    for (let frame = 0; frame < 200; frame++) {
      relaxNeighbours(graph, hub);
    }
    // After many frames the fan must NOT be a single point. Compute
    // the max pairwise distance and require it to stay above some
    // floor that's well clear of "all collapsed".
    let maxSep = 0;
    for (let i = 0; i < fan.length; i++) {
      for (let j = i + 1; j < fan.length; j++) {
        const d = Math.hypot(
          fan[i]!.x - fan[j]!.x,
          fan[i]!.y - fan[j]!.y,
          fan[i]!.z - fan[j]!.z,
        );
        if (d > maxSep) maxSep = d;
      }
    }
    // REPEL_DISTANCE = 60, so the equilibrium ring should have
    // separation at least on that order.
    expect(maxSep).toBeGreaterThan(40);
  });
});
