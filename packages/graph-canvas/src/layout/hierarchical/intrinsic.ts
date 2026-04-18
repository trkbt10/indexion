/**
 * @file Bottom-up intrinsic radius calculation.
 *
 * Each path in the hierarchy computes the smallest radius that holds
 * its content — the owned leaves packed at footprint spacing plus any
 * sub-cluster bubbles arranged on a Fibonacci shell. Computing bottom
 * up means the top-down placer never asks a cluster to shrink below
 * what its content demands.
 */

import type { LayoutSettings, ViewNode } from "../../types.ts";
import { fibonacciNearestChord } from "../geometry.ts";

export type IntrinsicArgs = {
  readonly roots: readonly string[];
  readonly childrenOf: ReadonlyMap<string, readonly string[]>;
  readonly ownedNodes: ReadonlyMap<string, readonly ViewNode[]>;
  readonly settings: LayoutSettings;
};

/** Per-path intrinsic radius. Pure leaf clusters need
 *  `cbrt(n) × footprint / 1.2` to pack n leaves; branch clusters need
 *  `computeSiblingOuterRadius(kidsRadii)`. Mixed clusters need enough
 *  room for both, since the leaves occupy an inner sphere at
 *  `radius × innerFraction` and the sub-bubbles ring the outer. */
export function computeIntrinsicRadii(
  args: IntrinsicArgs,
): Map<string, number> {
  const { roots, childrenOf, ownedNodes, settings } = args;
  const cache = new Map<string, number>();
  const visit = (path: string): number => {
    const cached = cache.get(path);
    if (cached !== undefined) {
      return cached;
    }
    const owned = ownedNodes.get(path) ?? [];
    const kids = childrenOf.get(path) ?? [];
    const kidsRadii = kids.map(visit);
    const leafRadius =
      owned.length === 0
        ? 0
        : (settings.ownedLeafFootprint * Math.cbrt(Math.max(1, owned.length))) /
          1.2;
    const kidsRadius =
      kids.length === 0
        ? 0
        : computeSiblingOuterRadius({ radii: kidsRadii, settings });
    const totalRadius =
      owned.length > 0 && kids.length > 0
        ? Math.max(leafRadius / settings.innerFraction, kidsRadius)
        : Math.max(leafRadius, kidsRadius);
    cache.set(path, totalRadius);
    return totalRadius;
  };
  for (const root of roots) {
    visit(root);
  }
  return cache;
}

export type SiblingOuterArgs = {
  readonly radii: readonly number[];
  readonly settings: LayoutSettings;
};

/** Smallest parent radius that hosts `radii` child bubbles on a
 *  Fibonacci shell with the configured siblingGap. Uses max(radii) as
 *  the packing-governing radius (conservative — the allocator scales
 *  everyone to the max so the weakest-gap constraint is the binding
 *  one). Symmetric with `allocateSiblingsByIntrinsic`. */
export function computeSiblingOuterRadius(args: SiblingOuterArgs): number {
  const { radii, settings } = args;
  const n = radii.length;
  if (n === 0) {
    return 0;
  }
  if (n === 1) {
    return radii[0]! * (1 + settings.siblingGap);
  }
  const maxR = Math.max(...radii);
  const chord = Math.max(0.02, fibonacciNearestChord(n));
  const shell = (maxR * 2 * (1 + settings.siblingGap)) / chord;
  return shell + maxR;
}
