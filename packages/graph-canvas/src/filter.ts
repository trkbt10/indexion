/**
 * @file Node, edge, disconnected-node, and search filtering.
 */

import type { FilterResult, ViewGraph } from "./types.ts";

type KindSetInput = ReadonlySet<string> | readonly string[] | undefined;

export function computeFilter(
  graph: ViewGraph,
  enabledNodeKinds?: KindSetInput,
  enabledEdgeKinds?: KindSetInput,
  hideDisconnected: boolean = false,
  searchQuery: string = "",
): FilterResult {
  const nodeKinds = toSet(enabledNodeKinds);
  const edgeKinds = toSet(enabledEdgeKinds);
  const visibleNodes = new Set<string>();

  for (const node of graph.nodes) {
    if (!nodeKinds || nodeKinds.has(node.kind)) {
      visibleNodes.add(node.id);
    }
  }

  const visibleEdges = new Set<number>();
  const connectedNodes = new Set<string>();
  graph.edges.forEach((edge, index) => {
    if (!visibleNodes.has(edge.sourceId) || !visibleNodes.has(edge.targetId)) {
      return;
    }
    if (edgeKinds && !edgeKinds.has(edge.kind)) {
      return;
    }
    visibleEdges.add(index);
    connectedNodes.add(edge.sourceId);
    connectedNodes.add(edge.targetId);
  });

  if (hideDisconnected) {
    for (const nodeId of visibleNodes) {
      if (!connectedNodes.has(nodeId)) {
        visibleNodes.delete(nodeId);
      }
    }
  }

  const highlightedNodes = computeHighlights(graph, visibleNodes, searchQuery);
  return { visibleNodes, visibleEdges, highlightedNodes };
}

function toSet(input: KindSetInput): ReadonlySet<string> | null {
  if (!input) return null;
  if (input instanceof Set) return input;
  return new Set(input);
}

function computeHighlights(
  graph: ViewGraph,
  visibleNodes: ReadonlySet<string>,
  searchQuery: string,
): Set<string> {
  const query = searchQuery.trim().toLowerCase();
  const highlighted = new Set<string>();
  if (!query) return highlighted;

  for (const node of graph.nodes) {
    if (!visibleNodes.has(node.id)) continue;
    const label = node.label.toLowerCase();
    const id = node.id.toLowerCase();
    if (label.includes(query) || id.includes(query)) {
      highlighted.add(node.id);
    }
  }
  return highlighted;
}
