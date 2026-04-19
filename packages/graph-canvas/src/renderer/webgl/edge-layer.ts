/**
 * @file Edge polyline + arrow head layer.
 *
 * Renders directed edges as quadratic-bezier polylines with optional
 * cluster-corridor bundling, and places small arrow cones near the
 * target end of every directed edge that survives length / proximity
 * culling. Linewidth and arrow size are coordinated through the
 * shared EdgeRenderSettings so arrows always read as a cap on the
 * line, never a separate glyph.
 *
 * Owns:
 *   - LineSegments2 (the edge polyline mesh + LineMaterial)
 *   - InstancedMesh of arrow cones
 *
 * Depends on the SceneContext for camera / theme; never on the
 * outer renderer.
 */

import {
  Color,
  ConeGeometry,
  InstancedMesh,
  Matrix4,
  MeshBasicMaterial,
  Quaternion,
  Vector3,
} from "three";
import { LineSegments2 } from "three/examples/jsm/lines/LineSegments2.js";
import { LineSegmentsGeometry } from "three/examples/jsm/lines/LineSegmentsGeometry.js";
import { LineMaterial } from "three/examples/jsm/lines/LineMaterial.js";
import type {
  ClusterShell,
  EdgeRenderSettings,
  NodeRenderSettings,
  SelectionState,
  Vec3,
  ViewEdge,
  ViewNode,
} from "../../types.ts";
import {
  edgeDirectedness,
  type DirectednessContext,
} from "./arrow-directedness.ts";
import {
  edgeImportance,
  type EdgeImportanceContext,
} from "./importance.ts";
import { buildBundleHubs, getCorridorControl } from "./bundle-hubs.ts";
import { clusterColor } from "./cluster-palette.ts";
import { ensureInstanceCapacity } from "./instanced-pool.ts";
import { lengthProximity, pixelScale } from "./projection.ts";
import type { SceneContext } from "./scene-context.ts";

export type EdgeRebuildArgs = {
  readonly visibleEdges: readonly ViewEdge[];
  readonly visibleNodes: readonly ViewNode[];
  readonly selection: SelectionState;
  readonly hoverNeighbors: ReadonlySet<string> | null;
  readonly edgeContext: EdgeImportanceContext;
  readonly directednessContext: DirectednessContext;
  readonly clusterShells: readonly ClusterShell[];
  /** Per-node cluster id from the layout strategy. Same source of
   *  truth used by the node layer for colouring; here it drives the
   *  edge gradient (src→tgt cluster colours) and the bundle hubs. */
  readonly nodeCluster: ReadonlyMap<string, string> | undefined;
};

export class EdgeLayer {
  private readonly ctx: SceneContext;
  private readonly settings: EdgeRenderSettings;
  private readonly nodeSettings: NodeRenderSettings;
  private readonly edgeLines: LineSegments2;
  private readonly edgeMaterial: LineMaterial;
  private arrowMesh: InstancedMesh;
  private readonly dummyMatrix = new Matrix4();
  private readonly dummyQuat = new Quaternion();
  private readonly dummyScale = new Vector3();
  private readonly dummyPos = new Vector3();
  private readonly arrowUp = new Vector3(0, 1, 0);
  private readonly arrowDir = new Vector3();

  constructor(args: {
    readonly ctx: SceneContext;
    readonly settings: EdgeRenderSettings;
    readonly nodeSettings: NodeRenderSettings;
    readonly width: number;
    readonly height: number;
  }) {
    this.ctx = args.ctx;
    this.settings = args.settings;
    this.nodeSettings = args.nodeSettings;
    const edgeGeom = new LineSegmentsGeometry();
    // Very thin, low per-edge opacity. A single edge is almost
    // pixel-sized; a cluster of hundreds reads as a soft haze
    // rather than a solid bar.
    this.edgeMaterial = new LineMaterial({
      vertexColors: true,
      linewidth: this.settings.linewidth,
      worldUnits: false,
      transparent: true,
      opacity: this.settings.opacity,
      alphaToCoverage: false,
      depthWrite: false,
    });
    this.edgeMaterial.resolution.set(args.width, args.height);
    this.edgeLines = new LineSegments2(edgeGeom, this.edgeMaterial);
    this.edgeLines.frustumCulled = false;
    this.ctx.scene.add(this.edgeLines);

    // Arrow cones — base at origin, tip at +Y after the constructor's
    // implicit translation.
    //
    // Material opacity matches the edge material so arrowheads read
    // as a cap on the line, not a separate opaque glyph. Without this
    // (the previous default of opacity=1), arrowheads would dominate
    // every edge while the line itself faded into the background —
    // exactly the visual imbalance the design is trying to avoid.
    // The per-arrow tint is still applied via setColorAt(); the
    // material opacity is the *ceiling* and instance color modulates
    // intensity within it.
    const arrowGeom = new ConeGeometry(1, 2, 10, 1, true);
    arrowGeom.translate(0, 1, 0);
    const arrowMat = new MeshBasicMaterial({
      color: 0xffffff,
      transparent: true,
      opacity: this.settings.opacity,
      depthWrite: false,
    });
    this.arrowMesh = new InstancedMesh(arrowGeom, arrowMat, 0);
    this.arrowMesh.frustumCulled = false;
    this.ctx.scene.add(this.arrowMesh);
  }

  resize(width: number, height: number): void {
    this.edgeMaterial.resolution.set(width, height);
  }

  rebuild(args: EdgeRebuildArgs): void {
    const {
      visibleEdges,
      visibleNodes,
      selection,
      hoverNeighbors,
      edgeContext,
      directednessContext,
      clusterShells,
      nodeCluster,
    } = args;

    const bundleHubs = buildBundleHubs({
      shells: clusterShells,
      nodes: visibleNodes,
      nodeCluster,
    });

    const n = visibleEdges.length;
    const SEGS = this.settings.bezierSegments;
    const positions = new Float32Array(n * SEGS * 6);
    const colors = new Float32Array(n * SEGS * 6);
    const corridorCache = new Map<Vec3, Map<Vec3, Vec3>>();
    const color = new Color();

    const BUNDLE = this.settings.bundleStrength;
    const { shortQuantile, longQuantile, longEdgeFloor } = this.settings;

    let shortThreshold = 0;
    let longThreshold = 0;
    if (n > 0) {
      const lengths = new Float64Array(n);
      for (let i = 0; i < n; i++) {
        const edge = visibleEdges[i]!;
        const dx = edge.target.x - edge.source.x;
        const dy = edge.target.y - edge.source.y;
        const dz = edge.target.z - edge.source.z;
        lengths[i] = Math.sqrt(dx * dx + dy * dy + dz * dz);
      }
      const sorted = Array.from(lengths).sort((a, b) => a - b);
      shortThreshold = sorted[Math.floor(sorted.length * shortQuantile)] ?? 0;
      longThreshold = sorted[Math.floor(sorted.length * longQuantile)] ?? 1;
      if (longThreshold <= shortThreshold) {
        longThreshold = shortThreshold + 1;
      }
    }

    this.arrowMesh = ensureInstanceCapacity({
      mesh: this.arrowMesh,
      count: n,
      scene: this.ctx.scene,
    });
    let arrowIndex = 0;

    const cam = this.ctx.camera.position;
    const camTarget = this.ctx.controls.target;
    const camFitDist = cam.distanceTo(camTarget) || 1;
    const cullRadius = camFitDist * 2.5;
    const cullRadiusSq = cullRadius * cullRadius;

    for (let i = 0; i < n; i++) {
      const edge = visibleEdges[i]!;
      const ax = edge.source.x;
      const ay = edge.source.y;
      const az = edge.source.z;
      const bx = edge.target.x;
      const by = edge.target.y;
      const bz = edge.target.z;

      const mxT = (ax + bx) * 0.5 - camTarget.x;
      const myT = (ay + by) * 0.5 - camTarget.y;
      const mzT = (az + bz) * 0.5 - camTarget.z;
      const midDsq = mxT * mxT + myT * myT + mzT * mzT;
      if (midDsq > cullRadiusSq) {
        writeHidden(positions, colors, i, SEGS);
        continue;
      }

      const dx = bx - ax;
      const dy = by - ay;
      const dz = bz - az;
      const length = Math.sqrt(dx * dx + dy * dy + dz * dz);
      const proximity = lengthProximity(length, shortThreshold, longThreshold);

      const mx = (ax + bx) * 0.5 - cam.x;
      const my = (ay + by) * 0.5 - cam.y;
      const mz = (az + bz) * 0.5 - cam.z;
      const edgeCamDist = Math.sqrt(mx * mx + my * my + mz * mz) || 1;
      const relDist = edgeCamDist / camFitDist;
      const nearFade = Math.min(1, Math.max(0.7, relDist));

      const srcHub = bundleHubs.get(edge.sourceId);
      const tgtHub = bundleHubs.get(edge.targetId);
      const sameCluster = !!srcHub && !!tgtHub && srcHub.path === tgtHub.path;

      const importance = edgeImportance(edge, edgeContext);
      const lengthWeight = longEdgeFloor + (1 - longEdgeFloor) * proximity;
      // Cross-cluster edges are inherently noisier (longer, more
      // numerous, often through bundling corridors). They get a
      // dimmer strong-end so the local intra-cluster structure
      // dominates the read; same-cluster edges keep their full
      // tint so each cluster's internal connectivity is legible.
      const strongEnd = sameCluster ? 0.85 : 0.45;
      const tint = (0.20 + (strongEnd - 0.20) * importance) * lengthWeight * nearFade;

      // Pick endpoint colours.
      //   - same-cluster edges: tinted by that cluster's palette
      //     colour, so internal connections take on the group hue
      //     (= "this is wiring within X")
      //   - cross-cluster edges: per-vertex gradient from src colour
      //     to tgt colour, so the eye sees the bridge as flowing
      //     from one group to another
      //   - unknown (no cluster info): fall back to the foreground
      //     so they still render as legible neutral lines.
      const srcBase = srcHub ? clusterColor(srcHub.path) : this.ctx.fgColor;
      const tgtBase = tgtHub ? clusterColor(tgtHub.path) : this.ctx.fgColor;
      const tmpSrc = new Color()
        .copy(this.ctx.bgColor)
        .lerp(srcBase, tint);
      const tmpTgt = new Color()
        .copy(this.ctx.bgColor)
        .lerp(tgtBase, tint);

      // Selection / hover dimming applies to both endpoints.
      const isFocused =
        selection.focusNeighbors.has(edge.sourceId) &&
        selection.focusNeighbors.has(edge.targetId);
      if (selection.focusCenter && !isFocused) {
        tmpSrc.lerp(this.ctx.bgColor, 0.8);
        tmpTgt.lerp(this.ctx.bgColor, 0.8);
      }
      if (hoverNeighbors && !selection.focusCenter) {
        const srcIn = hoverNeighbors.has(edge.sourceId);
        const tgtIn = hoverNeighbors.has(edge.targetId);
        if (!(srcIn && tgtIn)) {
          tmpSrc.lerp(this.ctx.bgColor, 0.75);
          tmpTgt.lerp(this.ctx.bgColor, 0.75);
        }
      }

      let cx: number;
      let cy: number;
      let cz: number;
      if (sameCluster || !srcHub || !tgtHub) {
        cx = (ax + bx) * 0.5;
        cy = (ay + by) * 0.5;
        cz = (az + bz) * 0.5;
      } else {
        const corridor = getCorridorControl(corridorCache, srcHub.centre, tgtHub.centre);
        const smx = (ax + bx) * 0.5;
        const smy = (ay + by) * 0.5;
        const smz = (az + bz) * 0.5;
        cx = smx + (corridor.x - smx) * BUNDLE;
        cy = smy + (corridor.y - smy) * BUNDLE;
        cz = smz + (corridor.z - smz) * BUNDLE;
      }

      // Walk along the bezier; at each segment endpoint, interpolate
      // the colour between src and tgt by the current parameter t so
      // the line carries a gradient from one cluster's hue to the
      // other. Same-cluster edges have tmpSrc === tmpTgt so the
      // gradient collapses to a constant — no extra cost.
      let prevX = ax;
      let prevY = ay;
      let prevZ = az;
      let prevR = tmpSrc.r;
      let prevG = tmpSrc.g;
      let prevB = tmpSrc.b;
      for (let s = 0; s < SEGS; s++) {
        const t = (s + 1) / SEGS;
        const u = 1 - t;
        const nx = u * u * ax + 2 * u * t * cx + t * t * bx;
        const ny = u * u * ay + 2 * u * t * cy + t * t * by;
        const nz = u * u * az + 2 * u * t * cz + t * t * bz;
        const nr = tmpSrc.r * u + tmpTgt.r * t;
        const ng = tmpSrc.g * u + tmpTgt.g * t;
        const nb = tmpSrc.b * u + tmpTgt.b * t;
        const base = (i * SEGS + s) * 6;
        positions[base + 0] = prevX;
        positions[base + 1] = prevY;
        positions[base + 2] = prevZ;
        positions[base + 3] = nx;
        positions[base + 4] = ny;
        positions[base + 5] = nz;
        colors[base + 0] = prevR;
        colors[base + 1] = prevG;
        colors[base + 2] = prevB;
        colors[base + 3] = nr;
        colors[base + 4] = ng;
        colors[base + 5] = nb;
        prevX = nx;
        prevY = ny;
        prevZ = nz;
        prevR = nr;
        prevG = ng;
        prevB = nb;
      }
      // Reuse `color` for the arrow placement below — match the
      // tgt-side tint so the arrowhead reads as the cap of the
      // cluster the edge points into.
      color.copy(tmpTgt);

      const directedness = edgeDirectedness(edge.kind, directednessContext);
      if (directedness >= 0.35 && proximity > 0.2) {
        this.placeArrow({ index: arrowIndex, edge, importance, directedness, color });
        arrowIndex++;
      }
    }

    const geom = this.edgeLines.geometry;
    geom.setPositions(positions);
    geom.setColors(colors);
    geom.computeBoundingSphere();

    this.arrowMesh.count = arrowIndex;
    this.arrowMesh.instanceMatrix.needsUpdate = true;
    if (this.arrowMesh.instanceColor) {
      this.arrowMesh.instanceColor.needsUpdate = true;
    }
  }

  private placeArrow(args: {
    readonly index: number;
    readonly edge: ViewEdge;
    readonly importance: number;
    readonly directedness: number;
    readonly color: Color;
  }): void {
    const { index, edge, importance, directedness, color } = args;
    const { source, target } = edge;
    this.arrowDir.set(
      target.x - source.x,
      target.y - source.y,
      target.z - source.z,
    );
    const len = this.arrowDir.length();
    if (len < 1e-6) {
      this.dummyMatrix.identity();
      this.arrowMesh.setMatrixAt(index, this.dummyMatrix);
      return;
    }
    this.arrowDir.multiplyScalar(1 / len);

    const cam = this.ctx.camera.position;
    const dx = target.x - cam.x;
    const dy = target.y - cam.y;
    const dz = target.z - cam.z;
    const targetDist = Math.sqrt(dx * dx + dy * dy + dz * dz) || 1;
    const px = pixelScale(this.ctx.camera, this.ctx.height);
    const { linewidth, arrowLengthMul, arrowAspect } = this.settings;
    const arrowPx = linewidth * arrowLengthMul * (0.85 + 0.15 * importance);
    const worldHeight = (arrowPx * targetDist) / px;
    const scaleY = worldHeight / 2;
    const scaleR = (worldHeight * arrowAspect) / 2;

    const nodeWorld = (this.nodeSettings.pixelTarget * targetDist) / px;
    const backOff = nodeWorld + worldHeight * 0.5;
    const baseX = target.x - this.arrowDir.x * backOff;
    const baseY = target.y - this.arrowDir.y * backOff;
    const baseZ = target.z - this.arrowDir.z * backOff;

    this.dummyQuat.setFromUnitVectors(this.arrowUp, this.arrowDir);
    this.dummyScale.set(scaleR, scaleY, scaleR);
    this.dummyPos.set(baseX, baseY, baseZ);
    this.dummyMatrix.compose(this.dummyPos, this.dummyQuat, this.dummyScale);
    this.arrowMesh.setMatrixAt(index, this.dummyMatrix);

    // Arrow tint sits slightly brighter than the edge body so the
    // cap reads as the visual terminus of the line — but the
    // material.opacity (matched to edge.opacity in the constructor)
    // ensures it never becomes a separate opaque glyph. Combining a
    // higher RGB intensity with the edge's alpha ceiling gives a
    // "natural extension of the line" rather than "dot at the end".
    const arrowColor = color.clone().lerp(this.ctx.fgColor, 0.4 * directedness);
    this.arrowMesh.setColorAt(index, arrowColor);
  }

  dispose(): void {
    this.ctx.scene.remove(this.edgeLines);
    this.ctx.scene.remove(this.arrowMesh);
    this.edgeLines.geometry.dispose();
    this.edgeMaterial.dispose();
    this.arrowMesh.geometry.dispose();
    (this.arrowMesh.material as MeshBasicMaterial).dispose();
  }

}

function writeHidden(
  positions: Float32Array,
  colors: Float32Array,
  edgeIdx: number,
  segs: number,
): void {
  for (let s = 0; s < segs; s++) {
    const base = (edgeIdx * segs + s) * 6;
    for (let j = 0; j < 6; j++) {
      positions[base + j] = 0;
      colors[base + j] = 0;
    }
  }
}
