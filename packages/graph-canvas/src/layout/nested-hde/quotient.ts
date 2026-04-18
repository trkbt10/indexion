/**
 * @file Quotient graph construction + cluster grouping.
 *
 * Given a clustering, collapse each cluster to a single "supernode"
 * and re-weight inter-cluster edges. The quotient graph is what the
 * outer HDE pass layouts to pick cluster centres.
 */

import type { ViewEdge, ViewGraph, ViewNode } from "../../types.ts";

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
