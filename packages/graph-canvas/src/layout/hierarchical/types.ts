/**
 * @file Shared types for the hierarchical layout submodules.
 */

import type { Vec3 } from "../geometry.ts";

/** A cluster outline emitted by the hierarchical layout. The renderer
 *  draws one ring per shell so the nested structure is visible. */
export type ClusterShellInfo = {
  readonly path: string;
  readonly centre: Vec3;
  readonly radius: number;
  readonly depth: number;
};

/** N siblings' final positions and radii on a Fibonacci shell. */
export type VolumetricPlacement = {
  readonly positions: readonly Vec3[];
  readonly radii: readonly number[];
};
