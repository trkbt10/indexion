/**
 * @file Normalize CodeGraph or GraphJSON into the unified ViewGraph model.
 */

import type { CodeGraph } from "@indexion/api-client";
import type { GraphInput, GraphJSON, ViewEdge, ViewGraph, ViewNode } from "./types.ts";

/** Detect input type and normalize to ViewGraph. */
export function normalizeGraph(input: GraphInput): ViewGraph {
  if ("modules" in input && "symbols" in input) {
    return fromCodeGraph(input as CodeGraph);
  }
  return fromGraphJSON(input as GraphJSON);
}

/** Convert indexion CodeGraph to ViewGraph. */
export function fromCodeGraph(cg: CodeGraph): ViewGraph {
  const nodes: ViewNode[] = [];
  const nodeIndex = new Map<string, ViewNode>();

  // Modules → ViewNodes
  for (const [id, mod] of Object.entries(cg.modules)) {
    const node = makeNode(id, id, mod.file ? "module" : "external", "", mod.file ?? null, null, {});
    nodes.push(node);
    nodeIndex.set(id, node);
  }

  // Symbols → ViewNodes (may shadow module with same ID — symbol wins)
  for (const [id, sym] of Object.entries(cg.symbols)) {
    if (nodeIndex.has(id)) {
      // Update existing module node to symbol info
      const existing = nodeIndex.get(id)!;
      const replacement = makeNode(id, sym.name, sym.kind, sym.module, existing.file, sym.doc ?? null, {});
      replacement.x = existing.x;
      replacement.y = existing.y;
      const idx = nodes.indexOf(existing);
      if (idx >= 0) nodes[idx] = replacement;
      nodeIndex.set(id, replacement);
    } else {
      const parentMod = cg.modules[sym.module];
      const node = makeNode(id, sym.name, sym.kind, sym.module, parentMod?.file ?? null, sym.doc ?? null, {});
      nodes.push(node);
      nodeIndex.set(id, node);
    }
  }

  // Edges
  const edges: ViewEdge[] = [];
  for (const e of cg.edges) {
    const source = nodeIndex.get(e.from);
    const target = nodeIndex.get(e.to);
    if (!source || !target) continue;
    edges.push({
      sourceId: e.from,
      targetId: e.to,
      kind: e.kind,
      metadata: {},
      source,
      target,
    });
  }

  return { nodes, edges, nodeIndex };
}

/** Convert indexion GraphJSON to ViewGraph. */
export function fromGraphJSON(gj: GraphJSON): ViewGraph {
  const nodes: ViewNode[] = [];
  const nodeIndex = new Map<string, ViewNode>();

  for (const gn of gj.nodes) {
    const node = makeNode(gn.id, gn.label, gn.kind, "", gn.file ?? null, null, gn.metadata ?? {});
    nodes.push(node);
    nodeIndex.set(gn.id, node);
  }

  const edges: ViewEdge[] = [];
  for (const ge of gj.edges) {
    const source = nodeIndex.get(ge.from);
    const target = nodeIndex.get(ge.to);
    if (!source || !target) continue;
    edges.push({
      sourceId: ge.from,
      targetId: ge.to,
      kind: ge.kind,
      metadata: ge.metadata ?? {},
      source,
      target,
    });
  }

  return { nodes, edges, nodeIndex };
}

/**
 * Diff old graph against a new normalized graph, preserving positions
 * for nodes that persist. New nodes are placed near their neighbors.
 */
export function diffGraph(oldGraph: ViewGraph, newGraph: ViewGraph): ViewGraph {
  for (const node of newGraph.nodes) {
    const oldNode = oldGraph.nodeIndex.get(node.id);
    if (oldNode) {
      node.x = oldNode.x;
      node.y = oldNode.y;
      node.vx = 0;
      node.vy = 0;
      node.pinned = oldNode.pinned;
    } else {
      // Place new node near centroid of its connected neighbors
      placeNearNeighbors(node, newGraph);
    }
  }
  return newGraph;
}

function placeNearNeighbors(node: ViewNode, graph: ViewGraph): void {
  let cx = 0;
  let cy = 0;
  let count = 0;
  for (const edge of graph.edges) {
    const neighbor = edge.sourceId === node.id ? edge.target : edge.targetId === node.id ? edge.source : null;
    if (neighbor && (neighbor.x !== 0 || neighbor.y !== 0)) {
      cx += neighbor.x;
      cy += neighbor.y;
      count++;
    }
  }
  if (count > 0) {
    // Offset slightly from centroid to avoid overlap
    const angle = Math.random() * Math.PI * 2;
    node.x = cx / count + Math.cos(angle) * 30;
    node.y = cy / count + Math.sin(angle) * 30;
  }
  // else: leave at (0,0) — circularLayout will handle initial placement
}

function makeNode(
  id: string,
  label: string,
  kind: string,
  group: string,
  file: string | null,
  doc: string | null,
  metadata: Record<string, string>,
): ViewNode {
  return { id, label, kind, group, file, doc, metadata, x: 0, y: 0, vx: 0, vy: 0, pinned: false };
}
