/**
 * @file Cluster border layer.
 *
 * Draws a thin outline around every cluster cell so adjacent groups
 * are visually separated even when their fills sit at similar
 * intensity. Without this layer, a treemap of similar-density
 * clusters reads as one undifferentiated grid; the borders give the
 * eye a place to stop and recognise "this is one group, that is
 * another".
 *
 * Borders are tinted with the same palette-driven `clusterColor` as
 * the fill, so the line acts as both separator and category marker.
 * Top-level cluster borders are drawn thicker than nested ones so
 * the hierarchy reads at a glance — broad galaxies first, then
 * sub-groups within them.
 *
 * Implementation: one LineSegments2 mesh accumulating all rectangles.
 * Each rectangle contributes 4 line segments (TL→TR, TR→BR, BR→BL,
 * BL→TL). Colours are baked per-vertex so every border carries its
 * cluster's hue.
 */

import { Color } from "three";
import { LineSegments2 } from "three/examples/jsm/lines/LineSegments2.js";
import { LineSegmentsGeometry } from "three/examples/jsm/lines/LineSegmentsGeometry.js";
import { LineMaterial } from "three/examples/jsm/lines/LineMaterial.js";
import type { ClusterShell } from "../../types.ts";
import { clusterColor } from "./cluster-palette.ts";
import type { SceneContext } from "./scene-context.ts";

export type ClusterBorderInit = {
  readonly ctx: SceneContext;
  readonly width: number;
  readonly height: number;
};

export class ClusterBorderLayer {
  private readonly ctx: SceneContext;
  private readonly mesh: LineSegments2;
  private readonly material: LineMaterial;

  constructor(init: ClusterBorderInit) {
    this.ctx = init.ctx;
    const geom = new LineSegmentsGeometry();
    this.material = new LineMaterial({
      vertexColors: true,
      // 1.2 px: thin enough that nested borders don't crowd, thick
      // enough to read against the fill at low projected sizes.
      linewidth: 1.2,
      worldUnits: false,
      transparent: true,
      opacity: 0.65,
      depthWrite: false,
    });
    this.material.resolution.set(init.width, init.height);
    this.mesh = new LineSegments2(geom, this.material);
    this.mesh.frustumCulled = false;
    // Render after fills (-2) but before nodes (default 0), so the
    // border sits on top of its own fill but underneath nodes that
    // happen to lie on the rectangle edge.
    this.mesh.renderOrder = -1;
    this.ctx.scene.add(this.mesh);
  }

  resize(width: number, height: number): void {
    this.material.resolution.set(width, height);
  }

  rebuild(shells: readonly ClusterShell[]): void {
    // Borders only make sense for treemap-style cells, where the
    // rect is a tight non-overlapping cell. Centroid-style shells
    // (Volume / K-means) have rects that overlap freely; drawing
    // them here would produce a chaotic web of crossed boxes that
    // dominates the view (verified visually).
    const drawable = shells.filter((s) => s.kind === "treemap");
    if (drawable.length === 0) {
      this.mesh.geometry.setPositions(new Float32Array(0));
      this.mesh.geometry.setColors(new Float32Array(0));
      return;
    }
    // 4 line segments per rectangle, 2 endpoints per segment, 3 floats each.
    const SEGMENTS_PER_RECT = 4;
    const FLOATS_PER_SEGMENT = 6;
    const total = drawable.length * SEGMENTS_PER_RECT * FLOATS_PER_SEGMENT;
    const positions = new Float32Array(total);
    const colors = new Float32Array(total);
    const tinted = new Color();

    let cursor = 0;
    for (const shell of drawable) {
      const { x, y, w, h } = shell.rect;
      const x1 = x;
      const y1 = y;
      const x2 = x + w;
      const y2 = y + h;
      // Top-level shells get full-strength colour; deeper shells fade
      // toward bg so the visual hierarchy reads "broad → narrow".
      // depth=1 keeps full intensity, depth=4 fades to 30%.
      const depthMul = Math.max(0.3, 1 - (shell.depth - 1) * 0.22);
      const base = clusterColor(shell.path);
      tinted.copy(base).multiplyScalar(depthMul);
      const r = tinted.r;
      const g = tinted.g;
      const b = tinted.b;

      // 4 edges of the rectangle as line segments.
      const edges: readonly (readonly [number, number, number, number])[] = [
        [x1, y1, x2, y1], // top
        [x2, y1, x2, y2], // right
        [x2, y2, x1, y2], // bottom
        [x1, y2, x1, y1], // left
      ];
      for (const [ax, ay, bx, by] of edges) {
        positions[cursor + 0] = ax;
        positions[cursor + 1] = ay;
        positions[cursor + 2] = 0;
        positions[cursor + 3] = bx;
        positions[cursor + 4] = by;
        positions[cursor + 5] = 0;
        colors[cursor + 0] = r;
        colors[cursor + 1] = g;
        colors[cursor + 2] = b;
        colors[cursor + 3] = r;
        colors[cursor + 4] = g;
        colors[cursor + 5] = b;
        cursor += FLOATS_PER_SEGMENT;
      }
    }

    const geom = this.mesh.geometry;
    geom.setPositions(positions);
    geom.setColors(colors);
    geom.computeBoundingSphere();
  }

  dispose(): void {
    this.ctx.scene.remove(this.mesh);
    this.mesh.geometry.dispose();
    this.material.dispose();
  }
}
