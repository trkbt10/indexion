/**
 * @file Contract tests for edge-aware slot ordering.
 *
 * The hierarchical layout picks Fibonacci shell positions first,
 * then assigns paths to slots so strongly-connected clusters sit at
 * neighbouring slots. If the ordering layer is broken (slots picked
 * randomly, refinement not reducing cost, orderByConnectivity losing
 * a fragment), the "constellation" metaphor collapses — related
 * clusters end up at opposite poles and edges cross the world.
 */

import { describe, expect, it } from "vitest";
import type { ViewEdge, ViewNode } from "../../types.ts";
import { computeHierarchy } from "../hierarchy.ts";
import type { Vec3 } from "../geometry.ts";
import {
  addPair,
  buildAdjacencyIndex,
  buildInterClusterEdgeIndex,
  orderByConnectivity,
  orderLeavesByAdjacency,
  refineLeafOrderBySwaps,
  refineOrderByPairwiseSwaps,
} from "./ordering.ts";

function mkNode(id: string, file?: string): ViewNode {
  return {
    id,
    label: id,
    kind: "module",
    group: "",
    file: file ?? null,
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

describe("buildAdjacencyIndex", () => {
  it("builds bidirectional adjacency for every edge", () => {
    const a = mkNode("a");
    const b = mkNode("b");
    const c = mkNode("c");
    const index = buildAdjacencyIndex([mkEdge(a, b), mkEdge(b, c)]);
    expect(index.get("a")).toEqual(["b"]);
    expect(index.get("c")).toEqual(["b"]);
    expect(new Set(index.get("b"))).toEqual(new Set(["a", "c"]));
  });

  it("preserves parallel edges as duplicate neighbours", () => {
    // Parallel edges (same pair, multiple kinds) contribute to
    // weight calculations; dedup would undercount connectivity.
    const a = mkNode("a");
    const b = mkNode("b");
    const index = buildAdjacencyIndex([mkEdge(a, b), mkEdge(a, b)]);
    expect(index.get("a")).toEqual(["b", "b"]);
  });

  it("returns empty map for empty edge list", () => {
    expect(buildAdjacencyIndex([]).size).toBe(0);
  });
});

describe("addPair", () => {
  it("accumulates weights across both directions", () => {
    const idx = new Map<string, Map<string, number>>();
    addPair(idx, "a", "b");
    addPair(idx, "a", "b");
    addPair(idx, "a", "c");
    expect(idx.get("a")!.get("b")).toBe(2);
    expect(idx.get("a")!.get("c")).toBe(1);
  });
});

describe("buildInterClusterEdgeIndex", () => {
  it("accumulates edge weight at every shared-ancestor depth", () => {
    // Nodes x, y share ancestors at depth 0 ("src") but differ at
    // depth 1. An edge x—y contributes weight to ("src/a","src/b")
    // and symmetrically ("src/b","src/a"). The root pair "src"↔"src"
    // is skipped (same ancestor — no inter-cluster contribution).
    const x = mkNode("src/a/x.mbt", "src/a/x.mbt");
    const y = mkNode("src/b/y.mbt", "src/b/y.mbt");
    const assignment = computeHierarchy([x, y]);
    const idx = buildInterClusterEdgeIndex({
      edges: [mkEdge(x, y)],
      assignment,
    });
    expect(idx.get("src/a")?.get("src/b")).toBe(1);
    expect(idx.get("src/b")?.get("src/a")).toBe(1);
  });

  it("skips the innermost leaf level — index is a cluster index, not a node index", () => {
    // x and y live under the same folder. All ancestor paths
    // match; only the leaf path (the node id) differs. The index
    // should therefore stay empty — there's no cluster level at
    // which these nodes cross a boundary.
    const x = mkNode("pkg/foo/x");
    const y = mkNode("pkg/foo/y");
    const assignment = computeHierarchy([x, y]);
    const idx = buildInterClusterEdgeIndex({
      edges: [mkEdge(x, y)],
      assignment,
    });
    expect(idx.size).toBe(0);
  });

  it("does not emit weight at the leaf depth when ancestors diverge earlier", () => {
    // x and y diverge at depth 1 (a vs b). Depth 2 is their
    // individual ids — not a cluster. The index should only
    // record the depth-1 pair.
    const x = mkNode("src/a/x.mbt", "src/a/x.mbt");
    const y = mkNode("src/b/y.mbt", "src/b/y.mbt");
    const assignment = computeHierarchy([x, y]);
    const idx = buildInterClusterEdgeIndex({
      edges: [mkEdge(x, y)],
      assignment,
    });
    expect(idx.get("src/a")?.get("src/b")).toBe(1);
    expect(idx.get("src/a/x.mbt")).toBeUndefined();
    expect(idx.get("src/b/y.mbt")).toBeUndefined();
  });
});

describe("orderByConnectivity", () => {
  it("short-circuits for lists of ≤ 2 entries", () => {
    const idx = new Map<string, Map<string, number>>();
    expect(orderByConnectivity([], idx)).toEqual([]);
    expect(orderByConnectivity(["a"], idx)).toEqual(["a"]);
    expect(orderByConnectivity(["a", "b"], idx)).toEqual(["a", "b"]);
  });

  it("places the strongest tail neighbour next", () => {
    const idx = new Map<string, Map<string, number>>();
    // a strongly connected to c, weakly to b. Expected order:
    // a, c, b (c picked as a's best, then b remains).
    addPair(idx, "a", "c");
    addPair(idx, "a", "c");
    addPair(idx, "a", "c");
    addPair(idx, "a", "b");
    addPair(idx, "c", "a");
    addPair(idx, "c", "a");
    addPair(idx, "c", "a");
    addPair(idx, "b", "a");
    const order = orderByConnectivity(["a", "b", "c"], idx);
    expect(order[0]).toBe("a");
    expect(order[1]).toBe("c");
    expect(order[2]).toBe("b");
  });

  it("falls back to most-connected-to-placed when tail has no neighbours", () => {
    const idx = new Map<string, Map<string, number>>();
    // a is alone. b & c have no tie to a but c has tie to b.
    // After placing a we have no tail-row choices; fallback picks
    // the candidate with highest total weight to `placed` (which
    // is only {a}, so zero for both). Either is accepted as long
    // as both end up in the output.
    const order = orderByConnectivity(["a", "b", "c", "d"], idx);
    expect(new Set(order)).toEqual(new Set(["a", "b", "c", "d"]));
    expect(order[0]).toBe("a");
    expect(order.length).toBe(4);
  });

  it("never loses or duplicates a path", () => {
    const idx = new Map<string, Map<string, number>>();
    addPair(idx, "a", "b");
    addPair(idx, "c", "d");
    const input = ["a", "b", "c", "d", "e"];
    const out = orderByConnectivity(input, idx);
    expect(out.length).toBe(input.length);
    expect(new Set(out)).toEqual(new Set(input));
  });
});

describe("refineOrderByPairwiseSwaps", () => {
  /** Two slots facing each other on a small shell. Easy to reason
   *  about whether swapping reduces weighted squared distance. */
  function twoSlotFixture(): {
    ordered: string[];
    positions: readonly Vec3[];
    interCluster: Map<string, Map<string, number>>;
  } {
    const positions: Vec3[] = [
      { x: 10, y: 0, z: 0 },
      { x: -10, y: 0, z: 0 },
      { x: 0, y: 10, z: 0 },
      { x: 0, y: -10, z: 0 },
    ];
    const interCluster = new Map<string, Map<string, number>>();
    // a-b is very strong; the refinement should keep them adjacent.
    addPair(interCluster, "a", "b");
    addPair(interCluster, "a", "b");
    addPair(interCluster, "b", "a");
    addPair(interCluster, "b", "a");
    return { ordered: ["a", "c", "b", "d"], positions, interCluster };
  }

  it("reduces total pairwise-distance × weight cost", () => {
    const { ordered, positions, interCluster } = twoSlotFixture();
    const pre = slotCostSum(ordered, positions, interCluster);
    refineOrderByPairwiseSwaps({ ordered, positions, interCluster });
    const post = slotCostSum(ordered, positions, interCluster);
    expect(post).toBeLessThanOrEqual(pre);
  });

  it("never loses or duplicates any element", () => {
    const { ordered, positions, interCluster } = twoSlotFixture();
    const before = new Set(ordered);
    refineOrderByPairwiseSwaps({ ordered, positions, interCluster });
    expect(new Set(ordered)).toEqual(before);
  });

  it("is a no-op on 2 slots (no swap reduces a single-pair cost)", () => {
    const ordered = ["a", "b"];
    const positions: Vec3[] = [
      { x: 10, y: 0, z: 0 },
      { x: -10, y: 0, z: 0 },
    ];
    const interCluster = new Map<string, Map<string, number>>();
    addPair(interCluster, "a", "b");
    refineOrderByPairwiseSwaps({ ordered, positions, interCluster });
    expect(ordered).toEqual(["a", "b"]);
  });
});

function slotCostSum(
  ordered: readonly string[],
  positions: readonly Vec3[],
  interCluster: ReadonlyMap<string, ReadonlyMap<string, number>>,
): number {
  let sum = 0;
  for (let i = 0; i < ordered.length; i++) {
    for (let j = i + 1; j < ordered.length; j++) {
      const w = interCluster.get(ordered[i]!)?.get(ordered[j]!) ?? 0;
      if (w === 0) {
        continue;
      }
      const a = positions[i]!;
      const b = positions[j]!;
      const dx = a.x - b.x;
      const dy = a.y - b.y;
      const dz = a.z - b.z;
      sum += w * (dx * dx + dy * dy + dz * dz);
    }
  }
  return sum;
}

describe("refineLeafOrderBySwaps", () => {
  it("reduces total neighbour squared distance", () => {
    const n = (id: string) => mkNode(id);
    const nodes = [n("a"), n("b"), n("c"), n("d")];
    const positions: Vec3[] = [
      { x: 10, y: 0, z: 0 },
      { x: -10, y: 0, z: 0 },
      { x: 0, y: 10, z: 0 },
      { x: 0, y: -10, z: 0 },
    ];
    const edges = new Map<string, readonly string[]>([
      ["a", ["b"]],
      ["b", ["a"]],
      ["c", ["d"]],
      ["d", ["c"]],
    ]);
    const pre = leafCost(nodes, positions, edges);
    refineLeafOrderBySwaps({ nodes, positions, edges });
    const post = leafCost(nodes, positions, edges);
    expect(post).toBeLessThanOrEqual(pre);
  });

  it("never loses or duplicates a node", () => {
    const nodes = [mkNode("a"), mkNode("b"), mkNode("c"), mkNode("d")];
    const positions: Vec3[] = [
      { x: 0, y: 0, z: 0 },
      { x: 1, y: 0, z: 0 },
      { x: 2, y: 0, z: 0 },
      { x: 3, y: 0, z: 0 },
    ];
    const edges = new Map<string, readonly string[]>([["a", ["b"]]]);
    refineLeafOrderBySwaps({ nodes, positions, edges });
    expect(nodes.map((n) => n.id).sort()).toEqual(["a", "b", "c", "d"]);
  });
});

function leafCost(
  nodes: readonly ViewNode[],
  positions: readonly Vec3[],
  edges: ReadonlyMap<string, readonly string[]>,
): number {
  const idx = new Map(nodes.map((n, i) => [n.id, i]));
  let sum = 0;
  for (let i = 0; i < nodes.length; i++) {
    const ns = edges.get(nodes[i]!.id) ?? [];
    for (const other of ns) {
      const j = idx.get(other);
      if (j === undefined) {
        continue;
      }
      const a = positions[i]!;
      const b = positions[j]!;
      const dx = a.x - b.x;
      const dy = a.y - b.y;
      const dz = a.z - b.z;
      sum += dx * dx + dy * dy + dz * dz;
    }
  }
  return sum;
}

describe("orderLeavesByAdjacency", () => {
  it("short-circuits for ≤ 2 nodes", () => {
    const a = mkNode("a");
    const b = mkNode("b");
    const edges = new Map<string, readonly string[]>([["a", ["b"]]]);
    expect(orderLeavesByAdjacency([], edges)).toEqual([]);
    expect(orderLeavesByAdjacency([a], edges).map((n) => n.id)).toEqual(["a"]);
    const two = orderLeavesByAdjacency([a, b], edges).map((n) => n.id);
    expect(two.sort()).toEqual(["a", "b"]);
  });

  it("places the highest in-set-degree leaf first", () => {
    // b has 2 connections inside the set (to a, c), a has 1, c has 1.
    const a = mkNode("a");
    const b = mkNode("b");
    const c = mkNode("c");
    const edges = new Map<string, readonly string[]>([
      ["a", ["b"]],
      ["b", ["a", "c"]],
      ["c", ["b"]],
    ]);
    const out = orderLeavesByAdjacency([a, b, c], edges);
    expect(out[0]!.id).toBe("b");
  });

  it("walks connected neighbours first, falling back on disconnected", () => {
    const a = mkNode("a");
    const b = mkNode("b");
    const c = mkNode("c");
    const d = mkNode("d"); // disconnected
    const edges = new Map<string, readonly string[]>([
      ["a", ["b"]],
      ["b", ["a", "c"]],
      ["c", ["b"]],
    ]);
    const out = orderLeavesByAdjacency([a, b, c, d], edges).map((n) => n.id);
    // b picked first (max degree). From b, walk to a or c first.
    // d must be placed last via the fallback branch.
    expect(out[0]).toBe("b");
    expect(out[out.length - 1]).toBe("d");
  });

  it("returns every input node exactly once", () => {
    const nodes = ["a", "b", "c", "d", "e"].map((id) => mkNode(id));
    const edges = new Map<string, readonly string[]>([
      ["a", ["b", "c"]],
      ["b", ["a"]],
      ["c", ["a"]],
    ]);
    const out = orderLeavesByAdjacency(nodes, edges);
    expect(out.length).toBe(nodes.length);
    expect(new Set(out.map((n) => n.id))).toEqual(
      new Set(nodes.map((n) => n.id)),
    );
  });
});
