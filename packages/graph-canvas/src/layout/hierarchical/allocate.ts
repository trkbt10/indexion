/**
 * @file Sibling-slot allocation on a Fibonacci shell.
 *
 * Given `intrinsicRadii` for N siblings and a parent radius, pick
 * Fibonacci shell positions and uniformly scale every sibling's
 * radius if the parent can't host them at intrinsic demand.
 */

import type { LayoutSettings } from "../../types.ts";
import {
  fibonacciNearestChord,
  fibonacciPoints,
  ORIGIN,
  type Vec3,
} from "../geometry.ts";
import type { VolumetricPlacement } from "./types.ts";

export type AllocateArgs = {
  readonly parentRadius: number;
  readonly intrinsicRadii: readonly number[];
  readonly settings: LayoutSettings;
};

/** Place siblings using their bottom-up `intrinsicRadii`. The
 *  allocator's only job is to pick Fibonacci-shell positions that
 *  respect the disjointness constraint.
 *
 *  When `parentRadius` is smaller than intrinsic demands we scale
 *  every sibling by the same factor — proportions are preserved and
 *  no pair overlaps. */
export function allocateSiblingsByIntrinsic(
  args: AllocateArgs,
): VolumetricPlacement {
  const { parentRadius, intrinsicRadii, settings } = args;
  const n = intrinsicRadii.length;
  if (n === 0) {
    return { positions: [], radii: [] };
  }
  if (n === 1) {
    return {
      positions: [ORIGIN],
      radii: [Math.min(parentRadius * 0.85, intrinsicRadii[0]!)],
    };
  }
  const maxR = Math.max(...intrinsicRadii);
  const chord = Math.max(0.02, fibonacciNearestChord(n));
  const shellByPacking = (maxR * 2 * (1 + settings.siblingGap)) / chord;
  const totalOuter = shellByPacking + maxR;
  const scale = totalOuter <= parentRadius ? 1 : parentRadius / totalOuter;
  const radii = intrinsicRadii.map((r) => r * scale);
  const shellRadius = shellByPacking * scale;
  const positions = fibonacciPoints(n, shellRadius);
  return { positions, radii };
}

export type PermuteArgs = {
  readonly placement: VolumetricPlacement;
  /** Snapshot of `ordered` BEFORE the in-place refinement. Used to
   *  build the path → radius map against the original order. */
  readonly orderedBefore: readonly string[];
  /** The mutable array that the caller's refinement will permute. */
  readonly ordered: string[];
  /** Apply the in-place order refinement. Kept as an injected
   *  callback so this module doesn't depend on the ordering layer. */
  readonly refine: (args: {
    readonly ordered: string[];
    readonly positions: readonly Vec3[];
  }) => void;
};

/** Apply an in-place ordering refinement, then remap radii through
 *  the new order. Positions are permutation-invariant (Fibonacci
 *  slots are fixed; we choose which path sits at which slot). */
export function permutePlacementByOrder(
  args: PermuteArgs,
): VolumetricPlacement {
  const { placement, orderedBefore, ordered, refine } = args;
  const radiiByPath = new Map<string, number>();
  orderedBefore.forEach((p, i) => radiiByPath.set(p, placement.radii[i]!));
  refine({ ordered, positions: placement.positions });
  const reboundRadii = ordered.map((p) => radiiByPath.get(p)!);
  return { positions: placement.positions, radii: reboundRadii };
}

export type ScaleSubtreeArgs = {
  readonly path: string;
  readonly scale: number;
  readonly childrenOf: ReadonlyMap<string, readonly string[]>;
  readonly intrinsic: Map<string, number>;
};

/** Scale every descendant path's intrinsic radius by `scale` so the
 *  recursive placer uses consistent numbers. */
export function scaleSubtree(args: ScaleSubtreeArgs): void {
  const { path, scale, childrenOf, intrinsic } = args;
  const cur = intrinsic.get(path);
  if (cur !== undefined) {
    intrinsic.set(path, cur * scale);
  }
  const kids = childrenOf.get(path);
  if (!kids) {
    return;
  }
  for (const kid of kids) {
    scaleSubtree({ path: kid, scale, childrenOf, intrinsic });
  }
}
