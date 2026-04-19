/**
 * @file Shared geometry primitives for the layout module.
 *
 * Fibonacci-sphere sampling and common vector helpers. Centralised
 * here because several layout stages (HDE component packing, nested
 * HDE, hierarchical sibling placement, kind-band leaf placement) all
 * need to distribute N points uniformly on a sphere, and divergent
 * implementations were subtly wrong (see `fibonacciPoints` below).
 */

import type { Vec3, ViewNode } from "../types.ts";

export const ORIGIN: Vec3 = { x: 0, y: 0, z: 0 };

/** Golden angle — the irrational turn per sample that gives the
 *  fibonacci sphere its near-uniform coverage. */
export const GOLDEN_ANGLE = Math.PI * (3 - Math.sqrt(5));

export function addVec(a: Vec3, b: Vec3): Vec3 {
  return { x: a.x + b.x, y: a.y + b.y, z: a.z + b.z };
}

/** N points on a sphere of the given radius, approximately uniform.
 *
 *  Uses cell-centre sampling `t = (i + 0.5) / count` so points are
 *  placed at the centre of N equal-area latitude bands. A previous
 *  implementation used `t = i / (count - 1)` which put one point at
 *  each pole (r = 0, so the azimuth had no effect) and collapsed
 *  small-N distributions to a vertical line — the bug responsible
 *  for singleton components stacking on the scene's y-axis. */
export function fibonacciPoints(
  count: number,
  radius: number,
): readonly Vec3[] {
  if (count <= 0) {
    return [];
  }
  if (count === 1 || radius === 0) {
    return Array.from({ length: count }, () => ORIGIN);
  }
  const out: Vec3[] = new Array(count);
  for (let i = 0; i < count; i++) {
    const t = (i + 0.5) / count;
    const y = 1 - 2 * t;
    const r = Math.sqrt(Math.max(0, 1 - y * y));
    const theta = GOLDEN_ANGLE * i;
    out[i] = {
      x: Math.cos(theta) * r * radius,
      y: y * radius,
      z: Math.sin(theta) * r * radius,
    };
  }
  return out;
}

/** Chord length between the two nearest points of an N-point fibonacci
 *  sphere of unit radius. Used as the packing constraint when sizing
 *  a parent shell to host N equal-radius child bubbles without
 *  overlap. Memoised since N rarely changes per frame. */
const chordCache = new Map<number, number>();
export function fibonacciNearestChord(count: number): number {
  if (count <= 2) {
    return 2;
  }
  const cached = chordCache.get(count);
  if (cached !== undefined) {
    return cached;
  }
  const points = fibonacciPoints(count, 1);
  let minSq = Infinity;
  for (let i = 0; i < count; i++) {
    const pi = points[i]!;
    for (let j = i + 1; j < count; j++) {
      const pj = points[j]!;
      const dx = pi.x - pj.x;
      const dy = pi.y - pj.y;
      const dz = pi.z - pj.z;
      const sq = dx * dx + dy * dy + dz * dz;
      if (sq < minSq) {
        minSq = sq;
      }
    }
  }
  const result = Math.sqrt(minSq);
  chordCache.set(count, result);
  return result;
}

/** Write a position onto a mutable ViewNode and clear its velocity.
 *  Every layout stage ends by writing positions back via this so the
 *  renderer's assumptions (vx/vy/vz = 0 unless simulating) hold. */
export function writeNode(node: ViewNode, pos: Vec3): void {
  node.x = pos.x;
  node.y = pos.y;
  node.z = pos.z;
  node.vx = 0;
  node.vy = 0;
  node.vz = 0;
}

/** Lexicographic compare returning -1 / 0 / 1. Used as a sort tie-
 *  breaker so ordering is deterministic across platforms. */
export function compareString(a: string, b: string): number {
  if (a < b) {
    return -1;
  }
  if (a > b) {
    return 1;
  }
  return 0;
}
