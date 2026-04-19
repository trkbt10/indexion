/**
 * @file Pointer hit-testing and screen→world projection.
 *
 * Wraps the raycaster lifecycle so call sites only see "screen pixels
 * in, ViewNode (or world point) out". The picker reads the current
 * node mesh through a getter so capacity-grown meshes are picked up
 * without re-binding.
 */

import { Plane, Vector3 } from "three";
import type { InstancedMesh } from "three";
import type { Vec3, ViewNode } from "../../types.ts";
import type { SceneContext } from "./scene-context.ts";

export type PickerInit = {
  readonly ctx: SceneContext;
  /** Returns the current node mesh + the visible-node array bound to
   *  it. Wrapped in a getter because the mesh is replaced when its
   *  instance pool grows. */
  readonly nodeAccessor: () => {
    readonly mesh: InstancedMesh;
    readonly nodes: readonly ViewNode[];
  };
};

export class Picker {
  private readonly ctx: SceneContext;
  private readonly nodeAccessor: PickerInit["nodeAccessor"];

  constructor(init: PickerInit) {
    this.ctx = init.ctx;
    this.nodeAccessor = init.nodeAccessor;
  }

  pickNodeAt(screenX: number, screenY: number): ViewNode | null {
    const { mesh, nodes } = this.nodeAccessor();
    if (nodes.length === 0) {
      return null;
    }
    const ndc = this.ctx.setNdc(screenX, screenY);
    this.ctx.raycaster.setFromCamera(ndc, this.ctx.camera);
    const hits = this.ctx.raycaster.intersectObject(mesh, false);
    if (hits.length === 0) {
      return null;
    }
    const id = hits[0]!.instanceId;
    if (id === undefined) {
      return null;
    }
    return nodes[id] ?? null;
  }

  /** Ray-intersect the screen pointer with the plane perpendicular to
   *  the camera that passes through `worldAnchor`. Used for node drag:
   *  anchor is the node's current world position, and the result is
   *  where the node should move to for the current pointer. */
  screenToWorldOnPlane(
    screenX: number,
    screenY: number,
    worldAnchor: Vec3,
  ): Vec3 | null {
    const ndc = this.ctx.setNdc(screenX, screenY);
    this.ctx.raycaster.setFromCamera(ndc, this.ctx.camera);
    const viewDir = new Vector3();
    this.ctx.camera.getWorldDirection(viewDir);
    const anchor = new Vector3(worldAnchor.x, worldAnchor.y, worldAnchor.z);
    const plane = new Plane().setFromNormalAndCoplanarPoint(viewDir, anchor);
    const hit = new Vector3();
    if (this.ctx.raycaster.ray.intersectPlane(plane, hit) === null) {
      return null;
    }
    return { x: hit.x, y: hit.y, z: hit.z };
  }
}
