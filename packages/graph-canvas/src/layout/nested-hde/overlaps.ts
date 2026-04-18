/**
 * @file Rigid per-cluster overlap resolution.
 *
 * Each cluster has a bounding radius (measured from actual final
 * positions, plus padding). Pairs of centres closer than
 * `ra + rb` are pushed apart along the line between them, and
 * every member of the cluster is translated rigidly so the
 * internal HDE layout is preserved.
 *
 * Iterated until no pair overlaps, capped at MAX_ITERATIONS so
 * pathological inputs don't spin forever.
 */

import type { ViewNode } from "../../types.ts";
import type { Vec3 } from "../geometry.ts";

export type OverlapResolutionArgs = {
  readonly clusters: ReadonlyMap<string, readonly ViewNode[]>;
  readonly centres: Map<string, Vec3>;
  readonly innerRadii: ReadonlyMap<string, number>;
};

const MAX_ITERATIONS = 48;
const PADDING = 12;

export function resolveClusterOverlaps(args: OverlapResolutionArgs): void {
  const { clusters, centres, innerRadii } = args;
  const ids = Array.from(clusters.keys());
  if (ids.length < 2) {
    return;
  }

  // Measure each cluster's bounding radius from the centre it was
  // placed at, plus a small padding so neighbouring shells don't
  // touch exactly.
  const radii = new Map<string, number>();
  for (const id of ids) {
    const members = clusters.get(id) ?? [];
    const centre = centres.get(id) ?? { x: 0, y: 0, z: 0 };
    radii.set(id, measureRadius(members, centre, innerRadii.get(id) ?? 0));
  }

  for (let iter = 0; iter < MAX_ITERATIONS; iter++) {
    let moved = false;
    for (let i = 0; i < ids.length; i++) {
      const idA = ids[i]!;
      const ra = radii.get(idA)!;
      for (let j = i + 1; j < ids.length; j++) {
        const idB = ids[j]!;
        // Re-read ca/cb every inner iteration — a previous collision
        // this round may have moved A or B, and comparing against the
        // stale pre-move position lets overlaps accumulate instead
        // of resolve.
        const ca = centres.get(idA)!;
        const cb = centres.get(idB)!;
        const rb = radii.get(idB)!;
        if (!separatePair({ i, clusters, centres, idA, idB, ca, cb, ra, rb })) {
          continue;
        }
        moved = true;
      }
    }
    if (!moved) {
      break;
    }
  }
}

type SeparatePairArgs = {
  readonly i: number;
  readonly clusters: ReadonlyMap<string, readonly ViewNode[]>;
  readonly centres: Map<string, Vec3>;
  readonly idA: string;
  readonly idB: string;
  readonly ca: Vec3;
  readonly cb: Vec3;
  readonly ra: number;
  readonly rb: number;
};

/** True iff the pair overlapped and was separated. */
function separatePair(args: SeparatePairArgs): boolean {
  const { i, clusters, centres, idA, idB, ca, cb, ra, rb } = args;
  const dx = cb.x - ca.x;
  const dy = cb.y - ca.y;
  const dz = cb.z - ca.z;
  let distSq = dx * dx + dy * dy + dz * dz;
  const minDist = ra + rb;
  if (distSq >= minDist * minDist) {
    return false;
  }
  let nx: number;
  let ny: number;
  let nz: number;
  if (distSq < 1e-6) {
    // Coincident centres — pick an arbitrary but deterministic axis
    // derived from the cluster index.
    const angle = (i * 2654435761) % 1024;
    nx = Math.cos(angle);
    ny = Math.sin(angle);
    nz = 0;
    distSq = 1e-6;
  } else {
    const d = Math.sqrt(distSq);
    nx = dx / d;
    ny = dy / d;
    nz = dz / d;
  }
  const half = (minDist - Math.sqrt(distSq)) / 2;
  const newA: Vec3 = {
    x: ca.x - nx * half,
    y: ca.y - ny * half,
    z: ca.z - nz * half,
  };
  const newB: Vec3 = {
    x: cb.x + nx * half,
    y: cb.y + ny * half,
    z: cb.z + nz * half,
  };
  translateCluster(clusters.get(idA) ?? [], ca, newA);
  translateCluster(clusters.get(idB) ?? [], cb, newB);
  centres.set(idA, newA);
  centres.set(idB, newB);
  return true;
}

/** Translate every member of a cluster by `(to - from)`. Preserves
 *  the cluster's internal shape — what moved is only the cluster's
 *  origin, not its relative layout. */
export function translateCluster(
  members: readonly ViewNode[],
  from: Vec3,
  to: Vec3,
): void {
  const dx = to.x - from.x;
  const dy = to.y - from.y;
  const dz = to.z - from.z;
  if (dx === 0 && dy === 0 && dz === 0) {
    return;
  }
  for (const node of members) {
    node.x += dx;
    node.y += dy;
    node.z += dz;
  }
}

/** Measure the bounding radius — max(|member - centre|) — plus
 *  padding. Falls back to `planned` (the intrinsic radius) if it
 *  exceeds the measurement, so tiny clusters still keep their
 *  intended footprint. */
function measureRadius(
  members: readonly ViewNode[],
  centre: Vec3,
  planned: number,
): number {
  let maxDistSq = 0;
  for (const node of members) {
    const dx = node.x - centre.x;
    const dy = node.y - centre.y;
    const dz = node.z - centre.z;
    const d = dx * dx + dy * dy + dz * dz;
    if (d > maxDistSq) {
      maxDistSq = d;
    }
  }
  const measured = Math.sqrt(maxDistSq);
  return Math.max(measured, planned) + PADDING;
}
