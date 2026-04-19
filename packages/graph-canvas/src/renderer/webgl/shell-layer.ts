/**
 * @file Cluster shell ring layer.
 *
 * Each cluster is outlined by a thin camera-facing ring. Rings appear
 * at a screen-space pixel-radius window (smoothstep in/out) so we never
 * draw rings that are sub-pixel or that wrap the viewport from the
 * inside. The ring's projected band thickness is also normalised so
 * the visible line stays ~targetBandPx wide regardless of zoom.
 *
 * Shell-instanced mesh capacity grows with the number of *visible*
 * shells, which is always far smaller than the full shell count thanks
 * to the screen-space cull.
 */

import {
  Color,
  InstancedMesh,
  Matrix4,
  MeshBasicMaterial,
  Quaternion,
  RingGeometry,
  Vector3,
} from "three";
import type { ClusterShell, ShellRenderSettings } from "../../types.ts";
import { ensureInstanceCapacity } from "./instanced-pool.ts";
import { pixelScale, smoothstep } from "./projection.ts";
import type { SceneContext } from "./scene-context.ts";

export class ShellLayer {
  private mesh: InstancedMesh;
  private readonly settings: ShellRenderSettings;
  private readonly ctx: SceneContext;
  private readonly dummyMatrix = new Matrix4();
  private readonly dummyQuat = new Quaternion();
  private readonly dummyScale = new Vector3();
  private readonly dummyPos = new Vector3();
  private readonly ringNormal = new Vector3(0, 0, 1);
  private readonly toCam = new Vector3();

  constructor(args: { readonly ctx: SceneContext; readonly settings: ShellRenderSettings }) {
    this.ctx = args.ctx;
    this.settings = args.settings;
    const geom = new RingGeometry(
      1 - this.settings.ringWidthFrac,
      1,
      this.settings.sphereSegments.width,
      1,
    );
    const mat = new MeshBasicMaterial({
      color: 0xffffff,
      transparent: true,
      opacity: this.settings.opacityPeak,
      depthWrite: false,
      side: 2,
    });
    this.mesh = new InstancedMesh(geom, mat, 0);
    this.mesh.frustumCulled = false;
    this.mesh.renderOrder = -1;
    this.ctx.scene.add(this.mesh);
  }

  rebuild(shells: readonly ClusterShell[]): void {
    const cam = this.ctx.camera.position;
    const px = pixelScale(this.ctx.camera, this.ctx.height);
    const { fadeInPx, peakLoPx, peakHiPx, fadeOutPx, ringWidthFrac, targetBandPx } =
      this.settings;
    const visible: { shell: ClusterShell; alpha: number }[] = [];
    for (const s of shells) {
      const dx = s.centre.x - cam.x;
      const dy = s.centre.y - cam.y;
      const dz = s.centre.z - cam.z;
      const dist = Math.sqrt(dx * dx + dy * dy + dz * dz) || 1;
      // Skip shells whose interior contains the camera — once the
      // camera crosses the boundary the ring wraps the viewport.
      if (dist < s.radius * 1.02) {
        continue;
      }
      const projectedPx = (s.radius / dist) * px;
      const alphaIn = smoothstep(fadeInPx, peakLoPx, projectedPx);
      const alphaOut = 1 - smoothstep(peakHiPx, fadeOutPx, projectedPx);
      const alpha = Math.min(alphaIn, alphaOut);
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
        m.renderOrder = -1;
      },
    });
    const mesh = this.mesh;
    const color = new Color();
    for (let i = 0; i < visible.length; i++) {
      const { shell: s, alpha } = visible[i]!;
      this.dummyPos.set(s.centre.x, s.centre.y, s.centre.z);
      this.toCam.set(cam.x - s.centre.x, cam.y - s.centre.y, cam.z - s.centre.z);
      const dist = Math.max(1e-3, this.toCam.length());
      this.toCam.multiplyScalar(1 / dist);
      this.dummyQuat.setFromUnitVectors(this.ringNormal, this.toCam);
      this.dummyScale.setScalar(s.radius);
      this.dummyMatrix.compose(this.dummyPos, this.dummyQuat, this.dummyScale);
      mesh.setMatrixAt(i, this.dummyMatrix);
      const bandPx = (ringWidthFrac * s.radius * px) / dist;
      const widthAttenuation =
        bandPx <= targetBandPx ? 1 : targetBandPx / bandPx;
      const tint =
        (0.4 + 0.15 * Math.min(4, s.depth)) * alpha * widthAttenuation;
      color.copy(this.ctx.bgColor).lerp(this.ctx.fgColor, tint);
      mesh.setColorAt(i, color);
    }
    mesh.count = visible.length;
    mesh.instanceMatrix.needsUpdate = true;
    if (mesh.instanceColor) {
      mesh.instanceColor.needsUpdate = true;
    }
  }

  dispose(): void {
    this.ctx.scene.remove(this.mesh);
    this.mesh.geometry.dispose();
    (this.mesh.material as MeshBasicMaterial).dispose();
  }
}
