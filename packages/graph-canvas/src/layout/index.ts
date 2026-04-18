/**
 * @file Layout public surface.
 *
 * Consumers pass a ViewGraph (plus optional clusterOf and strategy),
 * and the layout writes x/y/z on every node in a single deterministic
 * pass. Drag-time nudges go through relaxNeighbours, which touches
 * only the dragged node's direct edge partners — never a full
 * re-solve.
 *
 * Everything else in this directory is implementation detail and
 * should not be imported from outside the layout module.
 */

import type { LayoutSettings, ViewGraph } from "../types.ts";
import {
  getLayoutStrategy,
  type LayoutStrategyId,
  type StrategyResult,
} from "./strategies.ts";
import { DEFAULT_RENDER_SETTINGS } from "../renderer/settings.ts";

export { LAYOUT_STRATEGIES, getLayoutStrategy } from "./strategies.ts";
export { relaxNeighbours } from "./drag-relax.ts";
export type {
  ClusterShell,
  LayoutStrategy,
  LayoutStrategyId,
  StrategyResult,
} from "./strategies.ts";

export type LayoutArgs = {
  readonly graph: ViewGraph;
  readonly clusterOf: ReadonlyMap<string, string> | null;
  readonly strategy?: LayoutStrategyId;
  readonly settings?: LayoutSettings;
};

const DEFAULT_STRATEGY: LayoutStrategyId = "hde-volume";

export function layoutGraph(args: LayoutArgs): StrategyResult {
  const { graph, clusterOf } = args;
  if (graph.nodes.length === 0) {
    return {};
  }
  const strategy = getLayoutStrategy(args.strategy ?? DEFAULT_STRATEGY);
  const layoutSettings = args.settings ?? DEFAULT_RENDER_SETTINGS.layout;
  return strategy.apply({ graph, clusterOf, layoutSettings });
}
