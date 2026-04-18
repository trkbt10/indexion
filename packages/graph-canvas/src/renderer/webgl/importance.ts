/**
 * @file Structural importance for continuous visual encoding.
 *
 * Language-agnostic: the renderer only consumes signals that are
 * present in every CodeGraph regardless of source language —
 *
 *   - degree (how many edges touch the node)
 *   - whether the node has a file path (= internal) vs. not (= external)
 *   - edge frequency within the current graph
 *
 * No hard-coded tables of moonbit / typescript / python kind strings.
 * Per-kind styling is derived from its position in the degree-sorted
 * distribution of the graph being rendered.
 */

import type { ViewEdge, ViewGraph, ViewNode } from "../../types.ts";

export type NodeImportanceArgs = {
  readonly node: ViewNode;
  readonly degree: number;
  /** Normalise degree against this, clamped to [0,1]. */
  readonly degreeCap: number;
};

/**
 * Node importance in [0, 1]. High-degree hubs dominate; nodes with a
 * source file (i.e. first-party code) get a small uplift so they stand
 * apart from pkg:/external dependencies without us needing to know the
 * specific language's external-module convention.
 */
export function nodeImportance(args: NodeImportanceArgs): number {
  const { node, degree, degreeCap } = args;
  // Log-normalised degree: a handful of hubs shouldn't make the long
  // tail disappear.
  const degreeTerm = Math.min(
    1,
    Math.log2(1 + degree) / Math.log2(1 + Math.max(2, degreeCap)),
  );
  // Internal nodes (those that map to a file in the host workspace)
  // read slightly stronger than external dependencies. This is a
  // structural property carried on every ViewNode.
  const structureTerm = node.file ? 0.6 : 0.35;
  // Weighted blend: degree-driven spotlight with a structural floor.
  return clamp(structureTerm * 0.5 + degreeTerm * 0.5, 0, 1);
}

export type EdgeImportanceContext = {
  /** For each edge kind in the graph, how often does it occur? */
  readonly kindFrequency: ReadonlyMap<string, number>;
  readonly totalEdges: number;
};

/**
 * Build a one-off context from the whole graph. The renderer calls
 * this once per frame; kindFrequency drives how strongly an edge of a
 * particular kind shows up — rare kinds stand out, common structural
 * glue fades back. This means the shader gets the right sense of
 * "primary vs secondary edge" without us naming kinds explicitly.
 */
export function buildEdgeContext(graph: ViewGraph): EdgeImportanceContext {
  const kindFrequency = new Map<string, number>();
  for (const edge of graph.edges) {
    kindFrequency.set(edge.kind, (kindFrequency.get(edge.kind) ?? 0) + 1);
  }
  return { kindFrequency, totalEdges: graph.edges.length };
}

/**
 * Edge importance in [0, 1]. Rare kinds get a visibility boost so
 * unusual semantic edges (e.g. an `extends` in a graph otherwise made
 * of plain imports) aren't washed out by the common structural edges.
 */
export function edgeImportance(
  edge: ViewEdge,
  ctx: EdgeImportanceContext,
): number {
  if (ctx.totalEdges === 0) {
    return 0.5;
  }
  const freq = ctx.kindFrequency.get(edge.kind) ?? 1;
  const ratio = freq / ctx.totalEdges;
  // Rarer ⇒ higher weight. Map ratio∈(0, 1] to weight∈[0.35, 0.95]
  // through a log curve so the distinction is gentle, not binary.
  const logRatio = Math.log(ratio);
  const logMin = Math.log(1 / Math.max(2, ctx.totalEdges));
  const t = logMin === 0 ? 0.5 : clamp(logRatio / logMin, 0, 1);
  return 0.35 + 0.6 * t;
}

function clamp(value: number, min: number, max: number): number {
  return Math.max(min, Math.min(max, value));
}
