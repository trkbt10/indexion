/**
 * @file Quotient graph construction + cluster grouping.
 *
 * Given a clustering, collapse each cluster to a single "supernode"
 * and re-weight inter-cluster edges. The quotient graph is what the
 * outer HDE pass layouts to pick cluster centres.
 */

import type { ViewEdge, ViewGraph, ViewNode } from "../../types.ts";
import type { PrebuiltSubgraph } from "../hde.ts";

export type QuotientResult = {
  readonly graph: ViewGraph;
};

export function buildQuotientGraph(
  graph: ViewGraph,
  clusterOf: ReadonlyMap<string, string>,
): QuotientResult {
  const superNodes = new Map<string, ViewNode>();
  for (const [, clusterId] of clusterOf) {
    if (!superNodes.has(clusterId)) {
      superNodes.set(clusterId, makeSuperNode(clusterId));
    }
  }

  const weights = new Map<string, number>();
  for (const edge of graph.edges) {
    const cs = clusterOf.get(edge.sourceId);
    const ct = clusterOf.get(edge.targetId);
    if (!cs || !ct || cs === ct) {
      continue;
    }
    const key = edgeKey(cs, ct);
    weights.set(key, (weights.get(key) ?? 0) + 1);
  }

  const nodeList = Array.from(superNodes.values());
  const nodeIndex = new Map<string, ViewNode>();
  for (const sn of nodeList) {
    nodeIndex.set(sn.id, sn);
  }

  const edges: ViewEdge[] = [];
  for (const key of weights.keys()) {
    const sep = key.indexOf("\u0000");
    const a = key.slice(0, sep);
    const b = key.slice(sep + 1);
    const sa = nodeIndex.get(a);
    const sb = nodeIndex.get(b);
    if (!sa || !sb) {
      continue;
    }
    edges.push({
      sourceId: a,
      targetId: b,
      kind: "quotient",
      metadata: {},
      source: sa,
      target: sb,
    });
  }

  return { graph: { nodes: nodeList, edges, nodeIndex } };
}

export function makeSuperNode(id: string): ViewNode {
  return {
    id,
    label: id,
    kind: "cluster",
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

/** Group nodes by their cluster assignment. Nodes whose id isn't in
 *  `clusterOf` are silently dropped — the caller is responsible for
 *  supplying a complete mapping. */
export function groupByCluster(
  nodes: readonly ViewNode[],
  clusterOf: ReadonlyMap<string, string>,
): Map<string, ViewNode[]> {
  const groups = new Map<string, ViewNode[]>();
  for (const node of nodes) {
    const clusterId = clusterOf.get(node.id);
    if (clusterId === undefined) {
      continue;
    }
    const list = groups.get(clusterId);
    if (list) {
      list.push(node);
    } else {
      groups.set(clusterId, [node]);
    }
  }
  return groups;
}

/** Canonical undirected edge key — sorts the two ids so (A,B) and
 *  (B,A) hash to the same bucket. Null character is used as separator
 *  since it cannot appear in a node id. */
function edgeKey(a: string, b: string): string {
  return a < b ? `${a}\u0000${b}` : `${b}\u0000${a}`;
}

/**
 * Build a `PrebuiltSubgraph` for every cluster in a single pass over
 * the global edge list. The previous nested-hde call site walked the
 * whole edge list once per cluster (O(K · |E|)); using this helper
 * collapses that to O(|E| + Σ |E_i|), which is essentially O(|E|)
 * since Σ |E_i| ≤ |E|.
 *
 * Only intra-cluster edges contribute to the per-cluster local
 * adjacency. Cross-cluster edges are excluded — they belong to the
 * quotient graph, not to any single cluster's HDE.
 */
export function buildClusterSubgraphs(args: {
  readonly graph: ViewGraph;
  readonly clusters: ReadonlyMap<string, readonly ViewNode[]>;
  readonly clusterOf: ReadonlyMap<string, string>;
}): Map<string, PrebuiltSubgraph> {
  const { graph, clusters, clusterOf } = args;
  // Per-cluster local index: nodeId → local position within the cluster.
  // Built once so per-edge classification is O(1).
  const localIndex = new Map<string, number>();
  for (const [, members] of clusters) {
    for (let i = 0; i < members.length; i++) {
      localIndex.set(members[i]!.id, i);
    }
  }
  // Initialise empty adjacency arrays for each cluster.
  const localAdj = new Map<string, number[][]>();
  for (const [clusterId, members] of clusters) {
    localAdj.set(
      clusterId,
      Array.from({ length: members.length }, () => []),
    );
  }
  // One sweep through the edge list. Skip self-loops and edges that
  // cross cluster boundaries — only intra-cluster connectivity feeds
  // the per-cluster HDE.
  for (const edge of graph.edges) {
    const cs = clusterOf.get(edge.sourceId);
    const ct = clusterOf.get(edge.targetId);
    if (!cs || cs !== ct) {
      continue;
    }
    if (edge.sourceId === edge.targetId) {
      continue;
    }
    const adj = localAdj.get(cs);
    if (!adj) {
      continue;
    }
    const si = localIndex.get(edge.sourceId);
    const ti = localIndex.get(edge.targetId);
    if (si === undefined || ti === undefined) {
      continue;
    }
    adj[si]!.push(ti);
    adj[ti]!.push(si);
  }
  // Materialise the result, pairing each cluster's nodes with its
  // local adjacency.
  const out = new Map<string, PrebuiltSubgraph>();
  for (const [clusterId, members] of clusters) {
    out.set(clusterId, {
      nodes: members,
      localAdj: localAdj.get(clusterId) ?? [],
    });
  }
  return out;
}
