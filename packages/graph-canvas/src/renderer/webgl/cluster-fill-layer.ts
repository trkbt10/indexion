/**
 * @file Cluster density-fill layer.
 *
 * At overview zoom, leaf cluster cells project to a few dozen pixels
 * — too small to read individual nodes. Drawing nodes anyway produces
 * a noisy speckle that conveys "stuff is here" but nothing more. This
 * layer instead paints the cell rectangle with a faint patch whose
 * intensity tracks the cluster's leaf count, then crossfades to the
 * detailed node view as the camera zooms in.
 *
 * Pairs with the NodeLayer's interior-LOD: when the patch is fully
 * opaque, the nodes inside the cluster are fully suppressed, and vice
 * versa. The crossfade is anchored to the same `belowPx`/`abovePx`
 * window so the two layers never visually fight.
 *
 * Geometry: a unit PlaneGeometry (1×1 in XY, z=0). One InstancedMesh
 * instance per visible leaf cell, scaled to the cell's rect.
 */

import {
  Color,
  InstancedMesh,
  Matrix4,
  MeshBasicMaterial,
  PlaneGeometry,
  Quaternion,
  Vector3,
} from "three";
import type { ClusterFillRenderSettings, ClusterShell } from "../../types.ts";
import { clusterColor } from "./cluster-palette.ts";
import { ensureInstanceCapacity } from "./instanced-pool.ts";
import { pixelScale, smoothstep } from "./projection.ts";
import type { SceneContext } from "./scene-context.ts";

export class ClusterFillLayer {
  private mesh: InstancedMesh;
  private readonly settings: ClusterFillRenderSettings;
  private readonly ctx: SceneContext;
  private readonly dummyMatrix = new Matrix4();
  private readonly dummyQuat = new Quaternion();
  private readonly dummyScale = new Vector3();
  private readonly dummyPos = new Vector3();

  constructor(args: { readonly ctx: SceneContext; readonly settings: ClusterFillRenderSettings }) {
    this.ctx = args.ctx;
    this.settings = args.settings;
    const geom = new PlaneGeometry(1, 1);
    const mat = new MeshBasicMaterial({
      color: 0xffffff,
      transparent: true,
      depthWrite: false,
    });
    this.mesh = new InstancedMesh(geom, mat, 0);
    this.mesh.frustumCulled = false;
    // Sit just behind the shell rings (-1) so density patches read as
    // a background paint, not as foreground tiles.
    this.mesh.renderOrder = -2;
    this.ctx.scene.add(this.mesh);
  }

  rebuild(shells: readonly ClusterShell[]): void {
    const cam = this.ctx.camera.position;
    const px = pixelScale(this.ctx.camera, this.ctx.height);
    const { belowPx, abovePx, opacityPeak, densityGain } = this.settings;

    // Only leaf clusters carry a fill — nested clusters are
    // represented by their children's fills aggregated in the
    // treemap. Also skip centroid-kind shells (Volume / K-means)
    // because their bounding rectangles overlap freely; painting
    // them produces a stack of translucent boxes that swamps the
    // canvas (the "boxes everywhere" failure mode the user saw on
    // the first Volume capture).
    const visible: { shell: ClusterShell; alpha: number }[] = [];
    for (const s of shells) {
      if (!s.isLeaf) {
        continue;
      }
      if (s.kind !== "treemap") {
        continue;
      }
      const dx = s.centre.x - cam.x;
      const dy = s.centre.y - cam.y;
      const dz = s.centre.z - cam.z;
      const dist = Math.sqrt(dx * dx + dy * dy + dz * dz) || 1;
      const projectedPx = (s.radius * px) / dist;
      // Patch alpha = 1 below `belowPx`, 0 above `abovePx`, smoothstep
      // between. Inverted from node interior-fade so the two cross
      // exactly.
      const visibility = 1 - smoothstep(belowPx, abovePx, projectedPx);
      if (visibility <= 0.01) {
        continue;
      }
      // Density: log10(1 + leafCount) / densityGain. Floor at 0.15
      // so even tiny leaf clusters are perceptible — otherwise they
      // disappear into the background.
      const density = Math.min(
        1,
        Math.max(0.15, Math.log10(1 + s.leafCount) / densityGain),
      );
      const alpha = opacityPeak * visibility * density;
      if (alpha <= 0.01) {
        continue;
      }
      visible.push({ shell: s, alpha });
    }

    this.mesh = ensureInstanceCapacity({
      mesh: this.mesh,
      count: visible.length,
      scene: this.ctx.scene,
      configure: (m) => {
        m.renderOrder = -2;
      },
    });
    const mesh = this.mesh;
    const color = new Color();
    this.dummyQuat.identity();
    for (let i = 0; i < visible.length; i++) {
      const { shell: s, alpha } = visible[i]!;
      const rect = s.rect;
      this.dummyPos.set(rect.x + rect.w / 2, rect.y + rect.h / 2, 0);
      this.dummyScale.set(Math.max(rect.w, 1e-6), Math.max(rect.h, 1e-6), 1);
      this.dummyMatrix.compose(this.dummyPos, this.dummyQuat, this.dummyScale);
      mesh.setMatrixAt(i, this.dummyMatrix);
      // Fill colour blends bg → cluster's palette colour by `alpha`.
      // Using the categorical palette here (instead of fg) gives
      // each top-level group its own visual region without raising
      // the overall brightness — the alpha still controls intensity
      // so dense and sparse clusters read at the right depth.
      color.copy(this.ctx.bgColor).lerp(clusterColor(s.path), alpha);
      mesh.setColorAt(i, color);
    }
    mesh.count = visible.length;
    mesh.instanceMatrix.needsUpdate = true;
    if (mesh.instanceColor) {
      mesh.instanceColor.needsUpdate = true;
    }
  }

  /** Per-leaf-cluster patch visibility (0..1). The NodeLayer reads
   *  this via the same shell ids so each node knows whether its
   *  cluster is currently in patch-mode (suppress me) or detail-mode
   *  (show me). Returned as a Map keyed by cluster path. */
  computePatchVisibility(shells: readonly ClusterShell[]): ReadonlyMap<string, number> {
    const cam = this.ctx.camera.position;
    const px = pixelScale(this.ctx.camera, this.ctx.height);
    const { belowPx, abovePx } = this.settings;
    const out = new Map<string, number>();
    for (const s of shells) {
      if (!s.isLeaf || s.kind !== "treemap") {
        continue;
      }
      const dx = s.centre.x - cam.x;
      const dy = s.centre.y - cam.y;
      const dz = s.centre.z - cam.z;
      const dist = Math.sqrt(dx * dx + dy * dy + dz * dz) || 1;
      const projectedPx = (s.radius * px) / dist;
      const visibility = 1 - smoothstep(belowPx, abovePx, projectedPx);
      if (visibility > 0.01) {
        out.set(s.path, visibility);
      }
    }
    return out;
  }

  dispose(): void {
    this.ctx.scene.remove(this.mesh);
    this.mesh.geometry.dispose();
    (this.mesh.material as MeshBasicMaterial).dispose();
  }
}
