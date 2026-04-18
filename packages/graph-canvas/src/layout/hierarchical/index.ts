/**
 * @file Hierarchical layout — "galaxies of galaxies".
 *
 * Every node is positioned in a single top-down pass:
 *
 *   world
 *    └─ each top-level path gets a bubble on the world sphere
 *        └─ nested paths get sub-bubbles inside their parent
 *            └─ owned leaves fill the interior by kind-band + force
 *
 * This entry orchestrates: compute intrinsic radii bottom-up, shrink
 * uniformly if the world can't host them, then walk the tree top-down
 * via placeChildren. Every algorithmic piece is its own exported
 * helper under this directory.
 *
 * All tuning values flow from `LayoutSettings` (the renderer's
 * `RenderSettings.layout` is the single source of truth). No magic
 * numbers in this file other than mathematical constants.
 *
 * Language-agnostic: consumes only the path assignment + node kinds,
 * never per-language prefixes or dir names.
 */

import type { LayoutSettings, ViewEdge, ViewNode } from "../../types.ts";
import {
  buildChildrenIndex,
  buildOwnedNodesIndex,
  rootsOf,
  type HierarchicalAssignment,
} from "../hierarchy.ts";
import { ORIGIN } from "../geometry.ts";
import {
  computeIntrinsicRadii,
  computeSiblingOuterRadius,
} from "./intrinsic.ts";
import { buildAdjacencyIndex, buildInterClusterEdgeIndex } from "./ordering.ts";
import { placeChildren } from "./place.ts";
import type { ClusterShellInfo } from "./types.ts";

export type { ClusterShellInfo } from "./types.ts";

export type HierarchicalLayoutArgs = {
  readonly nodes: readonly ViewNode[];
  /** Edges used for sibling ordering, kind-band adjacency, and
   *  intra-cluster force relaxation. Optional so the pure-layout
   *  spec tests can drive the layout without edge data. */
  readonly edges?: readonly ViewEdge[];
  readonly assignment: HierarchicalAssignment;
  readonly settings: LayoutSettings;
};

export type HierarchicalLayoutResult = {
  readonly nodeDepth: ReadonlyMap<string, number>;
  readonly clusterShells: readonly ClusterShellInfo[];
};

export function applyHierarchicalLayout(
  args: HierarchicalLayoutArgs,
): HierarchicalLayoutResult {
  const { nodes, assignment, edges, settings } = args;

  const nodeDepth = new Map<string, number>();
  for (const node of nodes) {
    nodeDepth.set(node.id, assignment.pathOf.get(node.id)?.length ?? 1);
  }
  if (nodes.length === 0) {
    return { nodeDepth, clusterShells: [] };
  }

  const childrenOf = buildChildrenIndex(assignment);
  const ownedNodes = buildOwnedNodesIndex(nodes, assignment);
  const roots = rootsOf(assignment);
  const interCluster = edges
    ? buildInterClusterEdgeIndex({ edges, assignment })
    : null;
  const adjacency = edges ? buildAdjacencyIndex(edges) : null;

  const intrinsic = computeIntrinsicRadii({
    roots,
    childrenOf,
    ownedNodes,
    settings,
  });

  // If the sum of root intrinsic radii exceeds the world radius,
  // scale every intrinsic uniformly so the whole scene fits. That
  // preserves relative proportions (heavy clusters still dwarf
  // light ones) while keeping the world inside a bounded box.
  const rootTotal = computeSiblingOuterRadius({
    radii: roots.map((p) => intrinsic.get(p)!),
    settings,
  });
  const worldRadius = settings.worldRadius;
  if (rootTotal > worldRadius) {
    const scale = worldRadius / rootTotal;
    for (const path of intrinsic.keys()) {
      intrinsic.set(path, intrinsic.get(path)! * scale);
    }
  }

  const shells: ClusterShellInfo[] = [];
  placeChildren({
    centre: ORIGIN,
    parentRadius: worldRadius,
    depth: 1,
    children: roots,
    childrenOf,
    ownedNodes,
    intrinsic,
    interCluster,
    adjacency,
    settings,
    collectShell: (s) => shells.push(s),
  });

  return { nodeDepth, clusterShells: shells };
}
