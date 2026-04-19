/**
 * @file Cluster-hub bundling helpers for the edge layer.
 *
 * Hierarchical Edge Bundling lite: every edge between two top-level
 * cluster shells passes through the same bezier control point so
 * parallel edges visibly bundle into a single corridor.
 */

import type { ClusterShell, Vec3, ViewNode } from "../../types.ts";

/** A node's bundling hub: the centre + path of its enclosing
 *  top-level cluster. Centre is used as the bezier corridor anchor
 *  (object identity → cache key); path lets the edge layer look up
 *  the cluster's palette colour for length-aware edge tinting. */
export type NodeHub = {
  readonly centre: Vec3;
  readonly path: string;
};

/** For each node, build its bundling hub from the
 *  layout-strategy-supplied `nodeCluster` map. The cluster centre is
 *  the centroid of all member nodes' top-level shells — when a shell
 *  exists at depth=1 with the same path we use it directly, otherwise
 *  we synthesise a centre from the cluster's member positions.
 *
 *  Earlier versions used prefix-matching against shell paths
 *  (`node.file.startsWith(shell.path + "/")`). That worked for the
 *  hierarchy strategy but produced empty hubs for k-means and
 *  Volume + clustering, where shell paths (`kmeans-0`, `mod:foo`)
 *  don't appear in any node's file path. Having every strategy
 *  declare the assignment explicitly removes the heuristic. */
export function buildBundleHubs(args: {
  readonly shells: readonly ClusterShell[];
  readonly nodes: readonly ViewNode[];
  readonly nodeCluster: ReadonlyMap<string, string> | undefined;
}): Map<string, NodeHub> {
  const { shells, nodes, nodeCluster } = args;
  if (!nodeCluster || nodeCluster.size === 0) {
    return new Map();
  }
  // Index shells by path so we can look up a centre quickly. Prefer
  // depth=1 shells (top-level groups) when both shallow and deep
  // shells share a path.
  const shellByPath = new Map<string, ClusterShell>();
  for (const shell of shells) {
    const existing = shellByPath.get(shell.path);
    if (!existing || existing.depth > shell.depth) {
      shellByPath.set(shell.path, shell);
    }
  }
  // For clusters that don't have a matching shell (e.g. flat
  // clusterings without a treemap), compute a centroid from member
  // positions on the fly.
  const centroidCache = new Map<string, Vec3>();
  const memberLists = new Map<string, ViewNode[]>();
  for (const node of nodes) {
    const cluster = nodeCluster.get(node.id);
    if (!cluster) continue;
    const list = memberLists.get(cluster);
    if (list) {
      list.push(node);
    } else {
      memberLists.set(cluster, [node]);
    }
  }
  const centreFor = (cluster: string): Vec3 => {
    const shell = shellByPath.get(cluster);
    if (shell) return shell.centre;
    const cached = centroidCache.get(cluster);
    if (cached) return cached;
    const members = memberLists.get(cluster) ?? [];
    let cx = 0;
    let cy = 0;
    let cz = 0;
    for (const m of members) {
      cx += m.x;
      cy += m.y;
      cz += m.z;
    }
    const n = Math.max(1, members.length);
    const centre: Vec3 = { x: cx / n, y: cy / n, z: cz / n };
    centroidCache.set(cluster, centre);
    return centre;
  };

  const out = new Map<string, NodeHub>();
  for (const node of nodes) {
    const cluster = nodeCluster.get(node.id);
    if (!cluster) continue;
    out.set(node.id, { centre: centreFor(cluster), path: cluster });
  }
  return out;
}

/** Memoised bezier control point for one (srcHub, tgtHub) corridor.
 *  Every edge between the same pair picks up the identical point so
 *  curves bundle into a single visual corridor. The cache keys on
 *  Vec3 object identity — every edge between the same two top-level
 *  shells reuses the same hub centre object, so identity comparison
 *  is the natural lookup. */
export function getCorridorControl(
  cache: Map<Vec3, Map<Vec3, Vec3>>,
  srcHub: Vec3,
  tgtHub: Vec3,
): Vec3 {
  let row = cache.get(srcHub);
  if (!row) {
    row = new Map();
    cache.set(srcHub, row);
  }
  const cached = row.get(tgtHub);
  if (cached) {
    return cached;
  }
  const mid: Vec3 = {
    x: (srcHub.x + tgtHub.x) * 0.5,
    y: (srcHub.y + tgtHub.y) * 0.5,
    z: (srcHub.z + tgtHub.z) * 0.5,
  };
  row.set(tgtHub, mid);
  return mid;
}
