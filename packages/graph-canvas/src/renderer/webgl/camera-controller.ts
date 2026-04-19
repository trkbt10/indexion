/**
 * @file Camera tween / fitToView / focusOn controller.
 *
 * Owns the only mutable camera state outside of OrbitControls — the
 * tween — and exposes intent-level methods (fitToView, focusOn). Per-
 * frame ticking (tween advance + controls damping) is centralised here
 * so the RAF loop has one place to call.
 *
 * Why a separate class:
 *   - WebGlRenderer's update() is camera-agnostic; cleaner to keep
 *     camera motion isolated from instance-buffer rebuilds.
 *   - fitToView contains a robust median/percentile bounding pass that
 *     deserves its own test surface.
 */

import { Vector3 } from "three";
import type { OrbitControls } from "three/examples/jsm/controls/OrbitControls.js";
import type { PerspectiveCamera } from "three";
import type { ViewNode } from "../../types.ts";
import { easeOutCubic } from "./projection.ts";

const TWEEN_DURATION_MS = 800;

type CameraTween = {
  readonly startTime: number;
  readonly duration: number;
  readonly fromPosition: Vector3;
  readonly fromTarget: Vector3;
  readonly toPosition: Vector3;
  readonly toTarget: Vector3;
};

export type CameraControllerInit = {
  readonly camera: PerspectiveCamera;
  readonly controls: OrbitControls;
  readonly viewport: { readonly width: number; readonly height: number };
};

export class CameraController {
  private readonly camera: PerspectiveCamera;
  private readonly controls: OrbitControls;
  private readonly viewport: { width: number; height: number };
  private tween: CameraTween | null = null;

  constructor(init: CameraControllerInit) {
    this.camera = init.camera;
    this.controls = init.controls;
    this.viewport = { ...init.viewport };
  }

  setViewport(width: number, height: number): void {
    this.viewport.width = width;
    this.viewport.height = height;
  }

  hasActiveTween(): boolean {
    return this.tween !== null;
  }

  /** Signature that changes iff the camera's visible state changed
   *  (position + target). Used by the RAF loop's quiet detector. */
  signature(): string {
    const p = this.camera.position;
    const t = this.controls.target;
    return `${p.x.toFixed(3)},${p.y.toFixed(3)},${p.z.toFixed(3)}|${t.x.toFixed(3)},${t.y.toFixed(3)},${t.z.toFixed(3)}`;
  }

  /** Advance per-frame camera state: active tween animation and
   *  OrbitControls damping. The camera is otherwise static. */
  tick(): void {
    if (this.tween) {
      const elapsed = performance.now() - this.tween.startTime;
      const t = Math.min(1, elapsed / this.tween.duration);
      const eased = easeOutCubic(t);
      this.camera.position.lerpVectors(
        this.tween.fromPosition,
        this.tween.toPosition,
        eased,
      );
      this.controls.target.lerpVectors(
        this.tween.fromTarget,
        this.tween.toTarget,
        eased,
      );
      this.camera.updateProjectionMatrix();
      if (t >= 1) {
        this.tween = null;
      }
    }
    this.controls.update();
  }

  fitToView(nodes: readonly ViewNode[], padding = 48): void {
    this.fitInternal(nodes, padding, /* animated */ true);
  }

  fitToViewInstant(nodes: readonly ViewNode[], padding = 48): void {
    this.fitInternal(nodes, padding, /* animated */ false);
  }

  focusOn(node: ViewNode, neighbourRadius = 80): void {
    const centre = new Vector3(node.x, node.y, node.z);
    const halfFov = (this.camera.fov * Math.PI) / 360;
    const distance = (neighbourRadius / Math.tan(halfFov)) * 1.6;
    const viewDir = this.currentViewDir();
    const toPosition = centre.clone().addScaledVector(viewDir, distance);
    this.applyMove({
      toPosition,
      toTarget: centre.clone(),
      animated: true,
    });
  }

  private fitInternal(
    nodes: readonly ViewNode[],
    padding: number,
    animated: boolean,
  ): void {
    if (nodes.length === 0) {
      return;
    }
    // Robust bounding centre: per-axis median, not mean. Outlier
    // nodes (halos of disconnected components) bias the mean; the
    // median sits at the payload's visual centre regardless of tail.
    const xs = nodes.map((n) => n.x).sort((a, b) => a - b);
    const ys = nodes.map((n) => n.y).sort((a, b) => a - b);
    const zs = nodes.map((n) => n.z).sort((a, b) => a - b);
    const mid = Math.floor(nodes.length / 2);
    const centre = new Vector3(xs[mid]!, ys[mid]!, zs[mid]!);
    // 90th-percentile radius keeps outliers from inflating the sphere.
    const dists: number[] = [];
    for (const n of nodes) {
      const dx = n.x - centre.x;
      const dy = n.y - centre.y;
      const dz = n.z - centre.z;
      dists.push(Math.sqrt(dx * dx + dy * dy + dz * dz));
    }
    dists.sort((a, b) => a - b);
    const p90 =
      dists[Math.floor(dists.length * 0.9)] ?? dists[dists.length - 1] ?? 0;
    const radius = Math.max(1, p90);

    const halfFovY = (this.camera.fov * Math.PI) / 360;
    const aspect = Math.max(0.0001, this.viewport.width / this.viewport.height);
    const halfFovX = Math.atan(Math.tan(halfFovY) * aspect);
    const halfFov = Math.min(halfFovY, halfFovX);
    const paddingFactor =
      1 + (padding * 2) / Math.max(this.viewport.width, this.viewport.height);
    const distance = (radius / Math.sin(halfFov)) * paddingFactor;

    // Expand orbit range so the user can dive in or pull out without
    // hitting an artificial wall.
    this.controls.minDistance = 0.01;
    this.controls.maxDistance = Math.max(distance * 4, radius * 8);

    const viewDir = this.currentViewDir();
    const toPosition = centre.clone().addScaledVector(viewDir, distance);
    this.applyMove({ toPosition, toTarget: centre, animated });
  }

  private currentViewDir(): Vector3 {
    const dir = new Vector3()
      .subVectors(this.camera.position, this.controls.target)
      .normalize();
    if (dir.lengthSq() < 1e-6) {
      dir.set(0, 0, 1);
    }
    return dir;
  }

  private applyMove(args: {
    readonly toPosition: Vector3;
    readonly toTarget: Vector3;
    readonly animated: boolean;
  }): void {
    const { toPosition, toTarget, animated } = args;
    if (!animated) {
      this.tween = null;
      this.camera.position.copy(toPosition);
      this.controls.target.copy(toTarget);
      this.camera.updateProjectionMatrix();
      this.controls.update();
      return;
    }
    this.tween = {
      startTime: performance.now(),
      duration: TWEEN_DURATION_MS,
      fromPosition: this.camera.position.clone(),
      fromTarget: this.controls.target.clone(),
      toPosition: toPosition.clone(),
      toTarget: toTarget.clone(),
    };
    // Wake any RAF loop listening on OrbitControls' change event.
    this.controls.dispatchEvent({ type: "change" });
  }
}
