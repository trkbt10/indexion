/**
 * @file Pure graph-derived selectors for the renderer.
 *
 * These walk the graph + filter and produce small auxiliary data
 * structures (visible nodes, visible edges, degree map, hover
 * neighbourhood). No three.js, no scene state, no LOD math — that's
 * each layer's responsibility.
 */

import type { FilterResult, ViewEdge, ViewGraph, ViewNode } from "../../types.ts";

export function filterVisibleNodes(
  graph: ViewGraph,
  filter: FilterResult,
): ViewNode[] {
  return graph.nodes.filter((n) => filter.visibleNodes.has(n.id));
}

export function filterVisibleEdges(
  graph: ViewGraph,
  filter: FilterResult,
): ViewEdge[] {
  const out: ViewEdge[] = [];
  graph.edges.forEach((edge, index) => {
    if (filter.visibleEdges.has(index)) {
      out.push(edge);
    }
  });
  return out;
}

export function computeDegreeMap(
  graph: ViewGraph,
  filter: FilterResult,
): Map<string, number> {
  const count = new Map<string, number>();
  graph.edges.forEach((edge, index) => {
    if (!filter.visibleEdges.has(index)) {
      return;
    }
    count.set(edge.sourceId, (count.get(edge.sourceId) ?? 0) + 1);
    count.set(edge.targetId, (count.get(edge.targetId) ?? 0) + 1);
  });
  return count;
}

/** Largest degree in the visible subgraph. Floored at 4 so single-edge
 *  graphs don't read every node as a "hub". */
export function computeDegreeCap(degreeMap: ReadonlyMap<string, number>): number {
  let cap = 4;
  for (const v of degreeMap.values()) {
    if (v > cap) {
      cap = v;
    }
  }
  return cap;
}

/** Ids of the hovered node + every node it shares an edge with.
 *  Used to highlight an Obsidian-style "1-hop neighbourhood" on
 *  hover. Includes the centre itself. */
export function collectNeighbourIds(
  graph: ViewGraph,
  centre: string,
): ReadonlySet<string> {
  const out = new Set<string>([centre]);
  for (const edge of graph.edges) {
    const other = otherEdgeEndpoint(edge, centre);
    if (other !== null) {
      out.add(other);
    }
  }
  return out;
}

function otherEdgeEndpoint(
  edge: { readonly sourceId: string; readonly targetId: string },
  nodeId: string,
): string | null {
  if (edge.sourceId === nodeId) {
    return edge.targetId;
  }
  if (edge.targetId === nodeId) {
    return edge.sourceId;
  }
  return null;
}
