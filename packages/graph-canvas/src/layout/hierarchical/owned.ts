/**
 * @file Owned-leaf placement inside a cluster bubble.
 *
 * Two passes:
 *   1. Kind-band — leaves are grouped by `node.kind` and each group
 *      fills a radial band (thick shell) inside the bubble. Heavy
 *      kinds get the inner shell, light kinds the outer. Single-kind
 *      clusters collapse to a ball.
 *   2. Force relaxation — bounded spring + repulsion. Connected
 *      leaves pull together; unconnected ones spread apart.
 *
 * `edges` is optional — the pure-layout spec tests drive the placer
 * without edge data and skip phase 2.
 */

import type { LayoutSettings, ViewNode } from "../../types.ts";
import { addVec, fibonacciPoints, writeNode, type Vec3 } from "../geometry.ts";
import { relaxInCluster } from "./relax.ts";
import { orderLeavesByAdjacency, refineLeafOrderBySwaps } from "./ordering.ts";

export type OwnedPlacementArgs = {
  readonly nodes: readonly ViewNode[];
  readonly centre: Vec3;
  readonly maxRadius: number;
  readonly settings: LayoutSettings;
  readonly edges?: ReadonlyMap<string, readonly string[]>;
};

export function placeOwnedCloud(args: OwnedPlacementArgs): void {
  const { nodes, centre, maxRadius, settings, edges } = args;
  const n = nodes.length;
  if (n === 0) {
    return;
  }
  if (n === 1) {
    writeNode(nodes[0]!, centre);
    return;
  }
  const kindGroups = groupByKind(nodes);
  if (kindGroups.length <= 1) {
    placeOwnedBall(args);
  } else {
    placeOwnedByKind({ ...args, groups: kindGroups });
  }
  // Phase 2 — skip unless there's at least one internal edge pair.
  // Without springs to pull pairs together the repulsion + boundary
  // interaction equilibrates every leaf at the same radius, which
  // is exactly the "collapsed to a shell" failure mode relaxation
  // was supposed to avoid.
  if (edges && n >= 4 && hasInternalEdge(nodes, edges)) {
    relaxInCluster({
      nodes,
      centre,
      radius: maxRadius * 0.92,
      edges,
      settings: settings.intraRelax,
    });
  }
}

export type OwnedByKindArgs = OwnedPlacementArgs & {
  readonly groups: readonly (readonly ViewNode[])[];
};

export function placeOwnedByKind(args: OwnedByKindArgs): void {
  const { groups, centre, maxRadius, edges } = args;
  const totalSize = groups.reduce((s, g) => s + g.length, 0);
  // Kind-band extent kept inside the bubble — seeding leaves on the
  // shell surface would force relaxation to pull them back in.
  const innerR = maxRadius * 0.12;
  const outerR = maxRadius * 0.75;
  const bandEdges: number[] = [0];
  let acc = 0;
  for (const g of groups) {
    acc += g.length / Math.max(1, totalSize);
    bandEdges.push(acc);
  }
  groups.forEach((group, gi) => {
    const count = group.length;
    if (count === 0) {
      return;
    }
    const rLo = innerR + (outerR - innerR) * Math.cbrt(bandEdges[gi]!);
    const rHi = innerR + (outerR - innerR) * Math.cbrt(bandEdges[gi + 1]!);
    const ordered: ViewNode[] = edges
      ? orderLeavesByAdjacency(group, edges)
      : [...group];
    const unit = fibonacciPoints(count, 1);
    const positions: Vec3[] = new Array(count);
    for (let i = 0; i < count; i++) {
      const t = (i + 0.5) / count;
      const r = rLo + (rHi - rLo) * Math.cbrt(t);
      const p = unit[i]!;
      positions[i] = { x: p.x * r, y: p.y * r, z: p.z * r };
    }
    if (edges && count > 3) {
      refineLeafOrderBySwaps({ nodes: ordered, positions, edges });
    }
    for (let i = 0; i < count; i++) {
      const p = positions[i]!;
      writeNode(ordered[i]!, {
        x: centre.x + p.x,
        y: centre.y + p.y,
        z: centre.z + p.z,
      });
    }
  });
}

export function placeOwnedBall(args: OwnedPlacementArgs): void {
  const { nodes, centre, maxRadius, settings, edges } = args;
  const n = nodes.length;
  const ordered = edges ? orderLeavesByAdjacency(nodes, edges) : [...nodes];
  const footprint = settings.ownedLeafFootprint;
  const targetR = (footprint * Math.cbrt(n)) / 2;
  const ballR = Math.min(maxRadius * 0.92, targetR);
  if (n <= 6) {
    const r = Math.min(maxRadius * 0.85, (footprint * Math.sqrt(n)) / 2);
    const points = fibonacciPoints(n, r);
    for (let i = 0; i < n; i++) {
      writeNode(ordered[i]!, addVec(centre, points[i]!));
    }
    return;
  }
  const unit = fibonacciPoints(n, 1);
  for (let i = 0; i < n; i++) {
    const t = (i + 0.5) / n;
    const r = ballR * (0.12 + 0.88 * Math.cbrt(t));
    const p = unit[i]!;
    writeNode(ordered[i]!, {
      x: centre.x + p.x * r,
      y: centre.y + p.y * r,
      z: centre.z + p.z * r,
    });
  }
}

/** True iff at least one edge has both endpoints in `nodes`. */
export function hasInternalEdge(
  nodes: readonly ViewNode[],
  edges: ReadonlyMap<string, readonly string[]>,
): boolean {
  const ids = new Set(nodes.map((n) => n.id));
  for (const node of nodes) {
    const ns = edges.get(node.id);
    if (!ns) {
      continue;
    }
    for (const other of ns) {
      if (ids.has(other) && other !== node.id) {
        return true;
      }
    }
  }
  return false;
}

/** Group by `node.kind`, ordered most-populous first. */
export function groupByKind(
  nodes: readonly ViewNode[],
): readonly (readonly ViewNode[])[] {
  const byKind = new Map<string, ViewNode[]>();
  for (const node of nodes) {
    const list = byKind.get(node.kind);
    if (list) {
      list.push(node);
    } else {
      byKind.set(node.kind, [node]);
    }
  }
  return [...byKind.values()].sort((a, b) => b.length - a.length);
}
