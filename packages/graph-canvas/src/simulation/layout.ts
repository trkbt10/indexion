/**
 * @file Initial node placement using concentric circles.
 *
 * Nodes are sorted by degree (connectivity) with highest-degree nodes
 * placed at the center, producing a deterministic and reproducible
 * starting configuration that converges faster than random placement.
 */

import type { ViewEdge, ViewNode } from "../types.ts";

/**
 * Place nodes in concentric circles, sorted by degree.
 * Only affects nodes whose position is (0, 0) (not yet placed).
 */
export function circularLayout(nodes: ViewNode[], edges: readonly ViewEdge[]): void {
  // Compute degree per node
  const degree = new Map<string, number>();
  for (const n of nodes) degree.set(n.id, 0);
  for (const e of edges) {
    degree.set(e.sourceId, (degree.get(e.sourceId) ?? 0) + 1);
    degree.set(e.targetId, (degree.get(e.targetId) ?? 0) + 1);
  }

  // Collect unplaced nodes
  const unplaced = nodes.filter((n) => n.x === 0 && n.y === 0 && !n.pinned);
  if (unplaced.length === 0) return;

  // Sort by degree descending (most connected at center)
  unplaced.sort((a, b) => (degree.get(b.id) ?? 0) - (degree.get(a.id) ?? 0));

  // Place on concentric rings
  const nodesPerRing = 8; // First ring capacity; grows with ring index
  let ringIndex = 0;
  let placed = 0;

  while (placed < unplaced.length) {
    const capacity = ringIndex === 0 ? 1 : nodesPerRing * ringIndex;
    const radius = ringIndex * 50;
    const count = Math.min(capacity, unplaced.length - placed);

    for (let i = 0; i < count; i++) {
      const angle = (2 * Math.PI * i) / count;
      const node = unplaced[placed]!;
      node.x = Math.cos(angle) * radius;
      node.y = Math.sin(angle) * radius;
      placed++;
    }
    ringIndex++;
  }
}
