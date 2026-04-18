/**
 * @file Directedness detection — language-agnostic.
 *
 * CodeGraph edges carry an explicit from → to direction. Whether a
 * given kind is "really" directed (A depends on B) or "really"
 * symmetric (A and B reference each other) isn't something we know
 * without hard-coding per-language semantics. We infer it from the
 * graph itself: if, for most edges of a kind, there is also a reverse
 * edge between the same two endpoints, the kind behaves symmetrically
 * and arrows add no information.
 *
 * Importantly this keeps graph-canvas agnostic of moonbit, typescript,
 * python, etc. — the KGF-driven CodeGraph is our only contract.
 */

import type { ViewEdge, ViewGraph } from "../../types.ts";

export type DirectednessContext = {
  /** 0..1: fraction of edges of this kind that have no reverse
   *  partner in the same graph. 1 → purely directed; 0 → always
   *  symmetric. */
  readonly asymmetryByKind: ReadonlyMap<string, number>;
};

export function buildDirectednessContext(
  graph: ViewGraph,
): DirectednessContext {
  // Group edges by kind first.
  const byKind = new Map<string, ViewEdge[]>();
  for (const edge of graph.edges) {
    const list = byKind.get(edge.kind);
    if (list) {
      list.push(edge);
    } else {
      byKind.set(edge.kind, [edge]);
    }
  }

  const asymmetryByKind = new Map<string, number>();
  for (const [kind, edges] of byKind) {
    const reverseKey = new Set<string>();
    for (const e of edges) {
      reverseKey.add(`${e.targetId}\u0000${e.sourceId}`);
    }
    let asymmetric = 0;
    for (const e of edges) {
      const forwardKey = `${e.sourceId}\u0000${e.targetId}`;
      // If the reverse pair exists we treat this half as symmetric.
      if (!reverseKey.has(forwardKey)) {
        asymmetric++;
      }
    }
    asymmetryByKind.set(
      kind,
      edges.length === 0 ? 1 : asymmetric / edges.length,
    );
  }
  return { asymmetryByKind };
}

/** 0..1 directedness for a given edge's kind in the current graph. */
export function edgeDirectedness(
  kind: string,
  ctx: DirectednessContext,
): number {
  return ctx.asymmetryByKind.get(kind) ?? 1;
}
