/**
 * @file Contract tests for quotient graph construction.
 *
 * Two-level HDE collapses each cluster to a supernode. If quotient
 * construction loses an edge, duplicates a supernode, or miscounts
 * edge weights, every cluster centre is placed wrong and the whole
 * layout slides with it. Test the primitives directly.
 */

import { describe, expect, it } from "vitest";
import type { ViewEdge, ViewGraph, ViewNode } from "../../types.ts";
import {
  buildQuotientGraph,
  groupByCluster,
  makeSuperNode,
} from "./quotient.ts";

function mkNode(id: string): ViewNode {
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

describe("makeSuperNode", () => {
  it("produces a well-formed ViewNode for a cluster id", () => {
    const sn = makeSuperNode("cluster-1");
    expect(sn.id).toBe("cluster-1");
    expect(sn.kind).toBe("cluster");
    expect(sn.label).toBe("cluster-1");
    expect(sn.x).toBe(0);
    expect(sn.y).toBe(0);
    expect(sn.z).toBe(0);
    expect(sn.pinned).toBe(false);
  });
});

describe("groupByCluster", () => {
  it("groups nodes that share a cluster id", () => {
    const a = mkNode("a");
    const b = mkNode("b");
    const c = mkNode("c");
    const assignment = new Map([
      ["a", "X"],
      ["b", "X"],
      ["c", "Y"],
    ]);
    const groups = groupByCluster([a, b, c], assignment);
    expect(groups.get("X")?.map((n) => n.id).sort()).toEqual(["a", "b"]);
    expect(groups.get("Y")?.map((n) => n.id)).toEqual(["c"]);
  });

  it("silently drops nodes missing from the assignment", () => {
    // Caller contract: a node not in clusterOf is ignored. Prevents
    // accidental "cluster undefined" buckets.
    const a = mkNode("a");
    const b = mkNode("unknown");
    const assignment = new Map([["a", "X"]]);
    const groups = groupByCluster([a, b], assignment);
    expect(groups.size).toBe(1);
    expect(groups.get("X")?.map((n) => n.id)).toEqual(["a"]);
  });

  it("returns empty map for empty input", () => {
    expect(groupByCluster([], new Map()).size).toBe(0);
  });
});

describe("buildQuotientGraph", () => {
  it("creates one supernode per unique cluster", () => {
    const a = mkNode("a");
    const b = mkNode("b");
    const c = mkNode("c");
    const assignment = new Map([
      ["a", "X"],
      ["b", "X"],
      ["c", "Y"],
    ]);
    const graph = mkGraph([a, b, c], []);
    const { graph: quotient } = buildQuotientGraph(graph, assignment);
    expect(quotient.nodes.length).toBe(2);
    expect(new Set(quotient.nodes.map((n) => n.id))).toEqual(new Set(["X", "Y"]));
  });

  it("drops self-edges (within-cluster edges contribute nothing)", () => {
    const a = mkNode("a");
    const b = mkNode("b");
    const assignment = new Map([
      ["a", "X"],
      ["b", "X"],
    ]);
    const graph = mkGraph([a, b], [mkEdge(a, b)]);
    const { graph: quotient } = buildQuotientGraph(graph, assignment);
    expect(quotient.edges.length).toBe(0);
  });

  it("deduplicates parallel inter-cluster edges into a single edge", () => {
    // Three edges between cluster X and cluster Y should collapse
    // into ONE undirected quotient edge.
    const a = mkNode("a");
    const b = mkNode("b");
    const c = mkNode("c");
    const d = mkNode("d");
    const assignment = new Map([
      ["a", "X"],
      ["b", "X"],
      ["c", "Y"],
      ["d", "Y"],
    ]);
    const graph = mkGraph(
      [a, b, c, d],
      [mkEdge(a, c), mkEdge(a, d), mkEdge(b, c), mkEdge(d, a)],
    );
    const { graph: quotient } = buildQuotientGraph(graph, assignment);
    expect(quotient.edges.length).toBe(1);
  });

  it("uses canonical ordering: (A,B) and (B,A) collapse into one edge", () => {
    const a = mkNode("a");
    const c = mkNode("c");
    const assignment = new Map([
      ["a", "X"],
      ["c", "Y"],
    ]);
    const graph = mkGraph([a, c], [mkEdge(a, c), mkEdge(c, a)]);
    const { graph: quotient } = buildQuotientGraph(graph, assignment);
    expect(quotient.edges.length).toBe(1);
  });

  it("populates nodeIndex consistently with the supernode list", () => {
    const a = mkNode("a");
    const assignment = new Map([["a", "X"]]);
    const graph = mkGraph([a], []);
    const { graph: quotient } = buildQuotientGraph(graph, assignment);
    for (const sn of quotient.nodes) {
      expect(quotient.nodeIndex.get(sn.id)).toBe(sn);
    }
  });

  it("edges reference supernode instances from nodeIndex, not fresh copies", () => {
    const a = mkNode("a");
    const c = mkNode("c");
    const assignment = new Map([
      ["a", "X"],
      ["c", "Y"],
    ]);
    const graph = mkGraph([a, c], [mkEdge(a, c)]);
    const { graph: quotient } = buildQuotientGraph(graph, assignment);
    const edge = quotient.edges[0]!;
    expect(edge.source).toBe(quotient.nodeIndex.get(edge.sourceId));
    expect(edge.target).toBe(quotient.nodeIndex.get(edge.targetId));
  });

  it("handles graph with no edges", () => {
    const a = mkNode("a");
    const b = mkNode("b");
    const assignment = new Map([
      ["a", "X"],
      ["b", "Y"],
    ]);
    const graph = mkGraph([a, b], []);
    const { graph: quotient } = buildQuotientGraph(graph, assignment);
    expect(quotient.edges.length).toBe(0);
    expect(quotient.nodes.length).toBe(2);
  });
});
