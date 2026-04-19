/**
 * @file Core type definitions for the graph-canvas viewer.
 *
 * ViewGraph is the unified internal model that all subsystems operate on.
 * Force simulation mutates position/velocity fields directly for performance.
 */

import type { CodeGraph } from "@indexion/api-client";

// --- Geometry ---

export type Vec2 = { x: number; y: number };

/** 3D point. Single source of truth for "a position in world space" —
 *  shared by layout output, renderer input, and clustering helpers.
 *  Readonly so layout-emitted positions can't be mutated downstream
 *  (the only mutation site is `writeNode` inside the layout module). */
export type Vec3 = {
  readonly x: number;
  readonly y: number;
  readonly z: number;
};

/** 2D rectangle in world coordinates. Used by the squarified treemap
 *  and the cluster-fill renderer. */
export type Rect = {
  readonly x: number;
  readonly y: number;
  readonly w: number;
  readonly h: number;
};

/** A cluster outline emitted by the hierarchical layout, consumed by
 *  the renderer for shell rings (ring inscribed in `rect`), interior-
 *  LOD detection (`centre`+`radius`), bundling hubs (`centre`), and
 *  the cluster-fill density patch (`rect`+`leafCount`). Single source
 *  of truth — every layer reads the same shape. */
export type ClusterShell = {
  readonly path: string;
  /** Inscribed-circle centre of `rect`. */
  readonly centre: Vec3;
  /** Inscribed-circle radius of `rect` (= min(w, h) / 2 of the inner,
   *  post-padding cell rectangle). */
  readonly radius: number;
  /** 1 = top-level cluster, increases per nesting level. */
  readonly depth: number;
  /** Cell rectangle this shell occupies. For "treemap" shells the
   *  rect is a tight, non-overlapping cell from the squarified pack
   *  and is used for fill + border drawing. For "centroid" shells
   *  (Volume / K-means) the rect is just an axis-aligned bounding
   *  square around the cluster's members — overlap with neighbours
   *  is normal, so the border layer skips it and only the fill /
   *  label draw against `centre` + `radius`. */
  readonly rect: Rect;
  /** Distinguishes treemap-style cells (Hierarchy) from centroid-
   *  derived bounding squares (Volume / K-means). The renderer keys
   *  off this so layers that assume non-overlapping rects (the
   *  border layer) don't draw a chaotic web of crossed boxes when
   *  the layout is centroid-based. */
  readonly kind: "treemap" | "centroid";
  /** True iff this cluster has no sub-clusters. The cluster-fill
   *  layer paints only leaf clusters; nested clusters are represented
   *  by their children's fills. */
  readonly isLeaf: boolean;
  /** Number of owned leaf nodes anywhere under this cluster. Drives
   *  the density-patch intensity. */
  readonly leafCount: number;
};

// --- Graph Model ---

/**
 * A node in the view graph. Identity fields are readonly; simulation
 * fields (position, velocity, pinned) are mutable for in-place update.
 *
 * The placement model is 3D. The 2D renderer projects (x,y,z) to the
 * screen using parallel projection, mapping z to size and opacity.
 * A future WebGL renderer can read the same (x,y,z) directly.
 */
export type ViewNode = {
  readonly id: string;
  readonly label: string;
  readonly kind: string;
  readonly group: string;
  readonly file: string | null;
  readonly doc: string | null;
  readonly metadata: Record<string, string>;
  x: number;
  y: number;
  z: number;
  vx: number;
  vy: number;
  vz: number;
  pinned: boolean;
};

/** Directed edge between two view nodes. */
export type ViewEdge = {
  readonly sourceId: string;
  readonly targetId: string;
  readonly kind: string;
  readonly metadata: Record<string, string>;
  source: ViewNode;
  target: ViewNode;
};

/** The unified graph model consumed by simulation, renderer, and interaction. */
export type ViewGraph = {
  readonly nodes: ViewNode[];
  readonly edges: ViewEdge[];
  readonly nodeIndex: Map<string, ViewNode>;
};

// --- GraphJSON (indexion intermediate format) ---

export type GraphJSONNode = {
  readonly id: string;
  readonly label: string;
  readonly kind: string;
  readonly file?: string;
  readonly metadata?: Record<string, string>;
};

export type GraphJSONEdge = {
  readonly from: string;
  readonly to: string;
  readonly kind: string;
  readonly metadata?: Record<string, string>;
};

export type GraphJSON = {
  readonly title: string;
  readonly nodes: readonly GraphJSONNode[];
  readonly edges: readonly GraphJSONEdge[];
  readonly metadata?: Record<string, string>;
};

/** Input type accepted by the component — either CodeGraph or GraphJSON. */
export type GraphInput = CodeGraph | GraphJSON;

// --- Theme ---

export type NodeStyle = {
  readonly radius: number;
  readonly color: string;
};

export type EdgeStyle = {
  readonly color: string;
  readonly dash: readonly number[];
  readonly arrow: boolean;
};

export type ThemeColors = {
  readonly background: string;
  readonly labelColor: string;
  readonly selectionColor: string;
  readonly highlightColor: string;
  readonly tooltipBackground: string;
  readonly tooltipBorder: string;
  readonly dimmedOpacity: number;
  readonly nodeStyles: Record<string, NodeStyle>;
  readonly edgeStyles: Record<string, EdgeStyle>;
};

// --- Selection ---

export type SelectionState = {
  readonly selected: Set<string>;
  readonly focusCenter: string | null;
  readonly focusNeighbors: Set<string>;
};

// --- Filter ---

export type FilterResult = {
  readonly visibleNodes: Set<string>;
  readonly visibleEdges: Set<number>;
  readonly highlightedNodes: Set<string>;
};

// --- Render settings (DI) ---

/**
 * Tuning knobs for every visual element. Defaults live in
 * `DEFAULT_RENDER_SETTINGS`; callers override individual fields via
 * the component's `renderSettings` prop. Tests and tooling can inject
 * a deterministic settings object; UI can expose any subset as live
 * controls without having to rewrite the renderer.
 */
export type RenderSettings = {
  readonly node: NodeRenderSettings;
  readonly shell: ShellRenderSettings;
  readonly clusterFill: ClusterFillRenderSettings;
  readonly edge: EdgeRenderSettings;
  readonly camera: CameraSettings;
  readonly layout: LayoutSettings;
};

export type NodeRenderSettings = {
  /** Target screen-space radius (pixels) for a leaf node. */
  readonly pixelTarget: number;
  /** Multiplier applied to the highest-degree node's pixel target.
   *  Leaves sit at 1×, hubs scale up continuously. */
  readonly hubScale: number;
  /** Sphere mesh tessellation (width, height segments). Higher →
   *  rounder at cost of draw time. */
  readonly sphereSegments: { readonly width: number; readonly height: number };
  /** Screen radius below which nodes fade; at `cullRadius` they are
   *  hidden entirely. Fading is smoothstep between the two. */
  readonly fadeRadius: number;
  readonly cullRadius: number;
  /** Depth-aware LOD: when a node is nested inside a cluster whose
   *  projected radius is below `interiorFadeLoPx` the node is
   *  hidden; it fades in smoothly up to `interiorFadeHiPx` so no
   *  hard pop when the camera slowly zooms. Applies to nodes at
   *  hierarchy depth > 1 — top-level landmarks are always visible. */
  readonly interiorFadeLoPx: number;
  readonly interiorFadeHiPx: number;
};

export type ClusterFillRenderSettings = {
  /** Below this projected pixel-radius for the cluster's inscribed
   *  circle, the cluster is drawn as a solid fill (the "density
   *  patch") and its individual nodes are suppressed. Above this
   *  size, the patch fades out and individual nodes fade in. The
   *  fade window is `belowPx`..`abovePx` so the transition is
   *  C¹-continuous (smoothstep) rather than a hard pop. */
  readonly belowPx: number;
  readonly abovePx: number;
  /** Maximum opacity of the patch when fully visible (cluster smaller
   *  than `belowPx`). Below 1 keeps a hint of underlying structure
   *  visible — patches are an overview cue, not opaque tiles. */
  readonly opacityPeak: number;
  /** Density-to-opacity gain. The patch alpha is
   *  `opacityPeak × min(1, log10(1 + leafCount) / densityGain)` so
   *  dense clusters look denser at the same projected size, but the
   *  log keeps the dynamic range readable. */
  readonly densityGain: number;
};

export type ShellRenderSettings = {
  /** Segment count of the ring silhouette used to outline each
   *  cluster. Higher → smoother circle. `height` is unused by the
   *  ring geometry but kept for schema symmetry. */
  readonly sphereSegments: { readonly width: number; readonly height: number };
  /** Screen-space size range (pixel radius) over which a shell
   *  smoothly appears and fades. Below `fadeInPx` shells are
   *  invisible (too small); above `fadeOutPx` the camera is nearly
   *  inside them so the outline wraps the viewport. Between these
   *  the alpha is a smoothstep — no pops. */
  readonly fadeInPx: number;
  readonly peakLoPx: number;
  readonly peakHiPx: number;
  readonly fadeOutPx: number;
  readonly opacityPeak: number;
  /** Ring thickness as a fraction of the shell's outer radius.
   *  Larger values produce a visibly thick outline; smaller a hair-
   *  line. Combined with `targetBandPx` to pick per-instance alpha
   *  so the visible line always reads as ~targetBandPx regardless
   *  of projected size. */
  readonly ringWidthFrac: number;
  /** Target on-screen band thickness (pixels) for a ring at peak
   *  visibility. When a shell's projected band exceeds this, alpha
   *  is attenuated proportionally so the line never turns into a
   *  gray wash. */
  readonly targetBandPx: number;
};

export type EdgeRenderSettings = {
  /** Line width (pixels) for every edge. */
  readonly linewidth: number;
  /** Base material opacity. Edges are then tinted per-edge by
   *  importance × proximity, so this is the ceiling. */
  readonly opacity: number;
  /** Number of straight segments used to approximate each bezier.
   *  Higher → smoother curve, more GPU work. */
  readonly bezierSegments: number;
  /** Pull strength toward the cluster-pair corridor (0 = straight
   *  line through the edge midpoint, 1 = control point sits exactly
   *  on the shared cluster-hub midpoint). */
  readonly bundleStrength: number;
  /** Edges are classified by length relative to the population.
   *  `shortQuantile` (0..1) is the quantile below which an edge is
   *  "short" (intra-cluster); `longQuantile` the one above which it
   *  is "long" (cross-scene). Edges are tinted smoothstep between
   *  those so the constellation shows local structure first. */
  readonly shortQuantile: number;
  readonly longQuantile: number;
  /** Floor on the edge's tint after long-edge attenuation. 0 lets
   *  very long edges disappear entirely; small positive values keep
   *  a ghost line so relationships never fully vanish. */
  readonly longEdgeFloor: number;
  /** Arrow length as a multiple of the edge linewidth. Pixels: arrow
   *  height = linewidth × arrowLengthMul. Tying this to linewidth
   *  (rather than to node pixel radius) keeps the arrow visually
   *  proportional to the line it terminates — so arrows look like a
   *  natural extension of the edge instead of a separate, oversized
   *  glyph. */
  readonly arrowLengthMul: number;
  /** Arrow base width as a fraction of arrow length (controls the
   *  cone's aspect ratio: smaller = thinner triangle). */
  readonly arrowAspect: number;
};

export type CameraSettings = {
  /** Perspective FOV in degrees. */
  readonly fov: number;
  /** Near / far planes. Narrow near enables deep zoom-in without
   *  clipping. */
  readonly near: number;
  readonly far: number;
  /** Orbit radius bounds. */
  readonly minDistance: number;
  readonly maxDistance: number;
  /** Multiplicative wheel-zoom strength. Each wheel tick multiplies
   *  camera→target distance by `exp(deltaY × zoomPerTick × 0.01)`. */
  readonly zoomPerTick: number;
  /** Fraction of the camera's step that the orbit target follows
   *  toward the cursor anchor. 0 keeps target stationary; higher
   *  values let the orbit centre follow what the user is zooming on. */
  readonly targetFollow: number;
};

export type LayoutSettings = {
  /** World radius of the overall scene. fitToView in the renderer
   *  measures the real payload per frame, so this only sets the
   *  working coordinate scale. */
  readonly worldRadius: number;
  /** Fractional gap kept between any two sibling bubbles. Chord
   *  between sibling centres ≥ (r_a + r_b) × (1 + siblingGap). */
  readonly siblingGap: number;
  /** Hard floor on a cluster bubble's radius as a fraction of its
   *  parent. Keeps deeply-nested singletons visible. */
  readonly minClusterFraction: number;
  /** When a cluster contains BOTH sub-clusters and owned leaves,
   *  the owned leaves occupy an inner sphere of radius
   *  `cluster × innerFraction`. */
  readonly innerFraction: number;
  /** Target per-leaf spacing in world units inside a pure-leaf
   *  cluster. Larger values spread leaves further apart so the
   *  interior is legible. */
  readonly ownedLeafFootprint: number;
  /** Intra-cluster force relaxation: spring rest length, attraction
   *  strength, and repulsion strength applied for `iterations`
   *  rounds after the initial kind-band placement. */
  readonly intraRelax: IntraRelaxSettings;
};

export type IntraRelaxSettings = {
  readonly iterations: number;
  /** Spring attraction coefficient for connected pairs. */
  readonly attraction: number;
  /** Coulomb-style repulsion coefficient between every pair. */
  readonly repulsion: number;
  /** Damping applied to accumulated displacement per iteration. */
  readonly damping: number;
  /** Maximum fraction of the cluster radius a node may travel per
   *  iteration. Keeps the system stable. */
  readonly maxStep: number;
};

/** Selection-state intent produced by pointer events. */
export type SelectionIntent =
  | {
      readonly type: "click";
      readonly node: ViewNode | null;
      readonly shift: boolean;
    }
  | { readonly type: "double-click"; readonly node: ViewNode | null }
  | { readonly type: "clear" };

/** Effect emitted alongside every selection transition. The host
 *  interprets these — the reducer itself is pure. */
export type SelectionEffect =
  | { readonly type: "none" }
  | { readonly type: "fit-to-view" }
  | { readonly type: "focus-on-node"; readonly nodeId: string };

// --- Component API ---

export type ClusteringStrategy =
  | "none"
  | "kind"
  | "directory"
  | "module"
  | "community";

/** Layout strategy identifier. See src/layout/strategies/. */
export type LayoutStrategyId = "hde-volume" | "k-means" | "hierarchy";

export type GraphCanvasProps = {
  readonly graph: GraphInput;
  readonly width?: number;
  readonly height?: number;
  readonly theme?: "dark" | "light" | "auto";
  readonly onNodeClick?: (node: ViewNode) => void;
  readonly onNodeDoubleClick?: (node: ViewNode) => void;
  readonly onSelectionChange?: (ids: ReadonlySet<string>) => void;
  readonly enabledEdgeKinds?: ReadonlySet<string> | readonly string[];
  readonly enabledNodeKinds?: ReadonlySet<string> | readonly string[];
  readonly searchQuery?: string;
  readonly hideDisconnected?: boolean;
  readonly clustering?: ClusteringStrategy;
  readonly layoutStrategy?: LayoutStrategyId;
  readonly className?: string;
  /** Optional overrides — any subset of the default render settings.
   *  Missing fields fall back to defaults via a deep merge. */
  readonly renderSettings?: DeepPartial<RenderSettings>;
};

/** Deep readonly-partial used for the `renderSettings` override. */
export type DeepPartial<T> = {
  readonly [K in keyof T]?: T[K] extends object ? DeepPartial<T[K]> : T[K];
};

export type GraphCanvasHandle = {
  fitToView(padding?: number): void;
  selectNode(id: string): void;
  clearSelection(): void;
  relayout(): void;
  getNodePosition(id: string): Vec2 | null;
};
