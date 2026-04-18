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

import type { ViewGraph } from "../../types.ts";
import type { Vec3 } from "../geometry.ts";
import {
  applyHdeLayout,
  DEFAULT_HDE_OPTIONS,
  type Finaliser,
  type HdeOptions,
} from "../hde.ts";
import { buildQuotientGraph, groupByCluster } from "./quotient.ts";
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
    const memberSet = new Set(members.map((n) => n.id));
    const innerRadius =
      opts.radius * 0.15 +
      opts.radius *
        0.25 *
        Math.sqrt(members.length / Math.max(1, maxClusterSize));
    innerRadii.set(clusterId, innerRadius);
    applyHdeLayout({
      graph: args.graph,
      subset: memberSet,
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
