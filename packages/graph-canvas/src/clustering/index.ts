/**
 * @file Flat clustering strategies for graph nodes.
 *
 * A clustering assigns a single cluster id to every visible node.
 * Pure data transformation — takes the graph and returns a map from
 * node id to cluster id. Never mutates the graph, never reads or
 * writes positions.
 *
 * Consumers (the layout module) use the assignment to group nodes at
 * placement time. Hierarchical / path-based grouping is handled by
 * the hierarchy layout strategy itself, not here — this module is
 * strictly flat (one id per node).
 */

import type { ViewGraph, ViewNode } from "../types.ts";

export type ClusteringId =
  | "none"
  | "kind"
  | "directory"
  | "module"
  | "community";

export type ClusterAssignment = {
  readonly strategy: ClusteringId;
  readonly clusterOf: ReadonlyMap<string, string>;
  readonly clusters: ReadonlyMap<string, readonly string[]>;
};

export type ClusteringMeta = {
  readonly id: ClusteringId;
  readonly label: string;
  readonly description: string;
};

export const CLUSTERINGS: readonly ClusteringMeta[] = [
  {
    id: "none",
    label: "None",
    description: "No clustering — pure force-directed layout.",
  },
  {
    id: "kind",
    label: "By kind",
    description: "Group nodes by their kind (module, function, type…).",
  },
  {
    id: "directory",
    label: "By directory",
    description: "Group nodes by top-level directory of their file.",
  },
  {
    id: "module",
    label: "By module",
    description: "Group symbols by their owning module.",
  },
  {
    id: "community",
    label: "By community",
    description: "Detect communities via label propagation on the edge graph.",
  },
];

export function computeClustering(
  graph: ViewGraph,
  strategy: ClusteringId,
): ClusterAssignment {
  const clusterOf = strategyFor(strategy)(graph);
  return { strategy, clusterOf, clusters: invert(clusterOf) };
}

type Strategy = (graph: ViewGraph) => Map<string, string>;

function strategyFor(id: ClusteringId): Strategy {
  switch (id) {
    case "none":
      return byNone;
    case "kind":
      return byKind;
    case "directory":
      return byDirectory;
    case "module":
      return byModule;
    case "community":
      return byCommunity;
  }
}

function byNone(graph: ViewGraph): Map<string, string> {
  const map = new Map<string, string>();
  for (const node of graph.nodes) {
    map.set(node.id, node.id);
  }
  return map;
}

function byKind(graph: ViewGraph): Map<string, string> {
  const map = new Map<string, string>();
  for (const node of graph.nodes) {
    map.set(node.id, `kind:${node.kind}`);
  }
  return collapseSingletonsTo(map, "kind:__isolates__");
}

function byDirectory(graph: ViewGraph): Map<string, string> {
  const map = new Map<string, string>();
  for (const node of graph.nodes) {
    map.set(node.id, `dir:${topLevelDirOf(node)}`);
  }
  return collapseSingletonsTo(map, "dir:__isolates__");
}

function byModule(graph: ViewGraph): Map<string, string> {
  const map = new Map<string, string>();
  for (const node of graph.nodes) {
    const key = node.group.length > 0 ? node.group : (node.file ?? node.id);
    map.set(node.id, `mod:${key}`);
  }
  return collapseSingletonsTo(map, "mod:__isolates__");
}

/** Reassign every assignment that produces a single-node cluster to
 *  the shared `bucketId`. Same rationale as `collapseSingletons` in
 *  byCommunity: thousands of single-node clusters multiply the
 *  per-cluster fixed cost in nested-hde and made the whole pipeline
 *  block the UI for seconds. Verified visually by switching to the
 *  Volume strategy with each clustering. */
function collapseSingletonsTo(
  assignment: Map<string, string>,
  bucketId: string,
): Map<string, string> {
  const counts = new Map<string, number>();
  for (const c of assignment.values()) {
    counts.set(c, (counts.get(c) ?? 0) + 1);
  }
  for (const [nodeId, c] of assignment) {
    if ((counts.get(c) ?? 0) === 1) {
      assignment.set(nodeId, bucketId);
    }
  }
  return assignment;
}

/**
 * Modularity-greedy community detection (Louvain phase 1).
 *
 * For each node, we compute the modularity gain from moving it into
 * each neighbouring community, and choose the best. Iterated until
 * stable. This typically produces balanced mid-sized communities
 * rather than one giant blob (which plain label propagation tends to).
 *
 * Modularity gain formula (undirected):
 *   ΔQ = [ k_in / m ]  −  [ Σ_tot · k / (2 m²) ]
 * where k_in is the sum of edge weights from the node to nodes already
 * in the target community, Σ_tot is the total edge weight incident on
 * the target community, k is the degree of the node, and m is the
 * total edge weight in the graph.
 */
function byCommunity(graph: ViewGraph): Map<string, string> {
  const community = new Map<string, string>();
  for (const node of graph.nodes) {
    community.set(node.id, node.id);
  }
  if (graph.edges.length === 0) {
    return qualify(community);
  }

  const adjacency = buildAdjacency(graph);
  const degree = new Map<string, number>();
  for (const [nodeId, neighbours] of adjacency) {
    degree.set(nodeId, neighbours.size);
  }

  // totalWeight = 2m because each undirected edge contributes to both
  // endpoints' degrees.
  let totalWeight = 0;
  for (const d of degree.values()) {
    totalWeight += d;
  }
  if (totalWeight === 0) {
    return qualify(community);
  }
  const twoM = totalWeight;

  const sigmaTot = new Map<string, number>();
  for (const [nodeId, d] of degree) {
    sigmaTot.set(nodeId, d);
  }

  const maxIterations = 20;
  for (let iter = 0; iter < maxIterations; iter++) {
    let moved = false;
    for (const node of graph.nodes) {
      const nodeId = node.id;
      const currentCommunity = community.get(nodeId)!;
      const k = degree.get(nodeId) ?? 0;
      if (k === 0) {
        continue;
      }

      const weights = neighbourCommunityWeights(nodeId, adjacency, community);
      const currentKIn = weights.get(currentCommunity) ?? 0;

      // Temporarily remove the node from its current community.
      sigmaTot.set(currentCommunity, (sigmaTot.get(currentCommunity) ?? 0) - k);

      let bestCommunity = currentCommunity;
      let bestGain = 0;
      for (const [candidate, kIn] of weights) {
        const tot = sigmaTot.get(candidate) ?? 0;
        const gain = kIn - (tot * k) / twoM;
        if (
          gain > bestGain ||
          (gain === bestGain && candidate < bestCommunity)
        ) {
          bestGain = gain;
          bestCommunity = candidate;
        }
      }

      // Rejoining the current community baselines to currentKIn, which
      // means "staying" gains currentKIn points; only switch if the
      // alternative beats that.
      if (bestGain > currentKIn) {
        sigmaTot.set(bestCommunity, (sigmaTot.get(bestCommunity) ?? 0) + k);
        community.set(nodeId, bestCommunity);
        moved = true;
      } else {
        sigmaTot.set(
          currentCommunity,
          (sigmaTot.get(currentCommunity) ?? 0) + k,
        );
      }
    }
    if (!moved) {
      break;
    }
  }

  // Collapse singletons into a single "isolates" pseudo-cluster.
  // Without this, isolated nodes (degree=0) and tiny disconnected
  // components stay as their own community — on a real codebase
  // graph that produced thousands of single-node clusters, which
  // forced nested-hde to run K HDE passes (each O(|E|)) and made
  // the whole pipeline hang for tens of seconds.
  collapseSingletonsTo(community, "__isolates__");
  return qualify(community);
}

function buildAdjacency(graph: ViewGraph): Map<string, Map<string, number>> {
  const adjacency = new Map<string, Map<string, number>>();
  for (const node of graph.nodes) {
    adjacency.set(node.id, new Map());
  }
  for (const edge of graph.edges) {
    bumpNeighbour(adjacency, edge.sourceId, edge.targetId);
    bumpNeighbour(adjacency, edge.targetId, edge.sourceId);
  }
  return adjacency;
}

function bumpNeighbour(
  map: Map<string, Map<string, number>>,
  from: string,
  to: string,
): void {
  if (from === to) {
    return;
  }
  const bucket = map.get(from);
  if (!bucket) {
    return;
  }
  bucket.set(to, (bucket.get(to) ?? 0) + 1);
}

function neighbourCommunityWeights(
  nodeId: string,
  adjacency: ReadonlyMap<string, ReadonlyMap<string, number>>,
  community: ReadonlyMap<string, string>,
): Map<string, number> {
  const out = new Map<string, number>();
  const neighbours = adjacency.get(nodeId);
  if (!neighbours) {
    return out;
  }
  for (const [neighbourId, weight] of neighbours) {
    const c = community.get(neighbourId);
    if (c === undefined) {
      continue;
    }
    out.set(c, (out.get(c) ?? 0) + weight);
  }
  return out;
}

function qualify(community: ReadonlyMap<string, string>): Map<string, string> {
  const out = new Map<string, string>();
  for (const [nodeId, c] of community) {
    out.set(nodeId, `c:${c}`);
  }
  return out;
}

function topLevelDirOf(node: ViewNode): string {
  if (node.file && node.file.length > 0) {
    const slash = node.file.indexOf("/");
    if (slash > 0) {
      return node.file.slice(0, slash);
    }
    return node.file;
  }
  const colon = node.id.indexOf(":");
  if (colon > 0) {
    return node.id.slice(0, colon);
  }
  return "_";
}

function invert(
  clusterOf: ReadonlyMap<string, string>,
): Map<string, readonly string[]> {
  const out = new Map<string, string[]>();
  for (const [nodeId, clusterId] of clusterOf) {
    const list = out.get(clusterId);
    if (list) {
      list.push(nodeId);
    } else {
      out.set(clusterId, [nodeId]);
    }
  }
  return out;
}
