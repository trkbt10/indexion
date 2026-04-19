/**
 * @file Node InstancedMesh layer.
 *
 * Owns the sphere-instanced node mesh, its capacity growth, the
 * per-frame LOD math (cull, fade, interior fade), the colour blend,
 * and the raycast picking surface. Reads camera state through the
 * shared SceneContext; never owns it.
 */

import {
  Color,
  InstancedMesh,
  Matrix4,
  MeshBasicMaterial,
  Quaternion,
  SphereGeometry,
  Vector3,
} from "three";
import type {
  ClusterShell,
  NodeRenderSettings,
  SelectionState,
  ViewNode,
} from "../../types.ts";
import { clusterColor } from "./cluster-palette.ts";
import { nodeImportance } from "./importance.ts";
import { ensureInstanceCapacity } from "./instanced-pool.ts";
import { pixelScale, smoothstep } from "./projection.ts";
import type { SceneContext } from "./scene-context.ts";

export type NodeRebuildArgs = {
  readonly visibleNodes: readonly ViewNode[];
  readonly selection: SelectionState;
  readonly hoverNode: ViewNode | null;
  readonly hoverNeighbors: ReadonlySet<string> | null;
  readonly degreeMap: ReadonlyMap<string, number>;
  readonly degreeCap: number;
  readonly nodeDepth?: ReadonlyMap<string, number>;
  readonly clusterShells: readonly ClusterShell[];
  /** Per-leaf-cluster patch visibility (0..1). When > 0 the cluster
   *  is painted as a density patch, so its enclosed nodes fade out
   *  proportionally. Single source of truth shared with
   *  ClusterFillLayer so the two never visually fight. */
  readonly patchVisibility: ReadonlyMap<string, number>;
  /** Per-node cluster id from the layout strategy. Used to colour
   *  the node with its cluster's palette hue so groupings read
   *  visually without hover/inspection. */
  readonly nodeCluster: ReadonlyMap<string, string> | undefined;
};

export class NodeLayer {
  private mesh: InstancedMesh;
  private visibleNodesByInstance: readonly ViewNode[] = [];
  private readonly settings: NodeRenderSettings;
  private readonly ctx: SceneContext;
  private readonly dummyMatrix = new Matrix4();
  private readonly dummyQuat = new Quaternion();
  private readonly dummyScale = new Vector3();
  private readonly dummyPos = new Vector3();

  constructor(args: { readonly ctx: SceneContext; readonly settings: NodeRenderSettings }) {
    this.ctx = args.ctx;
    this.settings = args.settings;
    // InstancedMesh multiplies material.color by the per-instance
    // color attribute set via setColorAt(). Keep the base material
    // white so instanceColor is used verbatim. Do NOT enable
    // vertexColors — that switches the shader to read geometry vertex
    // colours instead of instance colours, which is why every instance
    // would render black.
    const geom = new SphereGeometry(
      1,
      this.settings.sphereSegments.width,
      this.settings.sphereSegments.height,
    );
    const mat = new MeshBasicMaterial({ color: 0xffffff, transparent: true });
    this.mesh = new InstancedMesh(geom, mat, 0);
    this.mesh.frustumCulled = false;
    this.ctx.scene.add(this.mesh);
  }

  /** The current mesh — exposed so the picking layer can raycast it.
   *  Returned by reference; capacity growth replaces the mesh, so do
   *  not cache this value across frames. */
  get instance(): InstancedMesh {
    return this.mesh;
  }

  get visibleNodes(): readonly ViewNode[] {
    return this.visibleNodesByInstance;
  }

  rebuild(args: NodeRebuildArgs): void {
    const {
      visibleNodes,
      selection,
      hoverNode,
      hoverNeighbors,
      degreeMap,
      degreeCap,
      nodeDepth,
      clusterShells,
      patchVisibility,
      nodeCluster,
    } = args;
    this.mesh = ensureInstanceCapacity({
      mesh: this.mesh,
      count: visibleNodes.length,
      scene: this.ctx.scene,
    });
    this.visibleNodesByInstance = visibleNodes;
    const mesh = this.mesh;
    const color = new Color();
    const cam = this.ctx.camera.position;
    const px = pixelScale(this.ctx.camera, this.ctx.height);
    // Nodes whose projected screen radius is below this many pixels
    // are hidden entirely; between `cullRadius` and `fadeRadius`
    // they smoothstep-fade so nothing pops in or out.
    const MIN_SCREEN_RADIUS = this.settings.cullRadius;
    const FADE_SCREEN_RADIUS = this.settings.fadeRadius;
    const { interiorFadeLoPx, interiorFadeHiPx } = this.settings;

    // Find the deepest shell enclosing a node, project its radius to
    // pixels. Called once per node per frame — no caching needed.
    // Also returns the shell itself so the caller can read its
    // `path` for patch-visibility lookup.
    const enclosingShellFor = (node: ViewNode): ClusterShell | null => {
      let chosen: ClusterShell | null = null;
      let bestDepth = -1;
      for (const s of clusterShells) {
        if (s.depth <= bestDepth) {
          continue;
        }
        // Treemap rect membership — point-in-rect rather than
        // point-in-circle so corners of the cell are correctly
        // assigned (the inscribed disk leaves the corners outside).
        const r = s.rect;
        if (
          node.x >= r.x &&
          node.x <= r.x + r.w &&
          node.y >= r.y &&
          node.y <= r.y + r.h
        ) {
          chosen = s;
          bestDepth = s.depth;
        }
      }
      return chosen;
    };
    const interiorPxFor = (shell: ClusterShell): number => {
      const dxc = shell.centre.x - cam.x;
      const dyc = shell.centre.y - cam.y;
      const dzc = shell.centre.z - cam.z;
      const dist = Math.max(1, Math.sqrt(dxc * dxc + dyc * dyc + dzc * dzc));
      return (shell.radius * px) / dist;
    };

    for (let i = 0; i < visibleNodes.length; i++) {
      const node = visibleNodes[i]!;
      const degree = degreeMap.get(node.id) ?? 0;
      const importance = nodeImportance({ node, degree, degreeCap });
      const degreeFrac = Math.sqrt(
        Math.min(1, degree / Math.max(1, degreeCap)),
      );
      const { pixelTarget, hubScale } = this.settings;
      const targetPx = pixelTarget * (1 + (hubScale - 1) * degreeFrac);

      const dx = node.x - cam.x;
      const dy = node.y - cam.y;
      const dz = node.z - cam.z;
      const distance = Math.sqrt(dx * dx + dy * dy + dz * dz) || 1;
      const worldRadius = (targetPx * distance) / px;
      const screenRadius = targetPx;

      const interactive =
        selection.selected.has(node.id) ||
        hoverNode?.id === node.id ||
        selection.focusNeighbors.has(node.id);

      const depth = nodeDepth?.get(node.id) ?? 1;
      const enclosing = depth > 1 ? enclosingShellFor(node) : null;
      const clusterPx = enclosing ? interiorPxFor(enclosing) : Infinity;
      const interiorAlpha =
        depth <= 1
          ? 1
          : smoothstep(interiorFadeLoPx, interiorFadeHiPx, clusterPx);
      // Patch-mode suppression: when the enclosing leaf cluster is
      // currently rendered as a density patch, fade the node out by
      // the patch's visibility. This is the other half of the cross-
      // fade owned by ClusterFillLayer — they never visually fight
      // because they both consume the same `patchVisibility` map.
      const patchAlpha = enclosing
        ? 1 - (patchVisibility.get(enclosing.path) ?? 0)
        : 1;
      const combinedAlpha = interiorAlpha * patchAlpha;
      const visible =
        interactive ||
        (screenRadius >= MIN_SCREEN_RADIUS && combinedAlpha > 0.02);
      if (!visible) {
        this.dummyScale.setScalar(0);
        this.dummyPos.set(node.x, node.y, node.z);
        this.dummyQuat.identity();
        this.dummyMatrix.compose(this.dummyPos, this.dummyQuat, this.dummyScale);
        mesh.setMatrixAt(i, this.dummyMatrix);
        color.copy(this.ctx.bgColor);
        mesh.setColorAt(i, color);
        continue;
      }

      const fade = smoothstep(
        MIN_SCREEN_RADIUS,
        Math.max(MIN_SCREEN_RADIUS + 0.01, FADE_SCREEN_RADIUS),
        screenRadius,
      );

      this.dummyPos.set(node.x, node.y, node.z);
      this.dummyQuat.identity();
      this.dummyScale.setScalar(worldRadius);
      this.dummyMatrix.compose(this.dummyPos, this.dummyQuat, this.dummyScale);
      mesh.setMatrixAt(i, this.dummyMatrix);

      // Tint the node with its cluster's palette colour. Floor +
      // importance-gain mix matches the value space the foreground-
      // based version used (0.35 .. 0.80) so brightness against a
      // dark background reads about the same; only the hue shifts.
      // Nodes outside any cluster fall back to the foreground so
      // they remain visible (e.g. unclustered Volume strategy).
      const cluster = nodeCluster?.get(node.id);
      const baseColor = cluster ? clusterColor(cluster) : this.ctx.fgColor;
      color.copy(this.ctx.bgColor).lerp(baseColor, 0.35 + 0.45 * importance);
      if (selection.selected.has(node.id)) {
        color.lerp(this.ctx.selectionColor, 0.85);
      } else if (hoverNode?.id === node.id) {
        color.lerp(this.ctx.highlightColor, 0.7);
      }
      if (selection.focusCenter && !selection.focusNeighbors.has(node.id)) {
        color.lerp(this.ctx.bgColor, 0.75);
      }
      if (
        hoverNeighbors &&
        !selection.focusCenter &&
        !hoverNeighbors.has(node.id)
      ) {
        color.lerp(this.ctx.bgColor, 0.7);
      }
      if (!interactive && fade < 1) {
        color.lerp(this.ctx.bgColor, 1 - fade);
      }
      if (!interactive && combinedAlpha < 1) {
        color.lerp(this.ctx.bgColor, 1 - combinedAlpha);
      }
      mesh.setColorAt(i, color);
    }
    mesh.count = visibleNodes.length;
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
