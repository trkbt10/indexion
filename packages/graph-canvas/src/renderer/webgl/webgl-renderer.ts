/**
 * @file WebGL renderer — orchestrator only.
 *
 * Composes the layered renderer subsystems:
 *
 *   SceneContext     — three.js scene / camera / controls / theme
 *   CameraController — fitToView, focusOn, tween advance
 *   NodeLayer        — sphere instanced mesh + LOD
 *   EdgeLayer        — bezier polyline + arrow cones
 *   ShellLayer       — cluster outline rings
 *   LabelLayer       — DOM overlay
 *   Picker           — raycast hit-testing & screen→world projection
 *
 * This file owns *zero* per-instance buffer state and *zero* LOD math.
 * Its sole responsibility is to wire layers together, route update()
 * args to each, expose a public surface to React, and cache the latest
 * args for the RAF loop's per-frame recompute.
 */

import type {
  ClusterShell,
  FilterResult,
  RenderSettings,
  SelectionState,
  ThemeColors,
  Vec3,
  ViewGraph,
  ViewNode,
} from "../../types.ts";
import { buildDirectednessContext } from "./arrow-directedness.ts";
import { CameraController } from "./camera-controller.ts";
import { ClusterBorderLayer } from "./cluster-border-layer.ts";
import { ClusterFillLayer } from "./cluster-fill-layer.ts";
import { ClusterLabelLayer } from "./cluster-label-layer.ts";
import { EdgeLayer } from "./edge-layer.ts";
import {
  collectNeighbourIds,
  computeDegreeCap,
  computeDegreeMap,
  filterVisibleEdges,
  filterVisibleNodes,
} from "./graph-helpers.ts";
import { buildEdgeContext } from "./importance.ts";
import { LabelLayer } from "./label-layer.ts";
import { NodeLayer } from "./node-layer.ts";
import { Picker } from "./picker.ts";
import { detailFactorFromZoom } from "./projection.ts";
import { SceneContext } from "./scene-context.ts";
import { ShellLayer } from "./shell-layer.ts";

export type WebGlRendererInit = {
  readonly canvas: HTMLCanvasElement;
  readonly container: HTMLElement;
  readonly dpr: number;
  readonly width: number;
  readonly height: number;
  readonly theme: ThemeColors;
  readonly settings: RenderSettings;
};

export type UpdateArgs = {
  readonly graph: ViewGraph;
  readonly filter: FilterResult;
  readonly selection: SelectionState;
  readonly hoverNode: ViewNode | null;
  readonly theme: ThemeColors;
  readonly nodeDepth?: ReadonlyMap<string, number>;
  readonly clusterShells?: readonly ClusterShell[];
  /** Per-node cluster id used for categorical colouring. Each
   *  layout strategy is responsible for populating this; missing
   *  entries fall back to the foreground colour (ungrouped node). */
  readonly nodeCluster?: ReadonlyMap<string, string>;
};

export type ResizeArgs = {
  readonly width: number;
  readonly height: number;
  readonly dpr: number;
};

export class WebGlRenderer {
  private readonly ctx: SceneContext;
  private readonly camera: CameraController;
  private readonly nodeLayer: NodeLayer;
  private readonly edgeLayer: EdgeLayer;
  private readonly shellLayer: ShellLayer;
  private readonly clusterFillLayer: ClusterFillLayer;
  private readonly clusterBorderLayer: ClusterBorderLayer;
  private readonly clusterLabelLayer: ClusterLabelLayer;
  private readonly labels: LabelLayer;
  private readonly picker: Picker;
  private disposed = false;
  /** Latest scene state passed via update(). The RAF loop reuses
   *  these to recompute camera-dependent visibility every frame. */
  private lastUpdateArgs: UpdateArgs | null = null;

  constructor(init: WebGlRendererInit) {
    this.ctx = new SceneContext({
      canvas: init.canvas,
      width: init.width,
      height: init.height,
      dpr: init.dpr,
      theme: init.theme,
      cameraSettings: init.settings.camera,
    });
    this.camera = new CameraController({
      camera: this.ctx.camera,
      controls: this.ctx.controls,
      viewport: { width: init.width, height: init.height },
    });
    this.nodeLayer = new NodeLayer({ ctx: this.ctx, settings: init.settings.node });
    this.edgeLayer = new EdgeLayer({
      ctx: this.ctx,
      settings: init.settings.edge,
      nodeSettings: init.settings.node,
      width: init.width,
      height: init.height,
    });
    this.shellLayer = new ShellLayer({ ctx: this.ctx, settings: init.settings.shell });
    this.clusterFillLayer = new ClusterFillLayer({
      ctx: this.ctx,
      settings: init.settings.clusterFill,
    });
    this.clusterBorderLayer = new ClusterBorderLayer({
      ctx: this.ctx,
      width: init.width,
      height: init.height,
    });
    this.clusterLabelLayer = new ClusterLabelLayer({
      ctx: this.ctx,
      container: init.container,
      theme: init.theme,
    });
    this.labels = new LabelLayer({ container: init.container, theme: init.theme });
    this.picker = new Picker({
      ctx: this.ctx,
      nodeAccessor: () => ({
        mesh: this.nodeLayer.instance,
        nodes: this.nodeLayer.visibleNodes,
      }),
    });
  }

  dispose(): void {
    if (this.disposed) {
      return;
    }
    this.disposed = true;
    this.labels.dispose();
    this.clusterLabelLayer.dispose();
    this.clusterBorderLayer.dispose();
    this.clusterFillLayer.dispose();
    this.shellLayer.dispose();
    this.edgeLayer.dispose();
    this.nodeLayer.dispose();
    this.ctx.dispose();
  }

  resize(args: ResizeArgs): void {
    this.ctx.resize(args);
    this.camera.setViewport(args.width, args.height);
    this.edgeLayer.resize(args.width, args.height);
    this.clusterBorderLayer.resize(args.width, args.height);
  }

  setControlsEnabled(enabled: boolean): void {
    this.ctx.controls.enabled = enabled;
  }

  // ─── Camera control delegation ─────────────────────────────────

  getCameraSignature(): string {
    return this.camera.signature();
  }

  hasActiveTween(): boolean {
    return this.camera.hasActiveTween();
  }

  onCameraChange(listener: () => void): () => void {
    this.ctx.controls.addEventListener("change", listener);
    return () => this.ctx.controls.removeEventListener("change", listener);
  }

  tickControls(): void {
    this.camera.tick();
  }

  fitToView(nodes: readonly ViewNode[], padding = 48): void {
    this.camera.fitToView(nodes, padding);
  }

  fitToViewInstant(nodes: readonly ViewNode[], padding = 48): void {
    this.camera.fitToViewInstant(nodes, padding);
  }

  focusOn(node: ViewNode, neighbourRadius = 80): void {
    this.camera.focusOn(node, neighbourRadius);
  }

  // ─── Picking delegation ────────────────────────────────────────

  pickNodeAt(screenX: number, screenY: number): ViewNode | null {
    return this.picker.pickNodeAt(screenX, screenY);
  }

  screenToWorldOnPlane(
    screenX: number,
    screenY: number,
    worldAnchor: Vec3,
  ): Vec3 | null {
    return this.picker.screenToWorldOnPlane(screenX, screenY, worldAnchor);
  }

  // ─── State binding & rendering ─────────────────────────────────

  setTheme(theme: ThemeColors): void {
    this.ctx.applyTheme(theme);
  }

  /** Rebuild instance buffers from the current graph state. Called
   *  once per state change (graph/filter/selection/hover/theme) — and
   *  also implicitly every RAF tick via `recomputeFrame()` so the
   *  camera-dependent visibility (LOD, projected node sizes, shell
   *  ring fades) stays in sync as the camera moves. */
  update(args: UpdateArgs): void {
    this.lastUpdateArgs = args;
    this.ctx.applyTheme(args.theme);
    this.labels.setTheme(args.theme);
    this.clusterLabelLayer.setTheme(args.theme);

    const visibleNodes = filterVisibleNodes(args.graph, args.filter);
    const visibleEdges = filterVisibleEdges(args.graph, args.filter);
    const degreeMap = computeDegreeMap(args.graph, args.filter);
    const degreeCap = computeDegreeCap(degreeMap);
    const hoverNeighbors = args.hoverNode
      ? collectNeighbourIds(args.graph, args.hoverNode.id)
      : null;
    const clusterShells = args.clusterShells ?? [];
    // Compute patch visibility first so the node layer can suppress
    // nodes inside clusters that are currently rendered as patches.
    // Single source of truth for the patch/detail crossfade — both
    // layers read the same map.
    const patchVisibility = this.clusterFillLayer.computePatchVisibility(clusterShells);

    const nodeCluster = args.nodeCluster;
    this.nodeLayer.rebuild({
      visibleNodes,
      selection: args.selection,
      hoverNode: args.hoverNode,
      hoverNeighbors,
      degreeMap,
      degreeCap,
      nodeDepth: args.nodeDepth,
      clusterShells,
      patchVisibility,
      nodeCluster,
    });
    this.edgeLayer.rebuild({
      visibleEdges,
      visibleNodes,
      selection: args.selection,
      hoverNeighbors,
      edgeContext: buildEdgeContext(args.graph),
      directednessContext: buildDirectednessContext(args.graph),
      clusterShells,
      nodeCluster,
    });
    this.shellLayer.rebuild(clusterShells);
    this.clusterFillLayer.rebuild(clusterShells);
    this.clusterBorderLayer.rebuild(clusterShells);
    this.clusterLabelLayer.rebuild(clusterShells);
    this.labels.update({
      graph: args.graph,
      filter: args.filter,
      selection: args.selection,
      hoverNode: args.hoverNode,
      degreeMap,
      camera: this.ctx.camera,
      width: this.ctx.width,
      height: this.ctx.height,
      detailFactor: detailFactorFromZoom(this.ctx.camera.zoom),
      theme: args.theme,
    });
  }

  render(): void {
    if (this.disposed) {
      return;
    }
    this.ctx.renderer.render(this.ctx.scene, this.ctx.camera);
  }

  /** Recompute camera-dependent visibility for the current frame using
   *  the most recent state passed to `update()`. The RAF loop calls
   *  this every tick so LOD stays consistent as the camera tweens or
   *  the user orbits — without that, detail freezes between events. */
  recomputeFrame(): void {
    if (this.disposed || !this.lastUpdateArgs) {
      return;
    }
    this.update(this.lastUpdateArgs);
  }
}
