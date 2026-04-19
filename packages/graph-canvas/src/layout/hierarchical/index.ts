/**
 * @file Hierarchical layout — squarified treemap.
 *
 * Every cluster (a path in the node hierarchy) gets a 2D rectangle
 * whose area is proportional to the number of leaf nodes under it.
 * Sub-clusters tile their parent rectangle with another squarified
 * treemap; leaves at the deepest level fill the cell on a jittered
 * grid. The result is dense, area-proportional, and aspect-balanced
 * — every node gets visible space, no nesting collapses to a dot.
 *
 * The previous incarnation packed clusters on Fibonacci spheres,
 * which wasted most of the parent volume on shell space and forced
 * cascading scale reductions. The treemap uses 100% of the parent
 * area and never needs to "shrink to fit", so density tracks node
 * count linearly.
 *
 * Output:
 *   - Each ViewNode gets x, y written; z = 0.
 *   - One ClusterShell per visited path. Shell circles are
 *     inscribed in their cell rectangle so the renderer's existing
 *     spherical-shell drawing keeps working.
 *
 * Language-agnostic: consumes only the path assignment + node kinds.
 */

import type {
  ClusterShell,
  LayoutSettings,
  Rect,
  ViewEdge,
  ViewNode,
} from "../../types.ts";
import {
  buildChildrenIndex,
  buildOwnedNodesIndex,
  rootsOf,
  type HierarchicalAssignment,
} from "../hierarchy.ts";
import { computeWeights, packChildren } from "./pack.ts";

export type HierarchicalLayoutArgs = {
  readonly nodes: readonly ViewNode[];
  /** Edges used to order leaves so connected nodes end up in nearby
   *  grid slots. Optional so the pure-layout spec tests can drive
   *  the layout without edge data. */
  readonly edges?: readonly ViewEdge[];
  readonly assignment: HierarchicalAssignment;
  readonly settings: LayoutSettings;
};

export type HierarchicalLayoutResult = {
  readonly nodeDepth: ReadonlyMap<string, number>;
  readonly clusterShells: readonly ClusterShell[];
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
  const adjacency = edges ? buildAdjacencyIndex(edges) : null;
  const weightOf = computeWeights({ roots, childrenOf, ownedNodes });

  // The world is a square centred at the origin with side
  // 2 × worldRadius. The renderer's fitToView fits to whatever real
  // payload is present; this only sets the working scale.
  const side = settings.worldRadius * 2;
  const worldRect: Rect = {
    x: -settings.worldRadius,
    y: -settings.worldRadius,
    w: side,
    h: side,
  };

  const shells: ClusterShell[] = [];
  packChildren({
    rect: worldRect,
    depth: 1,
    children: roots,
    childrenOf,
    ownedNodes,
    weightOf,
    adjacency,
    settings,
    collectShell: (s) => shells.push(s),
  });

  // Singleton root special-case: if only one root exists, packChildren
  // gives it the full world rect. That's correct, but the renderer
  // expects nodeDepth=1 for landmarks and our recursion writes the
  // top-level shell as the root itself. No additional fix needed; the
  // shell list will contain the root cell at depth=1.

  return { nodeDepth, clusterShells: shells };
}

/** Build a node-id → neighbour-ids adjacency map from a list of
 *  directed edges. Symmetric: both endpoints see each other so the
 *  treemap leaf-ordering can group connected pairs regardless of
 *  edge direction. */
function buildAdjacencyIndex(
  edges: readonly ViewEdge[],
): ReadonlyMap<string, readonly string[]> {
  const map = new Map<string, string[]>();
  const push = (from: string, to: string): void => {
    const list = map.get(from);
    if (list) {
      list.push(to);
    } else {
      map.set(from, [to]);
    }
  };
  for (const edge of edges) {
    if (edge.sourceId === edge.targetId) {
      continue;
    }
    push(edge.sourceId, edge.targetId);
    push(edge.targetId, edge.sourceId);
  }
  return map;
}
