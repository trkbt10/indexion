/**
 * @file WebGL renderer backed by three.js.
 *
 * Responsibilities:
 *   - Scene management, perspective camera, OrbitControls.
 *   - Node & edge rendering via InstancedMesh. Each instance carries
 *     its own colour and transform, built from a scalar "importance"
 *     feature so the visual encoding is continuous rather than
 *     categorical.
 *   - DOM label overlay (LabelLayer) with screen-space projection.
 *   - Raycaster-based node picking.
 *   - One-shot setGraph / update flow; the renderer never computes
 *     layout — positions come from the layout module.
 */

import {
  Color,
  ConeGeometry,
  InstancedMesh,
  Matrix4,
  MeshBasicMaterial,
  PerspectiveCamera,
  Plane,
  Quaternion,
  Raycaster,
  RingGeometry,
  Scene,
  SphereGeometry,
  Vector2,
  Vector3,
  WebGLRenderer,
} from "three";
import { OrbitControls } from "three/examples/jsm/controls/OrbitControls.js";
import { LineSegments2 } from "three/examples/jsm/lines/LineSegments2.js";
import { LineSegmentsGeometry } from "three/examples/jsm/lines/LineSegmentsGeometry.js";
import { LineMaterial } from "three/examples/jsm/lines/LineMaterial.js";
import type {
  FilterResult,
  RenderSettings,
  SelectionState,
  ThemeColors,
  ViewEdge,
  ViewGraph,
  ViewNode,
} from "../../types.ts";
import {
  buildDirectednessContext,
  edgeDirectedness,
  type DirectednessContext,
} from "./arrow-directedness.ts";
import {
  buildEdgeContext,
  edgeImportance,
  nodeImportance,
  type EdgeImportanceContext,
} from "./importance.ts";
import { LabelLayer } from "./label-layer.ts";

export type WebGlRendererInit = {
  readonly canvas: HTMLCanvasElement;
  /** Parent of the canvas; used to mount the label overlay. */
  readonly container: HTMLElement;
  readonly dpr: number;
  readonly width: number;
  readonly height: number;
  readonly theme: ThemeColors;
  /** All visual tuning knobs. See types.ts RenderSettings. */
  readonly settings: RenderSettings;
};

export type UpdateArgs = {
  readonly graph: ViewGraph;
  readonly filter: FilterResult;
  readonly selection: SelectionState;
  readonly hoverNode: ViewNode | null;
  readonly theme: ThemeColors;
  /** Per-node hierarchy depth (1 = top folder). Missing for
   *  strategies that don't expose a hierarchy. */
  readonly nodeDepth?: ReadonlyMap<string, number>;
  /** Nested cluster outlines from hierarchical layouts. If given,
   *  the renderer draws each shell as a faint wireframe sphere so
   *  the user can see the nesting (pkg/foo encloses pkg/foo/bar
   *  encloses pkg/foo/bar/baz etc.). */
  readonly clusterShells?: readonly ClusterShellInput[];
};

export type ClusterShellInput = {
  readonly path: string;
  readonly centre: {
    readonly x: number;
    readonly y: number;
    readonly z: number;
  };
  readonly radius: number;
  readonly depth: number;
};

export type ResizeArgs = {
  readonly width: number;
  readonly height: number;
  readonly dpr: number;
};

const TWEEN_DURATION_MS = 800;

type CameraTween = {
  readonly startTime: number;
  readonly duration: number;
  readonly fromPosition: Vector3;
  readonly fromTarget: Vector3;
  readonly toPosition: Vector3;
  readonly toTarget: Vector3;
};

export class WebGlRenderer {
  private readonly renderer: WebGLRenderer;
  private readonly scene: Scene;
  private readonly camera: PerspectiveCamera;
  private readonly controls: OrbitControls;
  private readonly labels: LabelLayer;
  private readonly settings: RenderSettings;
  private nodeMesh: InstancedMesh;
  private arrowMesh: InstancedMesh;
  private shellMesh: InstancedMesh;
  private readonly edgeLines: LineSegments2;
  private readonly edgeMaterial: LineMaterial;
  /** Nodes keyed by the instance index used in the current frame. */
  private visibleNodesByInstance: readonly ViewNode[] = [];
  private readonly fgColor = new Color();
  private readonly bgColor = new Color();
  private readonly selectionColor = new Color();
  private readonly highlightColor = new Color();
  private readonly dummyMatrix = new Matrix4();
  private readonly dummyQuat = new Quaternion();
  private readonly dummyScale = new Vector3();
  private readonly dummyPos = new Vector3();
  private readonly arrowUp = new Vector3(0, 1, 0);
  private readonly arrowDir = new Vector3();
  private readonly raycaster = new Raycaster();
  private readonly ndc = new Vector2();
  /** Active camera tween state. null when the camera is idle. */
  private tween: CameraTween | null = null;
  private width: number;
  private height: number;
  private disposed = false;

  constructor(init: WebGlRendererInit) {
    this.settings = init.settings;
    this.width = init.width;
    this.height = init.height;

    this.renderer = new WebGLRenderer({
      canvas: init.canvas,
      antialias: true,
      alpha: true,
      powerPreference: "high-performance",
    });
    this.renderer.setPixelRatio(init.dpr);
    this.renderer.setSize(init.width, init.height, false);
    this.renderer.setClearColor(new Color(init.theme.background), 1);

    this.scene = new Scene();
    this.camera = new PerspectiveCamera(
      this.settings.camera.fov,
      init.width / init.height,
      this.settings.camera.near,
      this.settings.camera.far,
    );
    this.camera.position.set(0, 0, 1200);
    this.camera.lookAt(0, 0, 0);

    this.controls = new OrbitControls(this.camera, init.canvas);
    this.controls.enableDamping = true;
    this.controls.dampingFactor = 0.12;
    this.controls.rotateSpeed = 0.8;
    this.controls.panSpeed = 1;
    this.controls.zoomSpeed = 1;
    this.controls.screenSpacePanning = false;
    this.controls.zoomToCursor = false;
    this.controls.enableZoom = false;
    this.controls.minDistance = this.settings.camera.minDistance;
    this.controls.maxDistance = this.settings.camera.maxDistance;
    this.installCursorZoom(init.canvas);

    // Node instanced mesh — start with a small allocation; rebuilt on
    // setGraph.
    // InstancedMesh multiplies material.color by the per-instance
    // color attribute set via setColorAt(). Keep the base material
    // white so instanceColor is used verbatim. Do NOT enable
    // vertexColors — that switches the shader to read geometry vertex
    // colours instead of instance colours, which is why every instance
    // would render black.
    const nodeGeom = new SphereGeometry(
      1,
      this.settings.node.sphereSegments.width,
      this.settings.node.sphereSegments.height,
    );
    const nodeMat = new MeshBasicMaterial({
      color: 0xffffff,
      transparent: true,
    });
    this.nodeMesh = new InstancedMesh(nodeGeom, nodeMat, 0);
    this.nodeMesh.frustumCulled = false;
    this.scene.add(this.nodeMesh);

    // Edges use LineSegments2 so line width is specified in screen
    // pixels and stays legible regardless of camera distance or
    // rotation. Per-vertex colours carry the continuous importance
    // encoding.
    const edgeGeom = new LineSegmentsGeometry();
    // Very thin, low per-edge opacity. A single edge is almost
    // pixel-sized; a cluster of hundreds reads as a soft haze
    // rather than a solid bar. Linewidth is kept near the
    // sub-pixel floor so overlapping edges still have room to
    // bundle visually instead of saturating.
    this.edgeMaterial = new LineMaterial({
      vertexColors: true,
      linewidth: this.settings.edge.linewidth,
      worldUnits: false,
      transparent: true,
      opacity: this.settings.edge.opacity,
      alphaToCoverage: false,
      depthWrite: false,
    });
    this.edgeMaterial.resolution.set(init.width, init.height);
    this.edgeLines = new LineSegments2(edgeGeom, this.edgeMaterial);
    this.edgeLines.frustumCulled = false;
    this.scene.add(this.edgeLines);

    // Arrowheads — tiny cones placed near the target end of each
    // directed edge. Same per-instance colour trick as nodeMesh:
    // material.color stays white, setColorAt() paints each arrow.
    const arrowGeom = new ConeGeometry(1, 2, 10, 1, true);
    // ConeGeometry is centred on its midpoint with the tip at +Y.
    // Translate down so the base sits at origin and the tip is at
    // (0, 2, 0), making per-instance placement a "place base, point
    // toward target" operation.
    arrowGeom.translate(0, 1, 0);
    const arrowMat = new MeshBasicMaterial({
      color: 0xffffff,
      transparent: true,
    });
    this.arrowMesh = new InstancedMesh(arrowGeom, arrowMat, 0);
    this.arrowMesh.frustumCulled = false;
    this.scene.add(this.arrowMesh);

    // Cluster shells: faint wireframe spheres that outline each
    // nesting level from the hierarchical layout. Low-poly sphere
    // because we may render thousands. Even at 8×6 triangles per
    // shell this is tractable for ~1000 shells; the renderer also
    // screen-culls tiny shells in rebuildShells.
    // Shells render as thin camera-facing rings — silhouette
    // outlines of each cluster bubble. Rings read unambiguously as
    // "cluster boundary" whatever the zoom level, unlike a wireframe
    // sphere whose overlapping lines turn into a gray wash near the
    // horizon. The ring starts at inner=0.992 — the per-frame logic
    // in rebuildShells *shrinks the inner radius further* for
    // instances that are close to the camera so the visible line
    // stays ~2 px wide regardless of projected size.
    const shellGeom = new RingGeometry(
      1 - this.settings.shell.ringWidthFrac,
      1,
      this.settings.shell.sphereSegments.width,
      1,
    );
    const shellMat = new MeshBasicMaterial({
      color: 0xffffff,
      transparent: true,
      opacity: this.settings.shell.opacityPeak,
      depthWrite: false,
      side: 2, // DoubleSide — ring is a 2D disc, user may see either face
    });
    this.shellMesh = new InstancedMesh(shellGeom, shellMat, 0);
    this.shellMesh.frustumCulled = false;
    this.shellMesh.renderOrder = -1;
    this.scene.add(this.shellMesh);

    this.labels = new LabelLayer({
      container: init.container,
      theme: init.theme,
    });

    this.applyTheme(init.theme);
  }

  dispose(): void {
    if (this.disposed) {
      return;
    }
    this.disposed = true;
    this.labels.dispose();
    this.controls.dispose();
    this.scene.remove(this.nodeMesh);
    this.scene.remove(this.edgeLines);
    this.scene.remove(this.arrowMesh);
    this.scene.remove(this.shellMesh);
    this.shellMesh.geometry.dispose();
    (this.shellMesh.material as MeshBasicMaterial).dispose();
    this.nodeMesh.geometry.dispose();
    (this.nodeMesh.material as MeshBasicMaterial).dispose();
    this.edgeLines.geometry.dispose();
    this.edgeMaterial.dispose();
    this.arrowMesh.geometry.dispose();
    (this.arrowMesh.material as MeshBasicMaterial).dispose();
    this.renderer.dispose();
  }

  /** Cursor-origin zoom handler. Substitutes OrbitControls' built-in
   *  wheel zoom because that implementation clamps distance in a way
   *  that conflicts with screenSpacePanning and fails to reach the
   *  minimum distance even after many wheel ticks.
   *
   *  Each wheel tick multiplies the camera-to-target distance by a
   *  geometric factor. Zooming *in* also pulls both the camera and
   *  the target toward the point the cursor is currently hovering,
   *  so the view actually converges on where the user is looking —
   *  not on the fixed centre of the scene. */
  private installCursorZoom(canvas: HTMLCanvasElement): void {
    const raycaster = this.raycaster;
    const ndc = new Vector2();
    const pointerWorld = new Vector3();
    const plane = new Plane();
    const viewDir = new Vector3();
    const toCursor = new Vector3();
    const camToTarget = new Vector3();

    const zoomPerTick = this.settings.camera.zoomPerTick;
    const targetFollow = this.settings.camera.targetFollow;
    canvas.addEventListener(
      "wheel",
      (event: WheelEvent) => {
        event.preventDefault();
        const rect = canvas.getBoundingClientRect();
        const x = event.clientX - rect.left;
        const y = event.clientY - rect.top;
        ndc.set((x / rect.width) * 2 - 1, -((y / rect.height) * 2 - 1));
        raycaster.setFromCamera(ndc, this.camera);

        // Project the cursor ray onto the viewplane through the
        // current orbit target. That point is the "where the user is
        // pointing" anchor we dolly toward.
        this.camera.getWorldDirection(viewDir);
        plane.setFromNormalAndCoplanarPoint(viewDir, this.controls.target);
        const hit = raycaster.ray.intersectPlane(plane, pointerWorld);
        const anchor = hit ? pointerWorld : this.controls.target;

        // Multiplicative distance change — stable across magnitudes
        // so a single graph load can zoom from world-radius to node-
        // radius without hitting any special-case limits.
        const scale = Math.exp(event.deltaY * 0.01 * zoomPerTick);
        camToTarget.subVectors(this.camera.position, this.controls.target);
        const prevRadius = camToTarget.length();
        const nextRadius = clamp(
          prevRadius * scale,
          this.controls.minDistance,
          this.controls.maxDistance,
        );
        const actualScale = prevRadius > 0 ? nextRadius / prevRadius : 1;

        // Move the camera toward the anchor by `1 - actualScale` of
        // its distance to the anchor. When zooming in we also pull
        // the target (which is where OrbitControls orbits around)
        // toward the anchor — but only a fraction of what the camera
        // moves. Keeping target "near" the anchor lets subsequent
        // orbit drags rotate around what the user was looking at,
        // instead of around the old scene centroid.
        toCursor.subVectors(anchor, this.camera.position);
        this.camera.position.addScaledVector(toCursor, 1 - actualScale);
        toCursor.subVectors(anchor, this.controls.target);
        // Tug the target by `settings.camera.targetFollow` of the
        // camera's step so the orbit centre follows the user's
        // interest without overshooting past it.
        this.controls.target.addScaledVector(
          toCursor,
          (1 - actualScale) * targetFollow,
        );
        this.camera.updateMatrixWorld();
        // Wake any RAF loop listening on OrbitControls' change event.
        this.controls.dispatchEvent({ type: "change" });
      },
      { passive: false },
    );
  }

  resize(args: ResizeArgs): void {
    this.width = args.width;
    this.height = args.height;
    this.renderer.setPixelRatio(args.dpr);
    this.renderer.setSize(args.width, args.height, false);
    this.camera.aspect = args.width / args.height;
    this.camera.updateProjectionMatrix();
    this.edgeMaterial.resolution.set(args.width, args.height);
  }

  /**
   * Enable or disable OrbitControls. Disable while a node is being
   * dragged so camera movement doesn't fight the drag.
   */
  setControlsEnabled(enabled: boolean): void {
    this.controls.enabled = enabled;
  }

  /**
   * Signature that changes iff the camera's visible state changed
   * (position + target). Used by the host RAF loop to decide whether
   * there's anything new to draw.
   */
  getCameraSignature(): string {
    const p = this.camera.position;
    const t = this.controls.target;
    return `${p.x.toFixed(3)},${p.y.toFixed(3)},${p.z.toFixed(3)}|${t.x.toFixed(3)},${t.y.toFixed(3)},${t.z.toFixed(3)}`;
  }

  /** True while a focus / fit tween is in progress. */
  hasActiveTween(): boolean {
    return this.tween !== null;
  }

  /** Subscribe to user-initiated camera changes (mouse drag to orbit,
   *  wheel to zoom). Lets the host RAF loop kick back on when the
   *  camera starts moving again after idling. */
  onCameraChange(listener: () => void): () => void {
    this.controls.addEventListener("change", listener);
    return () => this.controls.removeEventListener("change", listener);
  }

  /**
   * Advance per-frame camera state: active tween animation and
   * OrbitControls damping. The camera is otherwise static — no
   * idle-time movement.
   */
  tickControls(): void {
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

  /**
   * Compute the distance required to fit a bounding sphere at the
   * camera's FOV, then move the camera along its current view vector
   * so the node cloud fills the viewport (minus padding).
   */
  fitToView(nodes: readonly ViewNode[], padding = 48): void {
    this.fitToViewInternal(nodes, padding, /* animated */ true);
  }

  /** Instant version used the very first time a graph loads — we
   *  don't want the camera to fly in from the default position. */
  fitToViewInstant(nodes: readonly ViewNode[], padding = 48): void {
    this.fitToViewInternal(nodes, padding, /* animated */ false);
  }

  private fitToViewInternal(
    nodes: readonly ViewNode[],
    padding: number,
    animated: boolean,
  ): void {
    if (nodes.length === 0) {
      return;
    }
    // Robust bounding centre: per-axis median, not mean. The mean
    // is biased by outlier nodes (e.g. a halo of disconnected
    // components far from the main cluster); the median sits at
    // the payload's visual centre regardless of tail shape.
    const xs = nodes.map((n) => n.x).sort((a, b) => a - b);
    const ys = nodes.map((n) => n.y).sort((a, b) => a - b);
    const zs = nodes.map((n) => n.z).sort((a, b) => a - b);
    const mid = Math.floor(nodes.length / 2);
    const centre = new Vector3(xs[mid]!, ys[mid]!, zs[mid]!);
    // Robust radius: 90th-percentile distance from the median
    // centre. Keeps outliers from inflating the bounding sphere.
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

    // Pick a camera distance so the bounding sphere fits entirely in
    // the smaller-of-h-or-w dimension (plus padding). Using the
    // smaller dimension so portrait windows still show the full graph.
    const halfFovY = (this.camera.fov * Math.PI) / 360;
    const aspect = Math.max(0.0001, this.width / this.height);
    const halfFovX = Math.atan(Math.tan(halfFovY) * aspect);
    const halfFov = Math.min(halfFovY, halfFovX);
    const paddingFactor = 1 + (padding * 2) / Math.max(this.width, this.height);
    const distance = (radius / Math.sin(halfFov)) * paddingFactor;

    // Expand the OrbitControls range so the user can actually reach
    // both the overview and a single-node close-up. Min is tiny so
    // dives into a specific node are not blocked; max is generous
    // so pulling back for context works without a wall.
    this.controls.minDistance = 0.01;
    this.controls.maxDistance = Math.max(distance * 4, radius * 8);

    // Keep the current view direction; just move along it.
    const viewDir = new Vector3()
      .subVectors(this.camera.position, this.controls.target)
      .normalize();
    if (viewDir.lengthSq() < 1e-6) {
      viewDir.set(0, 0, 1);
    }
    const toPosition = centre.clone().addScaledVector(viewDir, distance);
    this.applyCameraMove({ toPosition, toTarget: centre, animated });
  }

  /**
   * Aim the camera at a specific node at a near distance so the user
   * can inspect it and its immediate neighbourhood. The view direction
   * is preserved; only target + position move along it.
   */
  focusOn(node: ViewNode, neighbourRadius = 80): void {
    const centre = new Vector3(node.x, node.y, node.z);
    // Distance that makes a sphere of `neighbourRadius` fill ~60% of
    // the vertical viewport. Tuned to feel close-up without clipping.
    const halfFov = (this.camera.fov * Math.PI) / 360;
    const distance = (neighbourRadius / Math.tan(halfFov)) * 1.6;
    const viewDir = new Vector3()
      .subVectors(this.camera.position, this.controls.target)
      .normalize();
    if (viewDir.lengthSq() < 1e-6) {
      viewDir.set(0, 0, 1);
    }
    const toPosition = centre.clone().addScaledVector(viewDir, distance);
    this.applyCameraMove({
      toPosition,
      toTarget: centre.clone(),
      animated: true,
    });
  }

  /**
   * Schedule a camera move. `animated=false` snaps immediately (used
   * for the initial fit); `animated=true` kicks off an easing tween
   * that tickControls drains over TWEEN_DURATION_MS.
   */
  private applyCameraMove(args: {
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
    // Wake the host's RAF loop — otherwise a fit-to-view / focus-on
    // tween kicked off while the scene is idle (camera not moving)
    // never actually plays because nothing ticks tickControls.
    this.controls.dispatchEvent({ type: "change" });
  }

  /**
   * Ray-intersect the screen pointer with the plane perpendicular to
   * the camera that passes through `worldAnchor`. Used for node drag:
   * anchor is the node's current world position, and the result is
   * where the node should move to for the current pointer.
   */
  screenToWorldOnPlane(
    screenX: number,
    screenY: number,
    worldAnchor: { readonly x: number; readonly y: number; readonly z: number },
  ): { readonly x: number; readonly y: number; readonly z: number } | null {
    this.ndc.set(
      (screenX / this.width) * 2 - 1,
      -((screenY / this.height) * 2 - 1),
    );
    this.raycaster.setFromCamera(this.ndc, this.camera);
    const viewDir = new Vector3();
    this.camera.getWorldDirection(viewDir);
    const anchor = new Vector3(worldAnchor.x, worldAnchor.y, worldAnchor.z);
    const plane = new Plane().setFromNormalAndCoplanarPoint(viewDir, anchor);
    const hit = new Vector3();
    if (this.raycaster.ray.intersectPlane(plane, hit) === null) {
      return null;
    }
    return { x: hit.x, y: hit.y, z: hit.z };
  }

  /**
   * Hit-test: return the ViewNode under the given screen position, or
   * null. Raycasts against the node InstancedMesh; the slight sphere
   * geometry makes this robust to picking off-centre hits.
   */
  pickNodeAt(screenX: number, screenY: number): ViewNode | null {
    if (this.visibleNodesByInstance.length === 0) {
      return null;
    }
    this.ndc.set(
      (screenX / this.width) * 2 - 1,
      -((screenY / this.height) * 2 - 1),
    );
    this.raycaster.setFromCamera(this.ndc, this.camera);
    const hits = this.raycaster.intersectObject(this.nodeMesh, false);
    if (hits.length === 0) {
      return null;
    }
    const id = hits[0]!.instanceId;
    if (id === undefined) {
      return null;
    }
    return this.visibleNodesByInstance[id] ?? null;
  }

  setTheme(theme: ThemeColors): void {
    this.applyTheme(theme);
  }

  /** Rebuild instance buffers from the current graph state. */
  update(args: UpdateArgs): void {
    this.applyTheme(args.theme);
    this.labels.setTheme(args.theme);
    const visibleNodes = filterVisibleNodes(args.graph, args.filter);
    const visibleEdges = filterVisibleEdges(args.graph, args.filter);
    const degreeMap = computeDegreeMap(args.graph, args.filter);
    let degreeCap = 4;
    for (const v of degreeMap.values()) {
      if (v > degreeCap) {
        degreeCap = v;
      }
    }

    // Obsidian-style hover: the hovered node and its immediate
    // neighbours light up, everything else dims. Computed once per
    // frame so nodes and edges agree on who is "lit".
    const hoverNeighbors = args.hoverNode
      ? collectNeighbourIds(args.graph, args.hoverNode.id)
      : null;

    this.rebuildNodes({
      visibleNodes,
      selection: args.selection,
      hoverNode: args.hoverNode,
      hoverNeighbors,
      degreeMap,
      degreeCap,
      nodeDepth: args.nodeDepth,
      clusterShells: args.clusterShells ?? [],
    });
    const edgeContext = buildEdgeContext(args.graph);
    const directednessContext = buildDirectednessContext(args.graph);
    const bundleHubs = buildBundleHubs({
      shells: args.clusterShells ?? [],
      nodes: visibleNodes,
    });
    this.rebuildEdges({
      visibleEdges,
      selection: args.selection,
      hoverNeighbors,
      edgeContext,
      directednessContext,
      bundleHubs,
    });
    this.rebuildShells(args.clusterShells ?? []);

    this.labels.update({
      graph: args.graph,
      filter: args.filter,
      selection: args.selection,
      hoverNode: args.hoverNode,
      degreeMap,
      camera: this.camera,
      width: this.width,
      height: this.height,
      detailFactor: detailFactorFromZoom(this.camera.zoom),
      theme: args.theme,
    });
  }

  render(): void {
    if (this.disposed) {
      return;
    }
    this.renderer.render(this.scene, this.camera);
  }

  // ─── Internals ───────────────────────────────────────────────────

  private applyTheme(theme: ThemeColors): void {
    this.fgColor.set(theme.labelColor);
    this.bgColor.set(theme.background);
    this.selectionColor.set(theme.selectionColor);
    this.highlightColor.set(theme.highlightColor);
    this.renderer.setClearColor(this.bgColor, 1);
  }

  private ensureNodeCapacity(count: number): void {
    if (this.nodeMesh.instanceMatrix.count >= count) {
      this.nodeMesh.count = count;
      return;
    }
    const geom = this.nodeMesh.geometry;
    const mat = this.nodeMesh.material as MeshBasicMaterial;
    this.scene.remove(this.nodeMesh);
    this.nodeMesh = new InstancedMesh(geom, mat, growCapacity(count));
    this.nodeMesh.frustumCulled = false;
    this.nodeMesh.count = count;
    this.scene.add(this.nodeMesh);
  }

  private ensureArrowCapacity(count: number): void {
    if (this.arrowMesh.instanceMatrix.count >= count) {
      this.arrowMesh.count = count;
      return;
    }
    const geom = this.arrowMesh.geometry;
    const mat = this.arrowMesh.material as MeshBasicMaterial;
    this.scene.remove(this.arrowMesh);
    this.arrowMesh = new InstancedMesh(geom, mat, growCapacity(count));
    this.arrowMesh.frustumCulled = false;
    this.arrowMesh.count = count;
    this.scene.add(this.arrowMesh);
  }

  /** Draw cluster shells as faint wireframe spheres. We screen-cull
   *  shells outside a usable pixel-radius range (too small = visual
   *  noise, too big = already enclosing the camera so no useful
   *  outline). With 9000+ raw shells in a real graph the cull keeps
   *  draw counts to the hundreds. */
  private rebuildShells(shells: readonly ClusterShellInput[]): void {
    const cam = this.camera.position;
    const pxScale = this.pixelScale();
    // Smooth LOD: alpha is a `smoothstep × (1 − smoothstep)`-style
    // curve keyed on the shell's projected pixel radius. That
    // gives C¹-continuous fade in at `fadeIn→peakLo`, a plateau at
    // 1 across `peakLo→peakHi`, and a C¹ fade out at
    // `peakHi→fadeOut`. No piecewise-linear ramps, so no visible
    // kinks when a user zooms slowly past a threshold.
    const { fadeInPx, peakLoPx, peakHiPx, fadeOutPx } = this.settings.shell;
    const visible: { shell: ClusterShellInput; alpha: number }[] = [];
    for (const s of shells) {
      const dx = s.centre.x - cam.x;
      const dy = s.centre.y - cam.y;
      const dz = s.centre.z - cam.z;
      const dist = Math.sqrt(dx * dx + dy * dy + dz * dz) || 1;
      // Skip shells whose interior contains the camera. Once the
      // camera crosses the shell boundary the sphere wraps the
      // viewport from the inside, which reads as an opaque gray
      // ceiling rather than a useful outline. Leaving it off frees
      // the user to see the actual cluster contents as they zoom
      // deeper.
      if (dist < s.radius * 1.02) {
        continue;
      }
      const px = (s.radius / dist) * pxScale;
      const alphaIn = smoothstep(fadeInPx, peakLoPx, px);
      const alphaOut = 1 - smoothstep(peakHiPx, fadeOutPx, px);
      const alpha = Math.min(alphaIn, alphaOut);
      if (alpha <= 0.01) {
        continue;
      }
      visible.push({ shell: s, alpha });
    }
    this.ensureShellCapacity(visible.length);
    const mesh = this.shellMesh;
    const color = new Color();
    // Ring geometry is fixed inner/outer radii. When a shell is close
    // to the camera its projected band becomes many pixels thick,
    // reading as a gray disc rather than an outline. Compensate by
    // fading alpha inversely with the projected band thickness: thin
    // rings stay fully opaque, thick rings become a faint wash.
    const ringNormal = new Vector3(0, 0, 1);
    const toCam = new Vector3();
    const { ringWidthFrac, targetBandPx } = this.settings.shell;
    for (let i = 0; i < visible.length; i++) {
      const { shell: s, alpha } = visible[i]!;
      this.dummyPos.set(s.centre.x, s.centre.y, s.centre.z);
      toCam.set(cam.x - s.centre.x, cam.y - s.centre.y, cam.z - s.centre.z);
      const dist = Math.max(1e-3, toCam.length());
      toCam.multiplyScalar(1 / dist);
      this.dummyQuat.setFromUnitVectors(ringNormal, toCam);
      this.dummyScale.setScalar(s.radius);
      this.dummyMatrix.compose(this.dummyPos, this.dummyQuat, this.dummyScale);
      mesh.setMatrixAt(i, this.dummyMatrix);
      // Projected ring-band thickness (in pixels).
      const bandPx = (ringWidthFrac * s.radius * pxScale) / dist;
      // Keep visual line thickness ≈ targetBandPx by dimming alpha
      // when the ring would otherwise paint a thick band.
      const widthAttenuation =
        bandPx <= targetBandPx ? 1 : targetBandPx / bandPx;
      const tint =
        (0.4 + 0.15 * Math.min(4, s.depth)) * alpha * widthAttenuation;
      color.copy(this.bgColor).lerp(this.fgColor, tint);
      mesh.setColorAt(i, color);
    }
    mesh.count = visible.length;
    mesh.instanceMatrix.needsUpdate = true;
    if (mesh.instanceColor) {
      mesh.instanceColor.needsUpdate = true;
    }
  }

  private ensureShellCapacity(count: number): void {
    if (this.shellMesh.instanceMatrix.count >= count) {
      this.shellMesh.count = count;
      return;
    }
    const geom = this.shellMesh.geometry;
    const mat = this.shellMesh.material as MeshBasicMaterial;
    this.scene.remove(this.shellMesh);
    this.shellMesh = new InstancedMesh(geom, mat, growCapacity(count));
    this.shellMesh.frustumCulled = false;
    this.shellMesh.renderOrder = -1;
    this.shellMesh.count = count;
    this.scene.add(this.shellMesh);
  }

  private rebuildNodes(args: {
    readonly visibleNodes: readonly ViewNode[];
    readonly selection: SelectionState;
    readonly hoverNode: ViewNode | null;
    readonly hoverNeighbors: ReadonlySet<string> | null;
    readonly degreeMap: ReadonlyMap<string, number>;
    readonly degreeCap: number;
    readonly nodeDepth?: ReadonlyMap<string, number>;
    readonly clusterShells: readonly ClusterShellInput[];
  }): void {
    const {
      visibleNodes,
      selection,
      hoverNode,
      hoverNeighbors,
      degreeMap,
      degreeCap,
      nodeDepth,
      clusterShells,
    } = args;
    this.ensureNodeCapacity(visibleNodes.length);
    this.visibleNodesByInstance = visibleNodes;
    const mesh = this.nodeMesh;
    const color = new Color();
    const cam = this.camera.position;
    const pxScale = this.pixelScale();
    // Nodes whose projected screen radius is below this many pixels
    // are hidden entirely; between `cullRadius` and `fadeRadius`
    // they smoothstep-fade so nothing pops in or out. Because
    // `screenRadius = pixelTarget × (1..hubScale)` for every node,
    // low-degree nodes only hit the cull path when the settings
    // explicitly squeeze `pixelTarget` below `cullRadius`.
    const MIN_SCREEN_RADIUS = this.settings.node.cullRadius;
    const FADE_SCREEN_RADIUS = this.settings.node.fadeRadius;

    // Depth-aware LOD (C¹ continuous): deep-in-cluster nodes fade
    // smoothly between `interiorFadeLoPx` and `interiorFadeHiPx` of
    // their enclosing cluster's projected screen radius. Below lo
    // they're hidden (the cluster is too small for internal detail
    // to read); above hi they're fully visible. Top-level nodes
    // (depth ≤ 1) are always at full alpha so the overview has
    // landmarks. No hard cuts — slow zoom never pops.
    const { interiorFadeLoPx, interiorFadeHiPx } = this.settings.node;
    // Find the deepest shell enclosing a node, project its radius to
    // pixels. Called once per node per frame — no caching needed.
    const interiorPxFor = (node: ViewNode): number => {
      let chosen: ClusterShellInput | null = null;
      let bestDepth = -1;
      for (const s of clusterShells) {
        if (s.depth <= bestDepth) {
          continue;
        }
        const dx = node.x - s.centre.x;
        const dy = node.y - s.centre.y;
        const dz = node.z - s.centre.z;
        if (dx * dx + dy * dy + dz * dz <= s.radius * s.radius) {
          chosen = s;
          bestDepth = s.depth;
        }
      }
      if (!chosen) {
        return Infinity;
      }
      const dxc = chosen.centre.x - cam.x;
      const dyc = chosen.centre.y - cam.y;
      const dzc = chosen.centre.z - cam.z;
      const dist = Math.max(1, Math.sqrt(dxc * dxc + dyc * dyc + dzc * dzc));
      return (chosen.radius * pxScale) / dist;
    };

    for (let i = 0; i < visibleNodes.length; i++) {
      const node = visibleNodes[i]!;
      const degree = degreeMap.get(node.id) ?? 0;
      const importance = nodeImportance({ node, degree, degreeCap });
      // Obsidian-style sizing: leaves are dots, hubs stand out. We
      // pick a *target pixel radius* then back-solve the world
      // radius, so nodes stay legible at any zoom.
      const degreeFrac = Math.sqrt(
        Math.min(1, degree / Math.max(1, degreeCap)),
      );
      const { pixelTarget, hubScale } = this.settings.node;
      const targetPx = pixelTarget * (1 + (hubScale - 1) * degreeFrac);

      const dx = node.x - cam.x;
      const dy = node.y - cam.y;
      const dz = node.z - cam.z;
      const distance = Math.sqrt(dx * dx + dy * dy + dz * dz) || 1;
      // worldRadius chosen so screen-projection = targetPx exactly.
      const worldRadius = (targetPx * distance) / pxScale;
      const screenRadius = targetPx;

      const interactive =
        selection.selected.has(node.id) ||
        hoverNode?.id === node.id ||
        selection.focusNeighbors.has(node.id);

      // Interior LOD fade (smoothstep). Nodes at depth 1 stay at
      // full alpha always; deeper nodes fade in proportionally to
      // their enclosing cluster's projected size. Interactive nodes
      // bypass the LOD so the user never loses what they're using.
      const depth = nodeDepth?.get(node.id) ?? 1;
      const clusterPx = depth > 1 ? interiorPxFor(node) : Infinity;
      const interiorAlpha =
        depth <= 1
          ? 1
          : smoothstep(interiorFadeLoPx, interiorFadeHiPx, clusterPx);
      const visible =
        interactive ||
        (screenRadius >= MIN_SCREEN_RADIUS && interiorAlpha > 0.02);
      if (!visible) {
        this.dummyScale.setScalar(0);
        this.dummyPos.set(node.x, node.y, node.z);
        this.dummyQuat.identity();
        this.dummyMatrix.compose(
          this.dummyPos,
          this.dummyQuat,
          this.dummyScale,
        );
        mesh.setMatrixAt(i, this.dummyMatrix);
        color.copy(this.bgColor);
        mesh.setColorAt(i, color);
        continue;
      }

      // Smoothstep between `cullRadius` and `fadeRadius` so small
      // nodes recede with a C¹-continuous alpha — no pop even if
      // the user zooms very slowly past the threshold.
      const fade = smoothstep(
        MIN_SCREEN_RADIUS,
        Math.max(MIN_SCREEN_RADIUS + 0.01, FADE_SCREEN_RADIUS),
        screenRadius,
      );

      this.dummyPos.set(node.x, node.y, node.z);
      this.dummyQuat.identity();
      this.dummyScale.setScalar(worldRadius);
      this.dummyMatrix.compose(this.dummyPos, this.dummyQuat, this.dummyScale);
      color.copy(this.bgColor).lerp(this.fgColor, 0.35 + 0.65 * importance);
      if (selection.selected.has(node.id)) {
        color.lerp(this.selectionColor, 0.85);
      } else {
        if (hoverNode?.id === node.id) {
          color.lerp(this.highlightColor, 0.7);
        }
      }
      if (selection.focusCenter && !selection.focusNeighbors.has(node.id)) {
        color.lerp(this.bgColor, 0.75);
      }
      // Obsidian-style hover spotlight: when hovering, anyone outside
      // the 1-hop neighbourhood recedes into the background. Applies
      // only if the user isn't already in a selection focus mode.
      if (
        hoverNeighbors &&
        !selection.focusCenter &&
        !hoverNeighbors.has(node.id)
      ) {
        color.lerp(this.bgColor, 0.7);
      }
      if (!interactive && fade < 1) {
        color.lerp(this.bgColor, 1 - fade);
      }
      // Apply the smoothstep interior-LOD fade as a final alpha-like
      // blend toward background. At interiorAlpha=1 the colour is
      // unchanged; at 0 the node blends completely into the bg.
      if (!interactive && interiorAlpha < 1) {
        color.lerp(this.bgColor, 1 - interiorAlpha);
      }
      mesh.setColorAt(i, color);
    }
    mesh.count = visibleNodes.length;
    mesh.instanceMatrix.needsUpdate = true;
    if (mesh.instanceColor) {
      mesh.instanceColor.needsUpdate = true;
    }
  }

  /** Pixel scale factor for world-to-screen radius conversion. */
  private pixelScale(): number {
    const halfFov = (this.camera.fov * Math.PI) / 360;
    return this.height / (2 * Math.tan(halfFov));
  }

  private rebuildEdges(args: {
    readonly visibleEdges: readonly ViewEdge[];
    readonly selection: SelectionState;
    readonly hoverNeighbors: ReadonlySet<string> | null;
    readonly edgeContext: EdgeImportanceContext;
    readonly directednessContext: DirectednessContext;
    readonly bundleHubs: ReadonlyMap<string, Vec3Hub>;
  }): void {
    const {
      visibleEdges,
      selection,
      hoverNeighbors,
      edgeContext,
      directednessContext,
      bundleHubs,
    } = args;
    const n = visibleEdges.length;
    // Each edge is rendered as an N-segment polyline sampled along a
    // smooth quadratic bezier:
    //   A  →  C  →  B
    // where:
    //   A, B       — source & target node positions
    //   C          — bundle control point (see below)
    // For intra-cluster edges C = midpoint(A, B) so the bezier
    // degenerates to a straight line — no visual distortion for
    // short local edges. For cross-cluster edges C = midpoint of the
    // two cluster hubs pulled partially toward the scene centre,
    // which makes every edge between clusters (X, Y) trace the same
    // smooth arc regardless of which exact nodes they connect —
    // parallel edges collapse onto a single visual corridor without
    // any sharp kinks.
    const SEGS = this.settings.edge.bezierSegments;
    const positions = new Float32Array(n * SEGS * 6);
    // One bezier control point per unordered cluster pair — every
    // edge between cluster X and Y shares this point, producing a
    // single visible corridor rather than a fan of separate arcs.
    const corridorCache = new Map<Vec3Hub, Map<Vec3Hub, Vec3Hub>>();
    const colors = new Float32Array(n * SEGS * 6);
    const color = new Color();

    // Bundling strength — read from RenderSettings so UI can expose
    // it as a slider. 0 = straight line; 1 = control point sits
    // exactly on the cluster-hub midpoint.
    const BUNDLE = this.settings.edge.bundleStrength;

    // Edge length distribution — used to classify edges as "short"
    // (near cluster-internal) vs "long" (cross-cluster). Long edges
    // get faded dramatically so the constellation reads as local
    // neighbourhoods rather than a tangle of intercluster wires.
    // We compute this from the *current* edge set so a small subset
    // of very long edges doesn't pull the threshold away.
    let shortThreshold = 0;
    let longThreshold = 0;
    const { shortQuantile, longQuantile, longEdgeFloor } = this.settings.edge;
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

    // Reserve arrow capacity up to the edge count (the upper bound).
    // `arrows.count` is set from the actual `arrowIndex` at the end
    // so unused slots are not drawn — no pre-pass counting needed.
    this.ensureArrowCapacity(n);
    const arrows = this.arrowMesh;
    let arrowIndex = 0;

    const cam = this.camera.position;
    const camTarget = this.controls.target;
    const camFitDist = cam.distanceTo(camTarget) || 1;
    // Cull edges whose midpoint is far from the camera's focus
    // point when zoomed in. Prevents the "hundreds of far edges
    // bleeding through into a near-zoom view" saturation.
    // Cull radius grows with orbit distance so at overview no edge
    // is culled; at close zoom only the ones touching the visible
    // cluster survive.
    const cullRadius = camFitDist * 2.5;
    const cullRadiusSq = cullRadius * cullRadius;
    const writeSegment = (args: {
      readonly edgeIdx: number;
      readonly segIdx: number;
      readonly from: {
        readonly x: number;
        readonly y: number;
        readonly z: number;
      };
      readonly to: {
        readonly x: number;
        readonly y: number;
        readonly z: number;
      };
      readonly color: {
        readonly r: number;
        readonly g: number;
        readonly b: number;
      };
    }) => {
      const { edgeIdx, segIdx, from, to, color: c } = args;
      const base = (edgeIdx * SEGS + segIdx) * 6;
      positions[base + 0] = from.x;
      positions[base + 1] = from.y;
      positions[base + 2] = from.z;
      positions[base + 3] = to.x;
      positions[base + 4] = to.y;
      positions[base + 5] = to.z;
      colors[base + 0] = c.r;
      colors[base + 1] = c.g;
      colors[base + 2] = c.b;
      colors[base + 3] = c.r;
      colors[base + 4] = c.g;
      colors[base + 5] = c.b;
    };
    const writeHidden = (edgeIdx: number) => {
      for (let s = 0; s < SEGS; s++) {
        const base = (edgeIdx * SEGS + s) * 6;
        for (let j = 0; j < 6; j++) {
          positions[base + j] = 0;
        }
        for (let j = 0; j < 6; j++) {
          colors[base + j] = 0;
        }
      }
    };
    for (let i = 0; i < n; i++) {
      const edge = visibleEdges[i]!;
      const ax = edge.source.x;
      const ay = edge.source.y;
      const az = edge.source.z;
      const bx = edge.target.x;
      const by = edge.target.y;
      const bz = edge.target.z;

      // Edge midpoint-to-camera-target distance. Skip edges far
      // outside the current camera focus.
      const mxT = (ax + bx) * 0.5 - camTarget.x;
      const myT = (ay + by) * 0.5 - camTarget.y;
      const mzT = (az + bz) * 0.5 - camTarget.z;
      const midDsq = mxT * mxT + myT * myT + mzT * mzT;
      if (midDsq > cullRadiusSq) {
        writeHidden(i);
        continue;
      }

      const dx = bx - ax;
      const dy = by - ay;
      const dz = bz - az;
      const length = Math.sqrt(dx * dx + dy * dy + dz * dz);
      // Proximity factor: 1.0 for short (near) edges, 0.0 for the
      // longest quintile. Smooth linear fade between the two
      // thresholds so there's no hard cutoff.
      const proximity = lengthProximity(length, shortThreshold, longThreshold);

      // Edge-to-camera distance (to the midpoint) relative to
      // camera's current orbit distance. Very-near edges get a
      // mild tint reduction so overlapping dense edges don't
      // saturate into solid beams, but we keep the fade gentle so
      // edges stay visible at every zoom level.
      const mx = (ax + bx) * 0.5 - cam.x;
      const my = (ay + by) * 0.5 - cam.y;
      const mz = (az + bz) * 0.5 - cam.z;
      const edgeCamDist = Math.sqrt(mx * mx + my * my + mz * mz) || 1;
      const relDist = edgeCamDist / camFitDist;
      // Clamp into [0.7, 1.0] — at worst, edges are 70% of their
      // overview intensity, never invisible.
      const nearFade = Math.min(1, Math.max(0.7, relDist));

      const importance = edgeImportance(edge, edgeContext);
      // Base tint is importance-driven. Proximity scales *down* the
      // tint so long edges stay visibly present but don't compete
      // with the local cluster detail; nearFade suppresses saturation
      // for edges sitting right in front of the camera.
      // Short edges (proximity → 1) keep full tint; long edges fall
      // to a `longEdgeFloor` lower bound so the relationship is still
      // visible but doesn't compete with local cluster detail.
      const lengthWeight = longEdgeFloor + (1 - longEdgeFloor) * proximity;
      const tint = (0.12 + 0.72 * importance) * lengthWeight * nearFade;
      color.copy(this.bgColor).lerp(this.fgColor, tint);
      const isFocused =
        selection.focusNeighbors.has(edge.sourceId) &&
        selection.focusNeighbors.has(edge.targetId);
      if (selection.focusCenter && !isFocused) {
        color.lerp(this.bgColor, 0.8);
      }
      // Hover spotlight: edges fully in the 1-hop neighbourhood stay
      // lit, edges touching only the hovered node glow brightly, all
      // other edges fade.
      if (hoverNeighbors && !selection.focusCenter) {
        const srcIn = hoverNeighbors.has(edge.sourceId);
        const tgtIn = hoverNeighbors.has(edge.targetId);
        if (!(srcIn && tgtIn)) {
          color.lerp(this.bgColor, 0.75);
        }
      }
      // Pick the bezier control point.
      //   - Intra-cluster edge:  midpoint(A, B) — degenerates to a
      //                          straight line, no bending.
      //   - Cross-cluster edge:  the control point shared by every
      //                          edge going between the same ordered
      //                          cluster pair — i.e. all edges from
      //                          cluster X to cluster Y trace through
      //                          the identical point, collapsing them
      //                          onto a single visual corridor.
      const srcHub = bundleHubs.get(edge.sourceId);
      const tgtHub = bundleHubs.get(edge.targetId);
      const sameCluster = !!srcHub && !!tgtHub && srcHub === tgtHub;
      let cx: number;
      let cy: number;
      let cz: number;
      if (sameCluster || !srcHub || !tgtHub) {
        // No bending — short edges stay short and clear.
        cx = (ax + bx) * 0.5;
        cy = (ay + by) * 0.5;
        cz = (az + bz) * 0.5;
      } else {
        // Shared corridor midpoint for every (srcHub, tgtHub) pair.
        // We mix it with the straight-line edge midpoint by `BUNDLE`
        // strength: BUNDLE=1 fully collapses the pair onto a single
        // arc (maximum bundling), lower values let individual edges
        // spread slightly — useful when zoomed into a cluster and
        // the shared corridor would otherwise overwrite node detail.
        const corridor = getCorridorControl(corridorCache, srcHub, tgtHub);
        const smx = (ax + bx) * 0.5;
        const smy = (ay + by) * 0.5;
        const smz = (az + bz) * 0.5;
        cx = smx + (corridor.x - smx) * BUNDLE;
        cy = smy + (corridor.y - smy) * BUNDLE;
        cz = smz + (corridor.z - smz) * BUNDLE;
      }

      const r = color.r;
      const g = color.g;
      const b = color.b;
      // Sample the quadratic bezier at SEGS+1 points and emit
      // SEGS connected line segments. Using a bezier instead of
      // a piecewise-linear through-the-hubs path eliminates the
      // visible kinks that made edges look like く shapes.
      let prevX = ax;
      let prevY = ay;
      let prevZ = az;
      for (let s = 0; s < SEGS; s++) {
        const t = (s + 1) / SEGS;
        const u = 1 - t;
        // Quadratic bezier: (1-t)^2·A + 2(1-t)t·C + t^2·B
        const nx = u * u * ax + 2 * u * t * cx + t * t * bx;
        const ny = u * u * ay + 2 * u * t * cy + t * t * by;
        const nz = u * u * az + 2 * u * t * cz + t * t * bz;
        writeSegment({
          edgeIdx: i,
          segIdx: s,
          from: { x: prevX, y: prevY, z: prevZ },
          to: { x: nx, y: ny, z: nz },
          color: { r, g, b },
        });
        prevX = nx;
        prevY = ny;
        prevZ = nz;
      }

      const directedness = edgeDirectedness(edge.kind, directednessContext);
      // Hide arrows on very-long edges too — a long faded edge with
      // a crisp arrowhead reads as two disconnected floating marks.
      if (directedness >= 0.35 && proximity > 0.2) {
        this.placeArrow({
          index: arrowIndex,
          edge,
          importance,
          directedness,
          color,
        });
        arrowIndex++;
      }
    }

    const geom = this.edgeLines.geometry;
    geom.setPositions(positions);
    geom.setColors(colors);
    geom.computeBoundingSphere();

    arrows.count = arrowIndex;
    arrows.instanceMatrix.needsUpdate = true;
    if (arrows.instanceColor) {
      arrows.instanceColor.needsUpdate = true;
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
    const length = this.arrowDir.length();
    if (length < 1e-6) {
      this.dummyMatrix.identity();
      this.arrowMesh.setMatrixAt(index, this.dummyMatrix);
      return;
    }
    this.arrowDir.multiplyScalar(1 / length);

    // Arrow size is *screen-space constant*: a small cone roughly
    // the same pixel size as a leaf node at any zoom. This keeps
    // arrows as visual glyphs (not decorations that grow with edge
    // length). Target pixel = 2× leaf node target, tapered by
    // importance so critical edges get a touch more visibility.
    const cam = this.camera.position;
    const dx = target.x - cam.x;
    const dy = target.y - cam.y;
    const dz = target.z - cam.z;
    const targetDist = Math.sqrt(dx * dx + dy * dy + dz * dz) || 1;
    const pxScale = this.pixelScale();
    const arrowPx =
      this.settings.node.pixelTarget * 1.6 * (0.7 + 0.3 * importance);
    const worldSize = (arrowPx * targetDist) / pxScale;

    // Back-off so the cone's base sits just outside the target node
    // (which itself is sized by NODE_TARGET_PX in world units at the
    // target's distance). Cone length = worldSize × 2 so tip extends
    // past the base.
    const nodeWorld = (this.settings.node.pixelTarget * targetDist) / pxScale;
    const backOff = nodeWorld + worldSize * 0.5;
    const baseX = target.x - this.arrowDir.x * backOff;
    const baseY = target.y - this.arrowDir.y * backOff;
    const baseZ = target.z - this.arrowDir.z * backOff;

    this.dummyQuat.setFromUnitVectors(this.arrowUp, this.arrowDir);
    this.dummyScale.set(worldSize * 0.6, worldSize, worldSize * 0.6);
    this.dummyPos.set(baseX, baseY, baseZ);
    this.dummyMatrix.compose(this.dummyPos, this.dummyQuat, this.dummyScale);
    this.arrowMesh.setMatrixAt(index, this.dummyMatrix);

    // Colour: follow the edge colour but scale towards fg by
    // directedness so dashed/weak relationships get visibly lighter.
    const arrowColor = color.clone().lerp(this.fgColor, 0.2 * directedness);
    this.arrowMesh.setColorAt(index, arrowColor);
  }
}

// ─── Helpers ──────────────────────────────────────────────────────

function filterVisibleNodes(
  graph: ViewGraph,
  filter: FilterResult,
): ViewNode[] {
  return graph.nodes.filter((n) => filter.visibleNodes.has(n.id));
}

function filterVisibleEdges(
  graph: ViewGraph,
  filter: FilterResult,
): ViewEdge[] {
  const out: ViewEdge[] = [];
  graph.edges.forEach((edge, index) => {
    if (filter.visibleEdges.has(index)) {
      out.push(edge);
    }
  });
  return out;
}

function computeDegreeMap(
  graph: ViewGraph,
  filter: FilterResult,
): Map<string, number> {
  const count = new Map<string, number>();
  graph.edges.forEach((edge, index) => {
    if (!filter.visibleEdges.has(index)) {
      return;
    }
    count.set(edge.sourceId, (count.get(edge.sourceId) ?? 0) + 1);
    count.set(edge.targetId, (count.get(edge.targetId) ?? 0) + 1);
  });
  return count;
}

/** Ids of the hovered node + every node it shares an edge with.
 *  Used to highlight an Obsidian-style "1-hop neighbourhood" on
 *  hover. Includes the centre itself. */
function collectNeighbourIds(
  graph: ViewGraph,
  centre: string,
): ReadonlySet<string> {
  const out = new Set<string>([centre]);
  for (const edge of graph.edges) {
    const other = otherEdgeEndpoint(edge, centre);
    if (other !== null) {
      out.add(other);
    }
  }
  return out;
}

function otherEdgeEndpoint(
  edge: { readonly sourceId: string; readonly targetId: string },
  nodeId: string,
): string | null {
  if (edge.sourceId === nodeId) {
    return edge.targetId;
  }
  if (edge.targetId === nodeId) {
    return edge.sourceId;
  }
  return null;
}

/** Smooth 1→0 ramp that classifies edges by length. Shorter than
 *  `shortThreshold` → 1 (fully local). Longer than `longThreshold` →
 *  0 (cross-scene). Linear fade between. Used for arrow culling and
 *  edge tinting — both want to keep local structure readable. */
function lengthProximity(
  length: number,
  shortThreshold: number,
  longThreshold: number,
): number {
  if (length <= shortThreshold) {
    return 1;
  }
  if (length >= longThreshold) {
    return 0;
  }
  return 1 - (length - shortThreshold) / (longThreshold - shortThreshold);
}

function easeOutCubic(t: number): number {
  const u = 1 - t;
  return 1 - u * u * u;
}

type Vec3Hub = { readonly x: number; readonly y: number; readonly z: number };

/** Return a single shared bezier control point for the (srcHub, tgtHub)
 *  corridor. Memoised in a nested map keyed by object identity so
 *  every edge between the same two clusters picks up the exact same
 *  control point — the hallmark of a real bundling pass.
 *
 *  The control point sits at `midpoint(srcHub, tgtHub) × BUNDLE +
 *  midpoint(A, B) × (1-BUNDLE)`. Since A, B vary per edge we can't
 *  actually fold the A,B term into the cache — so instead we cache
 *  the `hub-midpoint` vector only, and let the caller combine it
 *  with `(1-BUNDLE)·midpoint(A,B)` at draw time. But for strong
 *  bundling (BUNDLE≈0.7+) the hub term dominates and edges visibly
 *  bundle even without a full cache hit. Storing the hub midpoint
 *  here lets the hot loop skip the (srcHub.x+tgtHub.x)/2 work per
 *  edge. */
function getCorridorControl(
  cache: Map<Vec3Hub, Map<Vec3Hub, Vec3Hub>>,
  srcHub: Vec3Hub,
  tgtHub: Vec3Hub,
): Vec3Hub {
  let row = cache.get(srcHub);
  if (!row) {
    row = new Map();
    cache.set(srcHub, row);
  }
  const cached = row.get(tgtHub);
  if (cached) {
    return cached;
  }
  const mid: Vec3Hub = {
    x: (srcHub.x + tgtHub.x) * 0.5,
    y: (srcHub.y + tgtHub.y) * 0.5,
    z: (srcHub.z + tgtHub.z) * 0.5,
  };
  row.set(tgtHub, mid);
  return mid;
}

/** For each node, pick the *shallowest* (top-level) cluster shell it
 *  belongs to and return that shell's centre as the bundling hub.
 *  Shallowest — not deepest — because bundling by top-level cluster
 *  produces the strongest visual corridors; every edge between two
 *  top-level folders passes through the same pair of hubs no matter
 *  how deeply nested the endpoints are.
 *
 *  A node "belongs to" a shell iff the shell's id is an ancestor of
 *  the node's file path (or matches the node id for external nodes).
 *  We iterate shells ordered by depth ascending so the first match
 *  is the shallowest. */
function buildBundleHubs(args: {
  readonly shells: readonly ClusterShellInput[];
  readonly nodes: readonly ViewNode[];
}): Map<string, Vec3Hub> {
  const { shells, nodes } = args;
  if (shells.length === 0) {
    return new Map();
  }
  // Shells at depth=1 only — the top-level galaxies.
  const tops = shells.filter((s) => s.depth === 1);
  if (tops.length === 0) {
    return new Map();
  }
  // Sort top shells by path length ascending so `startsWith` falls
  // through to the shortest matching prefix.
  const topsSorted = [...tops].sort((a, b) => a.path.length - b.path.length);
  const out = new Map<string, Vec3Hub>();
  for (const node of nodes) {
    const key = node.file && node.file.length > 0 ? node.file : node.id;
    for (const shell of topsSorted) {
      // `${path}/` guards against false prefix matches (e.g. path "a"
      // matching id "ab/..."). Exact equality `key === shell.path`
      // is impossible — shells are directory prefixes, nodes are
      // always a file/symbol below them.
      if (key.startsWith(`${shell.path}/`)) {
        out.set(node.id, shell.centre);
        break;
      }
    }
  }
  return out;
}

function clamp(value: number, min: number, max: number): number {
  if (value < min) {
    return min;
  }
  if (value > max) {
    return max;
  }
  return value;
}

/** Standard smoothstep — 3t² − 2t³. C¹-continuous ramp from 0 at
 *  `edge0` to 1 at `edge1`, zero-slope at both ends so the fade has
 *  no visible kink. Values outside the range are clamped. */
function smoothstep(edge0: number, edge1: number, value: number): number {
  if (edge1 === edge0) {
    return value < edge0 ? 0 : 1;
  }
  const t = clamp((value - edge0) / (edge1 - edge0), 0, 1);
  return t * t * (3 - 2 * t);
}

function growCapacity(n: number): number {
  // Round up to the next power-of-two slot (min 64) to amortise
  // reallocations across incremental graph updates.
  let cap = 64;
  while (cap < n) {
    cap *= 2;
  }
  return cap;
}

/**
 * Continuous [0, 1] value that fades static labels in between the
 * overview zoom and the detail zoom levels. Mirrors the canvas2d
 * renderer's `detailFactor` so both backends feel the same.
 */
function detailFactorFromZoom(zoom: number): number {
  const edge0 = 0.9;
  const edge1 = 1.4;
  if (zoom <= edge0) {
    return 0;
  }
  if (zoom >= edge1) {
    return 1;
  }
  const t = (zoom - edge0) / (edge1 - edge0);
  return t * t * (3 - 2 * t);
}
