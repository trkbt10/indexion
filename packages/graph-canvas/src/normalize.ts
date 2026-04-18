/**
 * @file Normalize CodeGraph or GraphJSON into the unified ViewGraph model.
 */

import type { CodeGraph } from "@indexion/api-client";
import type {
  GraphInput,
  GraphJSON,
  ViewEdge,
  ViewGraph,
  ViewNode,
} from "./types.ts";

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
    const node = makeNode({
      id,
      label: id,
      kind: mod.file ? "module" : "external",
      group: "",
      file: mod.file ?? null,
      doc: null,
      metadata: {},
    });
    nodes.push(node);
    nodeIndex.set(id, node);
  }

  // Symbols → ViewNodes (may shadow module with same ID — symbol wins)
  for (const [id, sym] of Object.entries(cg.symbols)) {
    if (nodeIndex.has(id)) {
      // Update existing module node to symbol info
      const existing = nodeIndex.get(id)!;
      const replacement = makeNode({
        id,
        label: sym.name,
        kind: sym.kind,
        group: sym.module,
        file: existing.file,
        doc: sym.doc ?? null,
        metadata: {},
      });
      replacement.x = existing.x;
      replacement.y = existing.y;
      const idx = nodes.indexOf(existing);
      if (idx >= 0) {
        nodes[idx] = replacement;
      }
      nodeIndex.set(id, replacement);
    } else {
      const parentMod = cg.modules[sym.module];
      const node = makeNode({
        id,
        label: sym.name,
        kind: sym.kind,
        group: sym.module,
        file: parentMod?.file ?? null,
        doc: sym.doc ?? null,
        metadata: {},
      });
      nodes.push(node);
      nodeIndex.set(id, node);
    }
  }

  // Edges
  const edges: ViewEdge[] = [];
  let missingFrom = 0;
  let missingTo = 0;
  const missingSamples: string[] = [];
  for (const e of cg.edges) {
    const source = nodeIndex.get(e.from);
    const target = nodeIndex.get(e.to);
    if (!source || !target) {
      if (!source) {
        missingFrom++;
      }
      if (!target) {
        missingTo++;
      }
      if (missingSamples.length < 3) {
        missingSamples.push(`${e.from} → ${e.to}`);
      }
      continue;
    }
    edges.push({
      sourceId: e.from,
      targetId: e.to,
      kind: e.kind,
      metadata: {},
      source,
      target,
    });
  }

  const dropped = cg.edges.length - edges.length;
  if (dropped > 0) {
    console.warn(
      `[graph-canvas] Dropped ${dropped}/${cg.edges.length} edges whose endpoints are absent from modules/symbols (from: ${missingFrom}, to: ${missingTo}). Samples: ${missingSamples.join("; ")}`,
    );
  }

  return { nodes, edges, nodeIndex };
}

/** Convert indexion GraphJSON to ViewGraph. */
export function fromGraphJSON(gj: GraphJSON): ViewGraph {
  const nodes: ViewNode[] = [];
  const nodeIndex = new Map<string, ViewNode>();

  for (const gn of gj.nodes) {
    const node = makeNode({
      id: gn.id,
      label: gn.label,
      kind: gn.kind,
      group: "",
      file: gn.file ?? null,
      doc: null,
      metadata: gn.metadata ?? {},
    });
    nodes.push(node);
    nodeIndex.set(gn.id, node);
  }

  const edges: ViewEdge[] = [];
  const missingSamples: string[] = [];
  for (const ge of gj.edges) {
    const source = nodeIndex.get(ge.from);
    const target = nodeIndex.get(ge.to);
    if (!source || !target) {
      if (missingSamples.length < 3) {
        missingSamples.push(`${ge.from} → ${ge.to}`);
      }
      continue;
    }
    edges.push({
      sourceId: ge.from,
      targetId: ge.to,
      kind: ge.kind,
      metadata: ge.metadata ?? {},
      source,
      target,
    });
  }

  const dropped = gj.edges.length - edges.length;
  if (dropped > 0) {
    console.warn(
      `[graph-canvas] Dropped ${dropped}/${gj.edges.length} GraphJSON edges with missing endpoints. Samples: ${missingSamples.join("; ")}`,
    );
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
      node.z = oldNode.z;
      node.vx = 0;
      node.vy = 0;
      node.vz = 0;
      node.pinned = oldNode.pinned;
    } else {
      placeNearNeighbors(node, newGraph);
    }
  }
  return newGraph;
}

function placeNearNeighbors(node: ViewNode, graph: ViewGraph): void {
  let cx = 0;
  let cy = 0;
  let cz = 0;
  let count = 0;
  for (const edge of graph.edges) {
    const neighbor = neighborOf(edge, node.id);
    if (neighbor && !isAtOrigin(neighbor)) {
      cx += neighbor.x;
      cy += neighbor.y;
      cz += neighbor.z;
      count++;
    }
  }
  if (count > 0) {
    // Offset slightly from centroid to avoid overlap.
    const theta = Math.random() * Math.PI * 2;
    const phi = Math.random() * Math.PI - Math.PI / 2;
    const r = 30;
    node.x = cx / count + Math.cos(phi) * Math.cos(theta) * r;
    node.y = cy / count + Math.cos(phi) * Math.sin(theta) * r;
    node.z = cz / count + Math.sin(phi) * r;
  }
  // else: leave at origin — initial layout will place it.
}

function isAtOrigin(node: ViewNode): boolean {
  return node.x === 0 && node.y === 0 && node.z === 0;
}

function neighborOf(edge: ViewEdge, nodeId: string): ViewNode | null {
  if (edge.sourceId === nodeId) {
    return edge.target;
  }
  if (edge.targetId === nodeId) {
    return edge.source;
  }
  return null;
}

type MakeNodeArgs = {
  readonly id: string;
  readonly label: string;
  readonly kind: string;
  readonly group: string;
  readonly file: string | null;
  readonly doc: string | null;
  readonly metadata: Record<string, string>;
};

function makeNode(args: MakeNodeArgs): ViewNode {
  return {
    ...args,
    x: 0,
    y: 0,
    z: 0,
    vx: 0,
    vy: 0,
    vz: 0,
    pinned: false,
  };
}
