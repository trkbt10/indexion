/**
 * @file Force functions for the force-directed graph layout.
 *
 * Each function mutates vx/vy on ViewNodes directly. Forces are:
 * - Repulsion: Coulomb-like inverse-square between all node pairs
 * - Spring: Hooke's law attraction along edges
 * - Centering: Weak pull toward the centroid of all nodes
 */

import type { ForceConfig, ViewEdge, ViewNode } from "../types.ts";
import { applyBarnesHutRepulsion, buildQuadTree } from "./quadtree.ts";

/**
 * Apply mutual repulsion between all node pairs.
 * Uses direct O(N^2) for small graphs, Barnes-Hut for large ones.
 */
export function applyRepulsion(
  nodes: readonly ViewNode[],
  alpha: number,
  config: ForceConfig,
): void {
  if (nodes.length < 2) return;

  if (nodes.length >= config.barnesHutThreshold) {
    const tree = buildQuadTree(nodes);
    applyBarnesHutRepulsion(tree, nodes, config.barnesHutTheta, config.repulsionStrength, alpha);
    return;
  }

  // Direct N^2 calculation
  const strength = config.repulsionStrength;
  for (let i = 0; i < nodes.length; i++) {
    const a = nodes[i]!;
    for (let j = i + 1; j < nodes.length; j++) {
      const b = nodes[j]!;
      let dx = b.x - a.x;
      let dy = b.y - a.y;
      let distSq = dx * dx + dy * dy;
      if (distSq < 1) {
        // Jitter coincident nodes to break symmetry
        dx = (Math.random() - 0.5) * 0.1;
        dy = (Math.random() - 0.5) * 0.1;
        distSq = dx * dx + dy * dy;
      }
      const force = (strength * alpha) / distSq;
      const dist = Math.sqrt(distSq);
      const fx = (dx / dist) * force;
      const fy = (dy / dist) * force;
      if (!a.pinned) {
        a.vx -= fx;
        a.vy -= fy;
      }
      if (!b.pinned) {
        b.vx += fx;
        b.vy += fy;
      }
    }
  }
}

/**
 * Apply spring attraction along edges (Hooke's law).
 * Pulls connected nodes toward an ideal rest length.
 */
export function applySpring(
  edges: readonly ViewEdge[],
  alpha: number,
  config: ForceConfig,
): void {
  const { springStiffness, springRestLength } = config;
  for (const edge of edges) {
    const { source, target } = edge;
    const dx = target.x - source.x;
    const dy = target.y - source.y;
    const dist = Math.sqrt(dx * dx + dy * dy) || 1;
    const displacement = dist - springRestLength;
    const force = springStiffness * alpha * displacement;
    const fx = (dx / dist) * force;
    const fy = (dy / dist) * force;
    if (!source.pinned) {
      source.vx += fx;
      source.vy += fy;
    }
    if (!target.pinned) {
      target.vx -= fx;
      target.vy -= fy;
    }
  }
}

/**
 * Apply centering force pulling all nodes toward their centroid.
 * Prevents the graph from drifting off-screen.
 */
export function applyCentering(
  nodes: readonly ViewNode[],
  alpha: number,
  config: ForceConfig,
): void {
  if (nodes.length === 0) return;
  let cx = 0;
  let cy = 0;
  let count = 0;
  for (const n of nodes) {
    cx += n.x;
    cy += n.y;
    count++;
  }
  cx /= count;
  cy /= count;
  const strength = config.centerStrength * alpha;
  for (const n of nodes) {
    if (n.pinned) continue;
    n.vx -= (n.x - cx) * strength;
    n.vy -= (n.y - cy) * strength;
  }
}
