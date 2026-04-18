/**
 * @file Recursive top-down placer.
 *
 * Given `children` (sibling paths under a common centre), pick
 * Fibonacci-shell slots, optionally refine ordering by connectivity,
 * then recurse into each child's owned leaves and sub-clusters.
 */

import type { LayoutSettings, ViewNode } from "../../types.ts";
import type { Vec3 } from "../geometry.ts";
import {
  allocateSiblingsByIntrinsic,
  permutePlacementByOrder,
  scaleSubtree,
} from "./allocate.ts";
import { orderByConnectivity, refineOrderByPairwiseSwaps } from "./ordering.ts";
import { placeOwnedCloud } from "./owned.ts";
import type { ClusterShellInfo } from "./types.ts";

export type PlaceArgs = {
  readonly centre: Vec3;
  readonly parentRadius: number;
  readonly depth: number;
  readonly children: readonly string[];
  readonly childrenOf: ReadonlyMap<string, readonly string[]>;
  readonly ownedNodes: ReadonlyMap<string, readonly ViewNode[]>;
  readonly intrinsic: Map<string, number>;
  readonly interCluster: ReadonlyMap<
    string,
    ReadonlyMap<string, number>
  > | null;
  readonly adjacency: ReadonlyMap<string, readonly string[]> | null;
  readonly settings: LayoutSettings;
  readonly collectShell: (shell: ClusterShellInfo) => void;
};

export function placeChildren(args: PlaceArgs): void {
  const {
    centre,
    parentRadius,
    depth,
    children,
    childrenOf,
    ownedNodes,
    intrinsic,
    interCluster,
    adjacency,
    settings,
    collectShell,
  } = args;
  if (children.length === 0) {
    return;
  }

  const initial = interCluster
    ? orderByConnectivity(children, interCluster)
    : children;
  const ordered: string[] = [...initial];

  const initialPlacement = allocateSiblingsByIntrinsic({
    parentRadius,
    intrinsicRadii: ordered.map((p) => intrinsic.get(p)!),
    settings,
  });

  const placement =
    interCluster && ordered.length > 3
      ? permutePlacementByOrder({
          placement: initialPlacement,
          orderedBefore: [...ordered],
          ordered,
          refine: ({ ordered: o, positions }) =>
            refineOrderByPairwiseSwaps({
              ordered: o,
              positions,
              interCluster,
            }),
        })
      : initialPlacement;

  // If the allocator had to scale down, propagate the same scale to
  // every descendant so recursive calls use consistent numbers.
  const intendedMax = Math.max(...ordered.map((p) => intrinsic.get(p)!));
  const actualMax = Math.max(...placement.radii);
  const scaleApplied = intendedMax > 0 ? actualMax / intendedMax : 1;
  if (scaleApplied < 1 - 1e-6) {
    for (const childPath of ordered) {
      scaleSubtree({
        path: childPath,
        scale: scaleApplied,
        childrenOf,
        intrinsic,
      });
    }
  }

  ordered.forEach((childPath, i) => {
    const childRadius = placement.radii[i]!;
    const rel = placement.positions[i]!;
    const childCentre: Vec3 = {
      x: centre.x + rel.x,
      y: centre.y + rel.y,
      z: centre.z + rel.z,
    };
    collectShell({
      path: childPath,
      centre: childCentre,
      radius: childRadius,
      depth,
    });

    const owned = ownedNodes.get(childPath) ?? [];
    const grandchildren = childrenOf.get(childPath) ?? [];

    // A cluster holding both leaves AND sub-clusters gives the
    // leaves an inner sphere so they don't collide with the
    // sub-bubbles. Pure-leaf clusters use the full radius.
    if (owned.length > 0) {
      const leafRadius =
        grandchildren.length > 0
          ? childRadius * settings.innerFraction
          : childRadius;
      placeOwnedCloud({
        nodes: owned,
        centre: childCentre,
        maxRadius: leafRadius,
        settings,
        edges: adjacency ?? undefined,
      });
    }
    if (grandchildren.length > 0) {
      placeChildren({
        centre: childCentre,
        parentRadius: childRadius,
        depth: depth + 1,
        children: grandchildren,
        childrenOf,
        ownedNodes,
        intrinsic,
        interCluster,
        adjacency,
        settings,
        collectShell,
      });
    }
  });
}
