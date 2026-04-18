/**
 * @file Layout strategies — each is a pure function that places every
 * node in `graph.nodes` and returns optional metadata for the renderer.
 *
 * Three strategies:
 *   - hde-volume — HDE embedding, nodes fill a sphere. Honours an
 *                  optional flat clustering.
 *   - k-means    — HDE + 3D k-means on the embedding. Self-clustering.
 *   - hierarchy  — Nested bubbles by node path (file / id hierarchy).
 *
 * Adding a strategy = adding a new entry to LAYOUT_STRATEGIES.
 */

import type { LayoutSettings, ViewGraph } from "../types.ts";
import { computeHierarchy } from "./hierarchy.ts";
import { applyHdeLayout, volumeFinaliser } from "./hde.ts";
import { applyHierarchicalLayout } from "./hierarchical/index.ts";
import { kmeans } from "./kmeans.ts";
import { applyNestedHdeLayout } from "./nested-hde/index.ts";

export type LayoutStrategyId = "hde-volume" | "k-means" | "hierarchy";

export type LayoutStrategy = {
  readonly id: LayoutStrategyId;
  readonly label: string;
  readonly description: string;
  readonly apply: (args: StrategyArgs) => StrategyResult;
};

export type StrategyArgs = {
  readonly graph: ViewGraph;
  readonly clusterOf: ReadonlyMap<string, string> | null;
  /** Injected layout tuning. Callers always pass this; we default
   *  in `layoutGraph` so existing call sites don't have to know. */
  readonly layoutSettings: LayoutSettings;
};

/** Optional metadata a strategy can expose for the renderer to pick
 *  up — hierarchy cluster outlines, per-node depth for LOD fading,
 *  etc. Non-hierarchical strategies can leave these empty. */
export type StrategyResult = {
  /** Per-node hierarchy depth (1 = top folder). 0 or missing means
   *  "don't apply depth-based LOD to this node". */
  readonly nodeDepth?: ReadonlyMap<string, number>;
  /** Cluster shells: (centre, radius, depth) for each hierarchy level
   *  so the renderer can outline them. */
  readonly clusterShells?: readonly ClusterShell[];
};

export type ClusterShell = {
  readonly path: string;
  readonly centre: {
    readonly x: number;
    readonly y: number;
    readonly z: number;
  };
  readonly radius: number;
  readonly depth: number;
};

export const LAYOUT_STRATEGIES: readonly LayoutStrategy[] = [
  {
    id: "hierarchy",
    label: "Hierarchy",
    description:
      "Nested bubbles by id path: parents enclose sub-packages recursively. Shows the host language's package structure whatever it is.",
    apply: ({ graph, layoutSettings }) => {
      const assignment = computeHierarchy(graph.nodes);
      const result = applyHierarchicalLayout({
        nodes: graph.nodes,
        edges: graph.edges,
        assignment,
        settings: layoutSettings,
      });
      return {
        nodeDepth: result.nodeDepth,
        clusterShells: result.clusterShells,
      };
    },
  },
  {
    id: "k-means",
    label: "K-Means",
    description:
      "Edge-topology clustering: HDE places connected nodes nearby, then 3D k-means discovers the natural clusters.",
    apply: ({ graph }) => applyKMeansLayout(graph),
  },
  {
    id: "hde-volume",
    label: "Volume",
    description:
      "HDE embedding, nodes fill a sphere. Respects user-selected clustering if any.",
    apply: ({ graph, clusterOf }) => {
      if (!clusterOf || clusterOf.size === 0) {
        applyHdeLayout({ graph, finalise: volumeFinaliser });
        return {};
      }
      applyNestedHdeLayout({ graph, clusterOf, finalise: volumeFinaliser });
      return {};
    },
  },
];

const STRATEGY_BY_ID = new Map<LayoutStrategyId, LayoutStrategy>(
  LAYOUT_STRATEGIES.map((s) => [s.id, s]),
);

export function getLayoutStrategy(id: LayoutStrategyId): LayoutStrategy {
  const s = STRATEGY_BY_ID.get(id);
  if (!s) {
    throw new Error(`Unknown layout strategy: ${id as string}`);
  }
  return s;
}

// ─── K-means strategy ─────────────────────────────────────────────

/** K-means in 3D on top of an HDE embedding.
 *
 *  1. Run HDE with the volume finaliser so nodes occupy a solid ball
 *     in which connected pairs end up close.
 *  2. Read the placed coordinates into a flat `[x,y,z,...]` buffer.
 *  3. Run k-means with K = round(sqrt(N)) — a classic "rule of
 *     thumb" that balances cluster count vs cluster size for graphs
 *     of a few hundred to a few thousand nodes.
 *  4. Re-use HDE positions as the final coordinates (they're already
 *     good). Emit one `ClusterShell` per k-means cluster so the
 *     caller can outline the groups if desired. */
/** How much each node is pulled toward its k-means cluster centroid
 *  after the initial HDE embedding. 0 = leave raw HDE positions (no
 *  tightening), 1 = collapse every member onto the centroid. We want
 *  mild tightening so clusters read as groups without vanishing
 *  their internal structure. */
const KMEANS_PULL = 0.55;

type RobustRadiusArgs = {
  readonly points: Float64Array;
  readonly assignment: Int32Array;
  readonly clusterIdx: number;
  readonly centre: {
    readonly x: number;
    readonly y: number;
    readonly z: number;
  };
};

/** Robust radius estimate from the node distribution. We use the
 *  90th-percentile (not max) so a few outliers don't make the
 *  bounding sphere huge — which would force fitToView to zoom out
 *  until the real payload is sub-pixel. */
function robustRadius(args: RobustRadiusArgs): number {
  const { points, assignment, clusterIdx, centre } = args;
  const dists: number[] = [];
  const n = points.length / 3;
  for (let i = 0; i < n; i++) {
    if (assignment[i] !== clusterIdx) {
      continue;
    }
    const dx = points[i * 3]! - centre.x;
    const dy = points[i * 3 + 1]! - centre.y;
    const dz = points[i * 3 + 2]! - centre.z;
    dists.push(Math.sqrt(dx * dx + dy * dy + dz * dz));
  }
  if (dists.length === 0) {
    return 0;
  }
  dists.sort((a, b) => a - b);
  return dists[Math.floor(dists.length * 0.9)] ?? dists[dists.length - 1]!;
}

function applyKMeansLayout(graph: ViewGraph): StrategyResult {
  if (graph.nodes.length === 0) {
    return {};
  }
  // 1. HDE embedding — connected nodes end up near each other.
  applyHdeLayout({ graph, finalise: volumeFinaliser });

  // 2. Flat buffer for k-means.
  const n = graph.nodes.length;
  const points = new Float64Array(n * 3);
  for (let i = 0; i < n; i++) {
    const node = graph.nodes[i]!;
    points[i * 3] = node.x;
    points[i * 3 + 1] = node.y;
    points[i * 3 + 2] = node.z;
  }

  // 3. k-means. K = sqrt(N) clamped so tiny or huge graphs both
  //    produce a manageable cluster count.
  const k = Math.max(2, Math.min(32, Math.round(Math.sqrt(n))));
  const result = kmeans({ points, k });

  // 4. Pull each node partially toward its cluster's centroid — this
  //    tightens clusters so the grouping is visible, without
  //    collapsing internal structure. A fully-collapsed layout loses
  //    all node-to-node distinction.
  for (let i = 0; i < n; i++) {
    const c = result.centroids[result.assignment[i]!]!;
    const node = graph.nodes[i]!;
    node.x = node.x * (1 - KMEANS_PULL) + c.x * KMEANS_PULL;
    node.y = node.y * (1 - KMEANS_PULL) + c.y * KMEANS_PULL;
    node.z = node.z * (1 - KMEANS_PULL) + c.z * KMEANS_PULL;
    // Update the points buffer too so shell-radius maths below uses
    // the post-pull positions.
    points[i * 3] = node.x;
    points[i * 3 + 1] = node.y;
    points[i * 3 + 2] = node.z;
  }

  // 5. Emit one ClusterShell per k-means cluster. Radius uses the
  //    90th-percentile distance so outliers don't inflate the bubble.
  const shells: ClusterShell[] = result.centroids.map((c, idx) => ({
    path: `kmeans-${idx}`,
    centre: { x: c.x, y: c.y, z: c.z },
    radius: robustRadius({
      points,
      assignment: result.assignment,
      clusterIdx: idx,
      centre: c,
    }),
    depth: 1,
  }));
  return { clusterShells: shells };
}
