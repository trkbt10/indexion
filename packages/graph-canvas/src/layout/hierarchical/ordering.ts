/**
 * @file Edge-aware ordering of cluster siblings and owned leaves.
 *
 * The positioning of N points on a Fibonacci shell is fixed; what
 * varies is which path/node sits at which slot. This module picks an
 * order that minimises squared-distance × edge-weight so connected
 * siblings end up at nearby slots and visually adjacent clusters are
 * actually related.
 */

import type { ViewEdge, ViewNode } from "../../types.ts";
import type { HierarchicalAssignment } from "../hierarchy.ts";
import type { Vec3 } from "../geometry.ts";

/** Node-to-neighbour adjacency list over the whole edge set. */
export function buildAdjacencyIndex(
  edges: readonly ViewEdge[],
): ReadonlyMap<string, readonly string[]> {
  const index = new Map<string, string[]>();
  const push = (a: string, b: string) => {
    const list = index.get(a);
    if (list) {
      list.push(b);
    } else {
      index.set(a, [b]);
    }
  };
  for (const edge of edges) {
    push(edge.sourceId, edge.targetId);
    push(edge.targetId, edge.sourceId);
  }
  return index;
}

export type InterClusterArgs = {
  readonly edges: readonly ViewEdge[];
  readonly assignment: HierarchicalAssignment;
};

/** For each pair of ancestor paths (cluster prefixes) that share an
 *  edge somewhere in their subtree, accumulate a weight. Used to
 *  pick cluster slot orderings that keep communicating clusters
 *  adjacent.
 *
 *  Walks `minDepth - 1` levels so the innermost entries (the node
 *  ids themselves) are excluded — those are not cluster keys, so
 *  accumulating weight there is dead data that also risks false
 *  lookups if a caller ever passes a node id where a cluster path
 *  is expected. */
export function buildInterClusterEdgeIndex(
  args: InterClusterArgs,
): ReadonlyMap<string, ReadonlyMap<string, number>> {
  const { edges, assignment } = args;
  const index = new Map<string, Map<string, number>>();
  for (const edge of edges) {
    const sPath = assignment.pathOf.get(edge.sourceId);
    const tPath = assignment.pathOf.get(edge.targetId);
    if (!sPath || !tPath) {
      continue;
    }
    const minDepth = Math.min(sPath.length, tPath.length);
    // Stop one level short of minDepth so we don't accumulate
    // weights on the leaf paths (node ids, not cluster prefixes).
    const clusterDepth = minDepth - 1;
    for (let d = 0; d < clusterDepth; d++) {
      const a = sPath[d]!;
      const b = tPath[d]!;
      if (a === b) {
        continue;
      }
      addPair(index, a, b);
      addPair(index, b, a);
    }
  }
  return index;
}

export function addPair(
  index: Map<string, Map<string, number>>,
  from: string,
  to: string,
): void {
  let row = index.get(from);
  if (!row) {
    row = new Map();
    index.set(from, row);
  }
  row.set(to, (row.get(to) ?? 0) + 1);
}

export type RefineOrderArgs = {
  readonly ordered: string[];
  readonly positions: readonly Vec3[];
  readonly interCluster: ReadonlyMap<string, ReadonlyMap<string, number>>;
};

/** Hill-climbing pairwise swap: for every pair of slots, try the
 *  swap, accept if the sum of per-slot costs drops. Converges in a
 *  few rounds; we cap at MAX_ROUNDS for determinism. Mutates
 *  `ordered` in place. */
export function refineOrderByPairwiseSwaps(args: RefineOrderArgs): void {
  const { ordered, positions, interCluster } = args;
  const n = ordered.length;
  const MAX_ROUNDS = 6;
  const costBetween = (ia: number, ib: number): number => {
    const rowA = interCluster.get(ordered[ia]!);
    const w = rowA?.get(ordered[ib]!) ?? 0;
    if (w === 0) {
      return 0;
    }
    const pa = positions[ia]!;
    const pb = positions[ib]!;
    const dx = pa.x - pb.x;
    const dy = pa.y - pb.y;
    const dz = pa.z - pb.z;
    return w * (dx * dx + dy * dy + dz * dz);
  };
  const slotCost = (i: number): number => {
    let sum = 0;
    for (let j = 0; j < n; j++) {
      if (j === i) {
        continue;
      }
      sum += costBetween(i, j);
    }
    return sum;
  };
  for (let round = 0; round < MAX_ROUNDS; round++) {
    let improved = false;
    for (let i = 0; i < n; i++) {
      for (let j = i + 1; j < n; j++) {
        const before = slotCost(i) + slotCost(j) - 2 * costBetween(i, j);
        const tmp = ordered[i]!;
        ordered[i] = ordered[j]!;
        ordered[j] = tmp;
        const after = slotCost(i) + slotCost(j) - 2 * costBetween(i, j);
        if (after + 1e-9 < before) {
          improved = true;
        } else {
          ordered[j] = ordered[i]!;
          ordered[i] = tmp;
        }
      }
    }
    if (!improved) {
      break;
    }
  }
}

export type RefineLeafArgs = {
  readonly nodes: ViewNode[];
  readonly positions: readonly Vec3[];
  readonly edges: ReadonlyMap<string, readonly string[]>;
};

/** Same hill-climbing pattern but for leaves inside a single
 *  cluster. Cost per node is the sum of squared distances to its
 *  edge neighbours — connected leaves end up at adjacent slots. */
export function refineLeafOrderBySwaps(args: RefineLeafArgs): void {
  const { nodes, positions, edges } = args;
  const n = nodes.length;
  const MAX_ROUNDS = 4;
  const indexOf = new Map<string, number>();
  for (let i = 0; i < n; i++) {
    indexOf.set(nodes[i]!.id, i);
  }
  const sqDist = (i: number, j: number): number => {
    const a = positions[i]!;
    const b = positions[j]!;
    const dx = a.x - b.x;
    const dy = a.y - b.y;
    const dz = a.z - b.z;
    return dx * dx + dy * dy + dz * dz;
  };
  const localCost = (i: number): number => {
    const ns = edges.get(nodes[i]!.id);
    if (!ns) {
      return 0;
    }
    let sum = 0;
    for (const other of ns) {
      const j = indexOf.get(other);
      if (j === undefined) {
        continue;
      }
      sum += sqDist(i, j);
    }
    return sum;
  };
  for (let round = 0; round < MAX_ROUNDS; round++) {
    let improved = false;
    for (let i = 0; i < n; i++) {
      for (let j = i + 1; j < n; j++) {
        const before = localCost(i) + localCost(j);
        const tmp = nodes[i]!;
        nodes[i] = nodes[j]!;
        nodes[j] = tmp;
        indexOf.set(nodes[i]!.id, i);
        indexOf.set(nodes[j]!.id, j);
        const after = localCost(i) + localCost(j);
        if (after + 1e-9 < before) {
          improved = true;
        } else {
          const t2 = nodes[i]!;
          nodes[i] = nodes[j]!;
          nodes[j] = t2;
          indexOf.set(nodes[i]!.id, i);
          indexOf.set(nodes[j]!.id, j);
        }
      }
    }
    if (!improved) {
      break;
    }
  }
}

/** Greedy "place most-connected neighbour next" ordering. Starts at
 *  `paths[0]`, then repeatedly picks the path with the strongest
 *  edge weight to the currently-placed tail. When no candidate has
 *  a known edge, falls back to the candidate with the most total
 *  connections to everything already placed. */
export function orderByConnectivity(
  paths: readonly string[],
  interCluster: ReadonlyMap<string, ReadonlyMap<string, number>>,
): readonly string[] {
  if (paths.length <= 2) {
    return paths;
  }
  const remaining = new Set(paths);
  const ordered: string[] = [paths[0]!];
  remaining.delete(paths[0]!);
  while (remaining.size > 0) {
    const tail = ordered[ordered.length - 1]!;
    const tailRow = interCluster.get(tail);
    let best: string | null = null;
    let bestScore = 0;
    if (tailRow) {
      for (const candidate of remaining) {
        const s = tailRow.get(candidate) ?? 0;
        if (s > bestScore) {
          bestScore = s;
          best = candidate;
        }
      }
    }
    if (!best) {
      let bestSum = -1;
      for (const candidate of remaining) {
        const row = interCluster.get(candidate);
        let sum = 0;
        if (row) {
          for (const placed of ordered) {
            sum += row.get(placed) ?? 0;
          }
        }
        if (sum > bestSum) {
          bestSum = sum;
          best = candidate;
        }
      }
    }
    if (!best) {
      best = remaining.values().next().value ?? null;
    }
    if (!best) {
      break;
    }
    ordered.push(best);
    remaining.delete(best);
  }
  return ordered;
}

/** Reorder leaves by edge connectivity (DFS-ish walk from the
 *  highest-degree leaf). Leaves the original array untouched. */
export function orderLeavesByAdjacency(
  nodes: readonly ViewNode[],
  edges: ReadonlyMap<string, readonly string[]>,
): ViewNode[] {
  if (nodes.length <= 2) {
    return [...nodes];
  }
  const setOfIds = new Set(nodes.map((n) => n.id));
  const neighbourCountInSet = (id: string): number => {
    const ns = edges.get(id);
    if (!ns) {
      return 0;
    }
    let count = 0;
    for (const other of ns) {
      if (setOfIds.has(other)) {
        count++;
      }
    }
    return count;
  };
  const sorted = [...nodes].sort((a, b) => {
    const da = neighbourCountInSet(a.id);
    const db = neighbourCountInSet(b.id);
    if (da !== db) {
      return db - da;
    }
    return compareString(a.id, b.id);
  });
  const placed: ViewNode[] = [sorted[0]!];
  const remaining = new Map(sorted.slice(1).map((n) => [n.id, n]));
  while (remaining.size > 0) {
    const tail = placed[placed.length - 1]!;
    const tailNeighbours = edges.get(tail.id);
    let next: ViewNode | null = null;
    if (tailNeighbours) {
      for (const id of tailNeighbours) {
        const candidate = remaining.get(id);
        if (candidate) {
          next = candidate;
          break;
        }
      }
    }
    if (!next) {
      next = remaining.values().next().value ?? null;
    }
    if (!next) {
      break;
    }
    placed.push(next);
    remaining.delete(next.id);
  }
  return placed;
}

function compareString(a: string, b: string): number {
  if (a < b) {
    return -1;
  }
  if (a > b) {
    return 1;
  }
  return 0;
}
