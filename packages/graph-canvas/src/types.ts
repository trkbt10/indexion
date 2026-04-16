/**
 * @file Core type definitions for the graph-canvas viewer.
 *
 * ViewGraph is the unified internal model that all subsystems operate on.
 * Force simulation mutates position/velocity fields directly for performance.
 */

import type { CodeGraph } from "@indexion/api-client";

// --- Geometry ---

export type Vec2 = { x: number; y: number };

// --- Graph Model ---

/**
 * A node in the view graph. Identity fields are readonly; simulation
 * fields (x, y, vx, vy, pinned) are mutable for in-place update.
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
  vx: number;
  vy: number;
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

// --- Simulation Config ---

export type ForceConfig = {
  /** Coulomb repulsion strength. Default: 300 */
  readonly repulsionStrength: number;
  /** Hooke spring stiffness. Default: 0.02 */
  readonly springStiffness: number;
  /** Spring rest length in world units. Default: 80 */
  readonly springRestLength: number;
  /** Centering force strength. Default: 0.01 */
  readonly centerStrength: number;
  /** Velocity damping per tick (0..1). Default: 0.6 */
  readonly velocityDecay: number;
  /** Alpha decay per tick. Default: 0.0228 (~300 ticks to alphaMin) */
  readonly alphaDecay: number;
  /** Convergence threshold. Default: 0.001 */
  readonly alphaMin: number;
  /** Barnes-Hut approximation parameter. Default: 0.9 */
  readonly barnesHutTheta: number;
  /** Node count threshold for Barnes-Hut activation. Default: 200 */
  readonly barnesHutThreshold: number;
};

export const DEFAULT_FORCE_CONFIG: ForceConfig = {
  repulsionStrength: 300,
  springStiffness: 0.02,
  springRestLength: 80,
  centerStrength: 0.01,
  velocityDecay: 0.6,
  alphaDecay: 0.0228,
  alphaMin: 0.001,
  barnesHutTheta: 0.9,
  barnesHutThreshold: 200,
};

// --- Camera ---

export type Camera = {
  x: number;
  y: number;
  scale: number;
  readonly minScale: number;
  readonly maxScale: number;
};

export const DEFAULT_CAMERA: Readonly<Camera> = {
  x: 0,
  y: 0,
  scale: 1,
  minScale: 0.05,
  maxScale: 5,
};

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

// --- Component API ---

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
  readonly className?: string;
  readonly simulationConfig?: Partial<ForceConfig>;
};

export type GraphCanvasHandle = {
  fitToView(padding?: number): void;
  selectNode(id: string): void;
  clearSelection(): void;
  resetSimulation(): void;
  getNodePosition(id: string): Vec2 | null;
};
