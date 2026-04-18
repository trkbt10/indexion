/**
 * @file Intra-cluster force relaxation.
 *
 * Bounded spring + repulsion simulation on the leaves of a single
 * cluster. Starts from the kind-band placement; connected pairs
 * are pulled toward the spring rest length (a fraction of cluster
 * radius) and every pair is pushed apart by Coulomb-style repulsion.
 * Damping and the `maxStep` ceiling keep it stable.
 *
 * A soft boundary at `softR = radius × 0.7` pulls leaves back in,
 * while a hard clamp at `radius` catches the last outliers — so the
 * cluster interior reads as a filled cloud, not a surface shell.
 */

import type { IntraRelaxSettings, ViewNode } from "../../types.ts";
import type { Vec3 } from "../geometry.ts";

export type RelaxArgs = {
  readonly nodes: readonly ViewNode[];
  readonly centre: Vec3;
  readonly radius: number;
  readonly edges: ReadonlyMap<string, readonly string[]>;
  readonly settings: IntraRelaxSettings;
};

export function relaxInCluster(args: RelaxArgs): void {
  const { nodes, centre, radius, edges, settings } = args;
  const n = nodes.length;
  if (n < 2) {
    return;
  }
  const { iterations, attraction, repulsion, damping, maxStep } = settings;
  // id → node index in the current cluster. Lets neighbour lookup
  // stay O(1) inside the n² relaxation loop.
  const indexById = new Map<string, number>();
  for (let i = 0; i < n; i++) {
    indexById.set(nodes[i]!.id, i);
  }
  const neighbours: number[][] = nodes.map((node) => {
    const indices: number[] = [];
    const ns = edges.get(node.id);
    if (!ns) {
      return indices;
    }
    for (const other of ns) {
      const j = indexById.get(other);
      if (j !== undefined) {
        indices.push(j);
      }
    }
    return indices;
  });
  const xs = nodes.map((x) => x.x - centre.x);
  const ys = nodes.map((x) => x.y - centre.y);
  const zs = nodes.map((x) => x.z - centre.z);
  const vx = new Float64Array(n);
  const vy = new Float64Array(n);
  const vz = new Float64Array(n);
  const springLen = radius * 0.35;
  const maxStepAbs = radius * maxStep;
  for (let iter = 0; iter < iterations; iter++) {
    // Repulsion — O(n²) but n is a cluster's worth (<200).
    for (let i = 0; i < n; i++) {
      for (let j = i + 1; j < n; j++) {
        const dx = xs[i]! - xs[j]!;
        const dy = ys[i]! - ys[j]!;
        const dz = zs[i]! - zs[j]!;
        const dsq = dx * dx + dy * dy + dz * dz + 1;
        const f = repulsion / dsq;
        const inv = f / Math.sqrt(dsq);
        const fx = dx * inv;
        const fy = dy * inv;
        const fz = dz * inv;
        vx[i] += fx;
        vy[i] += fy;
        vz[i] += fz;
        vx[j] -= fx;
        vy[j] -= fy;
        vz[j] -= fz;
      }
    }
    // Spring attraction on each in-cluster neighbour pair.
    for (let i = 0; i < n; i++) {
      for (const j of neighbours[i]!) {
        if (j <= i) {
          continue;
        }
        const dx = xs[j]! - xs[i]!;
        const dy = ys[j]! - ys[i]!;
        const dz = zs[j]! - zs[i]!;
        const d = Math.sqrt(dx * dx + dy * dy + dz * dz) + 1e-6;
        const f = attraction * (d - springLen);
        const inv = f / d;
        const fx = dx * inv;
        const fy = dy * inv;
        const fz = dz * inv;
        vx[i] += fx;
        vy[i] += fy;
        vz[i] += fz;
        vx[j] -= fx;
        vy[j] -= fy;
        vz[j] -= fz;
      }
    }
    // Integrate + soft boundary. A hard clamp at `r = radius` would
    // pile every leaf on the shell surface once repulsion pushed
    // them outward (hollow interior failure mode). Instead a smooth
    // inward force proportional to how far outside `softR` the leaf
    // has travelled — a rubber wall that settles nodes at various
    // radii depending on local density. Hard clamp at `radius` is a
    // last resort; rare once soft pull kicks in.
    const softR = radius * 0.7;
    for (let i = 0; i < n; i++) {
      const vxi = clampAbs(vx[i]!, maxStepAbs);
      const vyi = clampAbs(vy[i]!, maxStepAbs);
      const vzi = clampAbs(vz[i]!, maxStepAbs);
      xs[i]! += vxi;
      ys[i]! += vyi;
      zs[i]! += vzi;
      const r = Math.sqrt(xs[i]! ** 2 + ys[i]! ** 2 + zs[i]! ** 2);
      if (r > softR) {
        const excess = r - softR;
        const pull = Math.min(1, excess / (radius - softR));
        const kx = xs[i]! / r;
        const ky = ys[i]! / r;
        const kz = zs[i]! / r;
        xs[i]! -= kx * excess * pull;
        ys[i]! -= ky * excess * pull;
        zs[i]! -= kz * excess * pull;
      }
      const r2 = Math.sqrt(xs[i]! ** 2 + ys[i]! ** 2 + zs[i]! ** 2);
      if (r2 > radius) {
        const k = radius / r2;
        xs[i]! *= k;
        ys[i]! *= k;
        zs[i]! *= k;
      }
      vx[i]! *= damping;
      vy[i]! *= damping;
      vz[i]! *= damping;
    }
  }
  for (let i = 0; i < n; i++) {
    nodes[i]!.x = centre.x + xs[i]!;
    nodes[i]!.y = centre.y + ys[i]!;
    nodes[i]!.z = centre.z + zs[i]!;
    nodes[i]!.vx = 0;
    nodes[i]!.vy = 0;
    nodes[i]!.vz = 0;
  }
}

export function clampAbs(v: number, max: number): number {
  if (v > max) {
    return max;
  }
  if (v < -max) {
    return -max;
  }
  return v;
}
