/**
 * @file InstancedMesh capacity management.
 *
 * Each layer (nodes, arrows, shells) needs to grow its InstancedMesh
 * when the visible-instance count exceeds the current allocation. The
 * pattern is identical: power-of-two grow, dispose old, register new.
 * Centralised here so layers only declare "I want N instances" without
 * repeating the realloc dance.
 */

import {
  InstancedMesh,
  type BufferGeometry,
  type Material,
  type Scene,
} from "three";

/** Round up to the next power-of-two slot (min 64) to amortise
 *  reallocations across incremental graph updates. */
export function growCapacity(n: number): number {
  let cap = 64;
  while (cap < n) {
    cap *= 2;
  }
  return cap;
}

export type EnsureArgs = {
  readonly mesh: InstancedMesh;
  readonly count: number;
  readonly scene: Scene;
  /** Re-applied to the freshly grown mesh. Each layer has its own
   *  conventions (frustumCulled, renderOrder) — the caller bakes them
   *  into this function so they're not forgotten across reallocs. */
  readonly configure?: (mesh: InstancedMesh) => void;
};

/** Ensure the mesh has at least `count` instance slots. Returns the
 *  potentially-new mesh; callers must rebind their reference. The old
 *  mesh's geometry/material are kept (transferred to the new mesh) so
 *  there's no dispose-then-recreate churn. */
export function ensureInstanceCapacity(args: EnsureArgs): InstancedMesh {
  const { mesh, count, scene, configure } = args;
  if (mesh.instanceMatrix.count >= count) {
    mesh.count = count;
    return mesh;
  }
  const geom: BufferGeometry = mesh.geometry;
  const mat = mesh.material as Material;
  scene.remove(mesh);
  const next = new InstancedMesh(geom, mat, growCapacity(count));
  next.frustumCulled = false;
  next.count = count;
  if (configure) {
    configure(next);
  }
  scene.add(next);
  return next;
}
