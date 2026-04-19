/**
 * @file Two-level HDE that respects a clustering.
 *
 * 1. Collapse each cluster to a supernode (see quotient.ts) and run
 *    HDE on the quotient graph to place cluster centres.
 * 2. Run HDE on each cluster's induced subgraph and translate the
 *    result to its centre.
 * 3. Push overlapping pairs apart until disjoint (see overlaps.ts).
 *
 * Cost: O(k·(|C| + |E_q|) + Σ_i k·(|N_i| + |E_i|)) where C is the
 * quotient graph and (N_i, E_i) the per-cluster subgraphs. Dominated
 * by the largest cluster — far cheaper than global HDE when the
 * clustering is balanced.
 */

import type { Vec3, ViewGraph } from "../../types.ts";
import {
  applyHdeLayout,
  applyHdeOnSubgraph,
  DEFAULT_HDE_OPTIONS,
  type Finaliser,
  type HdeOptions,
} from "../hde.ts";
import {
  buildClusterSubgraphs,
  buildQuotientGraph,
  groupByCluster,
} from "./quotient.ts";
import { resolveClusterOverlaps } from "./overlaps.ts";

export { buildQuotientGraph, groupByCluster } from "./quotient.ts";
export { resolveClusterOverlaps, translateCluster } from "./overlaps.ts";

export type NestedHdeArgs = {
  readonly graph: ViewGraph;
  readonly clusterOf: ReadonlyMap<string, string>;
  readonly options?: Partial<HdeOptions>;
  readonly finalise?: Finaliser;
};

export function applyNestedHdeLayout(args: NestedHdeArgs): void {
  const opts = { ...DEFAULT_HDE_OPTIONS, ...args.options };
  const clusters = groupByCluster(args.graph.nodes, args.clusterOf);
  if (clusters.size <= 1) {
    applyHdeLayout({
      graph: args.graph,
      options: opts,
      finalise: args.finalise,
    });
    return;
  }

  // 1. HDE on the quotient graph → cluster centres.
  const quotient = buildQuotientGraph(args.graph, args.clusterOf);
  applyHdeLayout({ graph: quotient.graph, options: opts });
  const centres = new Map<string, Vec3>();
  for (const superNode of quotient.graph.nodes) {
    centres.set(superNode.id, {
      x: superNode.x,
      y: superNode.y,
      z: superNode.z,
    });
  }

  // 2. Per-cluster HDE on the induced subgraph, translated to centre.
  //
  // Build every cluster's local adjacency in a single edge-list pass
  // (see `buildClusterSubgraphs`). Without this pre-build, the loop
  // below would call applyHdeLayout({ subset }) per cluster, and each
  // call walks the full graph.edges array — turning the whole pass
  // into O(K · |E|). For 1949 module clusters on an 8710-node graph
  // that was ~3 s of synchronous work; with the pre-build it drops to
  // O(|E|) total.
  const subgraphs = buildClusterSubgraphs({
    graph: args.graph,
    clusters,
    clusterOf: args.clusterOf,
  });
  const maxClusterSize = Math.max(
    ...Array.from(clusters.values(), (m) => m.length),
  );
  const innerRadii = new Map<string, number>();
  for (const [clusterId, members] of clusters) {
    const centre = centres.get(clusterId) ?? { x: 0, y: 0, z: 0 };
    if (members.length === 1) {
      const only = members[0]!;
      only.x = centre.x;
      only.y = centre.y;
      only.z = centre.z;
      only.vx = 0;
      only.vy = 0;
      only.vz = 0;
      innerRadii.set(clusterId, 0);
      continue;
    }
    const innerRadius =
      opts.radius * 0.15 +
      opts.radius *
        0.25 *
        Math.sqrt(members.length / Math.max(1, maxClusterSize));
    innerRadii.set(clusterId, innerRadius);
    const subgraph = subgraphs.get(clusterId);
    if (!subgraph) {
      continue;
    }
    applyHdeOnSubgraph({
      subgraph,
      centre,
      options: {
        ...opts,
        radius: innerRadius,
        pivots: Math.min(opts.pivots, Math.max(4, members.length - 1)),
      },
      finalise: args.finalise,
    });
  }

  // 3. Push overlapping clusters apart.
  resolveClusterOverlaps({ clusters, centres, innerRadii });
}
