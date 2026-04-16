/**
 * @file Force simulation tick loop with adaptive cooling.
 *
 * Each tick applies forces (repulsion, spring, centering), updates
 * positions by integrating velocities, and applies damping. The
 * simulation cools over time (alpha decays) and stops when stable.
 */

import type { ForceConfig, ViewGraph } from "../types.ts";
import { applyCentering, applyRepulsion, applySpring } from "./forces.ts";

export type SimulationState = {
  alpha: number;
  running: boolean;
};

export function createSimulation(): SimulationState {
  return { alpha: 1.0, running: true };
}

/**
 * Perform one simulation tick: apply forces, integrate, damp, cool.
 * Returns true if the simulation is still running.
 */
export function tick(
  state: SimulationState,
  graph: ViewGraph,
  config: ForceConfig,
): boolean {
  if (!state.running) return false;

  const { nodes, edges } = graph;

  // Apply forces (order matters slightly — repulsion first for stability)
  applyRepulsion(nodes, state.alpha, config);
  applySpring(edges, state.alpha, config);
  applyCentering(nodes, state.alpha, config);

  // Integrate velocities and apply damping
  const decay = config.velocityDecay;
  for (const node of nodes) {
    if (node.pinned) {
      node.vx = 0;
      node.vy = 0;
      continue;
    }
    node.vx *= decay;
    node.vy *= decay;
    node.x += node.vx;
    node.y += node.vy;
  }

  // Cool: reduce alpha
  state.alpha *= 1 - config.alphaDecay;
  if (state.alpha < config.alphaMin) {
    state.alpha = config.alphaMin;
    state.running = false;
  }

  return state.running;
}

/** Reheat the simulation to re-stabilize after perturbation. */
export function reheat(state: SimulationState, alpha: number = 0.3): void {
  state.alpha = alpha;
  state.running = true;
}
