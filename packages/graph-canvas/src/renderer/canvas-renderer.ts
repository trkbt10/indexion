/**
 * @file Canvas 2D renderer for graph frames.
 */

import type {
  Camera,
  FilterResult,
  SelectionState,
  ThemeColors,
  Vec2,
  ViewEdge,
  ViewGraph,
  ViewNode,
} from "../types.ts";
import { getVisibleBounds, worldToScreen } from "./camera.ts";
import { getEdgeStyle, getNodeStyle } from "./styles.ts";

export type CanvasSize = {
  readonly width: number;
  readonly height: number;
};

type ParallelInfo = {
  readonly count: number;
  readonly index: number;
};

type Bounds = {
  readonly x0: number;
  readonly y0: number;
  readonly x1: number;
  readonly y1: number;
};

const LABEL_BASE_SIZE = 12;
const MAX_LABEL_CHARS = 20;
const EDGE_MARGIN = 40;
const NODE_MARGIN = 24;
const ARROW_SIZE = 8;

export function renderFrame(
  ctx: CanvasRenderingContext2D,
  graph: ViewGraph,
  camera: Camera,
  filter: FilterResult,
  selection: SelectionState,
  styles: ThemeColors,
  hoverNode: ViewNode | null,
  canvasSize: CanvasSize,
  dpr: number,
): void {
  clearCanvas(ctx, styles, canvasSize, dpr);

  const visibleBounds = getVisibleBounds(camera, canvasSize.width, canvasSize.height);
  const expandedBounds = expandBounds(visibleBounds, EDGE_MARGIN / camera.scale);
  const parallelEdges = buildParallelInfo(graph.edges);

  setWorldTransform(ctx, camera, dpr);
  drawEdges(ctx, graph, camera, filter, selection, styles, expandedBounds, parallelEdges);
  drawNodes(ctx, graph, camera, filter, selection, styles, hoverNode, expandedBounds);
  drawLabels(ctx, graph, camera, filter, selection, styles, expandedBounds);

  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  if (hoverNode && filter.visibleNodes.has(hoverNode.id)) {
    drawTooltip(ctx, hoverNode, camera, styles, canvasSize);
  }
  ctx.setTransform(1, 0, 0, 1, 0, 0);
}

function clearCanvas(
  ctx: CanvasRenderingContext2D,
  styles: ThemeColors,
  canvasSize: CanvasSize,
  dpr: number,
): void {
  ctx.setTransform(1, 0, 0, 1, 0, 0);
  ctx.clearRect(0, 0, canvasSize.width * dpr, canvasSize.height * dpr);
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  ctx.fillStyle = styles.background;
  ctx.fillRect(0, 0, canvasSize.width, canvasSize.height);
}

function setWorldTransform(ctx: CanvasRenderingContext2D, camera: Camera, dpr: number): void {
  ctx.setTransform(
    camera.scale * dpr,
    0,
    0,
    camera.scale * dpr,
    camera.x * dpr,
    camera.y * dpr,
  );
}

function drawEdges(
  ctx: CanvasRenderingContext2D,
  graph: ViewGraph,
  camera: Camera,
  filter: FilterResult,
  selection: SelectionState,
  styles: ThemeColors,
  bounds: Bounds,
  parallelEdges: ReadonlyMap<number, ParallelInfo>,
): void {
  graph.edges.forEach((edge, index) => {
    if (!filter.visibleEdges.has(index)) return;
    if (!isEdgeInBounds(edge, bounds)) return;

    const opacity = focusOpacityForEdge(edge, selection, styles);
    const edgeStyle = getEdgeStyle(edge.kind, styles);
    const parallel = parallelEdges.get(index) ?? { count: 1, index: 0 };
    const lineWidth = Math.max(1 / camera.scale, 1.3 / camera.scale);

    ctx.save();
    ctx.globalAlpha = opacity;
    ctx.strokeStyle = edgeStyle.color;
    ctx.fillStyle = edgeStyle.color;
    ctx.lineWidth = lineWidth;
    ctx.setLineDash(edgeStyle.dash.map((dash) => dash / camera.scale));
    ctx.beginPath();

    const control = drawEdgePath(ctx, edge, parallel);
    ctx.stroke();
    ctx.setLineDash([]);

    if (edgeStyle.arrow) {
      drawArrowhead(ctx, edge, control, edge.kind, camera.scale, styles);
    }
    ctx.restore();
  });
}

function drawNodes(
  ctx: CanvasRenderingContext2D,
  graph: ViewGraph,
  camera: Camera,
  filter: FilterResult,
  selection: SelectionState,
  styles: ThemeColors,
  hoverNode: ViewNode | null,
  bounds: Bounds,
): void {
  for (const node of graph.nodes) {
    if (!shouldDrawNode(node, camera, filter, bounds)) continue;

    const nodeStyle = getNodeStyle(node.kind, styles);
    const isSelected = selection.selected.has(node.id);
    const isHovered = hoverNode?.id === node.id;
    const isHighlighted = filter.highlightedNodes.has(node.id);
    const opacity = focusOpacityForNode(node, selection, styles);

    ctx.save();
    ctx.globalAlpha = opacity;
    if (isHighlighted) {
      drawGlow(ctx, node, nodeStyle.radius, styles);
    }

    ctx.fillStyle = nodeStyle.color;
    ctx.beginPath();
    ctx.arc(node.x, node.y, nodeStyle.radius, 0, Math.PI * 2);
    ctx.fill();

    if (isSelected || isHovered) {
      ctx.strokeStyle = isSelected ? styles.selectionColor : styles.highlightColor;
      ctx.lineWidth = (isSelected ? 3 : 2) / camera.scale;
      ctx.beginPath();
      ctx.arc(node.x, node.y, nodeStyle.radius + 3 / camera.scale, 0, Math.PI * 2);
      ctx.stroke();
    }
    ctx.restore();
  }
}

function drawLabels(
  ctx: CanvasRenderingContext2D,
  graph: ViewGraph,
  camera: Camera,
  filter: FilterResult,
  selection: SelectionState,
  styles: ThemeColors,
  bounds: Bounds,
): void {
  const lod = getLod(camera.scale);
  if (lod === "modules") return;

  const scaledFontSize = LABEL_BASE_SIZE * camera.scale;
  if (lod !== "module-labels" && scaledFontSize < 8) return;
  const screenFontSize = clamp(scaledFontSize, 8, 18);
  const fontSize = screenFontSize / camera.scale;

  ctx.save();
  ctx.textAlign = "center";
  ctx.textBaseline = "top";
  ctx.fillStyle = styles.labelColor;
  ctx.font = `${fontSize}px ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif`;

  for (const node of graph.nodes) {
    if (!shouldDrawNode(node, camera, filter, bounds)) continue;
    if (lod === "module-labels" && node.kind !== "module") continue;

    const nodeStyle = getNodeStyle(node.kind, styles);
    const lines = labelLines(node, lod === "metadata");
    ctx.globalAlpha = focusOpacityForNode(node, selection, styles);

    lines.forEach((line, index) => {
      ctx.fillText(
        line,
        node.x,
        node.y + nodeStyle.radius + 4 / camera.scale + index * fontSize * 1.2,
      );
    });
  }
  ctx.restore();
}

function drawTooltip(
  ctx: CanvasRenderingContext2D,
  node: ViewNode,
  camera: Camera,
  styles: ThemeColors,
  canvasSize: CanvasSize,
): void {
  const screen = worldToScreen(camera, { x: node.x, y: node.y });
  const lines = [
    node.label,
    `kind: ${node.kind}`,
    node.file ? `file: ${node.file}` : "file: n/a",
  ];
  const padding = 8;
  const lineHeight = 17;
  ctx.font = "12px ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, \"Segoe UI\", sans-serif";
  const width = Math.min(
    320,
    Math.max(...lines.map((line) => ctx.measureText(line).width)) + padding * 2,
  );
  const height = lineHeight * lines.length + padding * 2;
  const x = clamp(screen.x + 14, 4, canvasSize.width - width - 4);
  const y = clamp(screen.y + 14, 4, canvasSize.height - height - 4);

  ctx.save();
  ctx.fillStyle = tooltipBackground(styles.background);
  ctx.strokeStyle = styles.selectionColor;
  ctx.lineWidth = 1;
  roundRect(ctx, x, y, width, height, 6);
  ctx.fill();
  ctx.stroke();
  ctx.fillStyle = styles.labelColor;
  ctx.textAlign = "left";
  ctx.textBaseline = "top";
  lines.forEach((line, index) => {
    ctx.fillText(line, x + padding, y + padding + index * lineHeight, width - padding * 2);
  });
  ctx.restore();
}

function shouldDrawNode(
  node: ViewNode,
  camera: Camera,
  filter: FilterResult,
  bounds: Bounds,
): boolean {
  if (!filter.visibleNodes.has(node.id)) return false;
  if (getLod(camera.scale) === "modules" && node.kind !== "module") return false;
  return isPointInBounds(node.x, node.y, expandBounds(bounds, NODE_MARGIN / camera.scale));
}

function drawEdgePath(
  ctx: CanvasRenderingContext2D,
  edge: ViewEdge,
  parallel: ParallelInfo,
): Vec2 | null {
  const source = edge.source;
  const target = edge.target;
  if (parallel.count <= 1) {
    ctx.moveTo(source.x, source.y);
    ctx.lineTo(target.x, target.y);
    return null;
  }

  const dx = target.x - source.x;
  const dy = target.y - source.y;
  const length = Math.hypot(dx, dy) || 1;
  const nx = -dy / length;
  const ny = dx / length;
  const offset = (parallel.index - (parallel.count - 1) / 2) * 18;
  const control = {
    x: (source.x + target.x) / 2 + nx * offset,
    y: (source.y + target.y) / 2 + ny * offset,
  };
  ctx.moveTo(source.x, source.y);
  ctx.quadraticCurveTo(control.x, control.y, target.x, target.y);
  return control;
}

function drawArrowhead(
  ctx: CanvasRenderingContext2D,
  edge: ViewEdge,
  control: Vec2 | null,
  edgeKind: string,
  scale: number,
  styles: ThemeColors,
): void {
  const target = edge.target;
  const source = edge.source;
  const from = control ?? source;
  const angle = Math.atan2(target.y - from.y, target.x - from.x);
  const targetRadius = getNodeStyle(target.kind, styles).radius;
  const size = ARROW_SIZE / scale;
  const tip = {
    x: target.x - Math.cos(angle) * targetRadius,
    y: target.y - Math.sin(angle) * targetRadius,
  };
  const left = {
    x: tip.x - Math.cos(angle - Math.PI / 6) * size,
    y: tip.y - Math.sin(angle - Math.PI / 6) * size,
  };
  const right = {
    x: tip.x - Math.cos(angle + Math.PI / 6) * size,
    y: tip.y - Math.sin(angle + Math.PI / 6) * size,
  };

  ctx.beginPath();
  ctx.moveTo(tip.x, tip.y);
  ctx.lineTo(left.x, left.y);
  ctx.lineTo(right.x, right.y);
  ctx.closePath();
  if (edgeKind === "extends" || edgeKind === "implements") {
    ctx.stroke();
  } else {
    ctx.fill();
  }
}

function drawGlow(
  ctx: CanvasRenderingContext2D,
  node: ViewNode,
  radius: number,
  styles: ThemeColors,
): void {
  ctx.save();
  ctx.shadowColor = styles.highlightColor;
  ctx.shadowBlur = 18;
  ctx.fillStyle = styles.highlightColor;
  ctx.globalAlpha = 0.6;
  ctx.beginPath();
  ctx.arc(node.x, node.y, radius + 2, 0, Math.PI * 2);
  ctx.fill();
  ctx.restore();
}

function buildParallelInfo(edges: readonly ViewEdge[]): Map<number, ParallelInfo> {
  const groups = new Map<string, number[]>();
  edges.forEach((edge, index) => {
    const key = parallelKey(edge);
    const group = groups.get(key);
    if (group) {
      group.push(index);
    } else {
      groups.set(key, [index]);
    }
  });

  const parallel = new Map<number, ParallelInfo>();
  for (const group of groups.values()) {
    group.forEach((edgeIndex, index) => {
      parallel.set(edgeIndex, { count: group.length, index });
    });
  }
  return parallel;
}

function parallelKey(edge: ViewEdge): string {
  if (edge.sourceId < edge.targetId) {
    return `${edge.sourceId}\u0000${edge.targetId}`;
  }
  return `${edge.targetId}\u0000${edge.sourceId}`;
}

function focusOpacityForNode(
  node: ViewNode,
  selection: SelectionState,
  styles: ThemeColors,
): number {
  if (!selection.focusCenter) return 1;
  if (selection.focusNeighbors.has(node.id)) return 1;
  return styles.dimmedOpacity;
}

function focusOpacityForEdge(
  edge: ViewEdge,
  selection: SelectionState,
  styles: ThemeColors,
): number {
  if (!selection.focusCenter) return 0.65;
  if (selection.focusNeighbors.has(edge.sourceId) && selection.focusNeighbors.has(edge.targetId)) {
    return 0.75;
  }
  return styles.dimmedOpacity;
}

function labelLines(node: ViewNode, includeMetadata: boolean): string[] {
  const lines = [truncate(node.label, MAX_LABEL_CHARS)];
  if (includeMetadata && node.file) {
    lines.push(truncate(node.file, 32));
  }
  if (includeMetadata && node.doc) {
    lines.push(truncate(node.doc, 36));
  }
  return lines;
}

function truncate(value: string, maxChars: number): string {
  if (value.length <= maxChars) return value;
  return `${value.slice(0, maxChars - 3)}...`;
}

function getLod(scale: number): "modules" | "module-labels" | "labels" | "metadata" {
  if (scale < 0.3) return "modules";
  if (scale < 0.7) return "module-labels";
  if (scale < 1.5) return "labels";
  return "metadata";
}

function isEdgeInBounds(edge: ViewEdge, bounds: Bounds): boolean {
  if (isPointInBounds(edge.source.x, edge.source.y, bounds)) return true;
  if (isPointInBounds(edge.target.x, edge.target.y, bounds)) return true;
  const x0 = Math.min(edge.source.x, edge.target.x);
  const y0 = Math.min(edge.source.y, edge.target.y);
  const x1 = Math.max(edge.source.x, edge.target.x);
  const y1 = Math.max(edge.source.y, edge.target.y);
  return !(x1 < bounds.x0 || x0 > bounds.x1 || y1 < bounds.y0 || y0 > bounds.y1);
}

function isPointInBounds(x: number, y: number, bounds: Bounds): boolean {
  return x >= bounds.x0 && x <= bounds.x1 && y >= bounds.y0 && y <= bounds.y1;
}

function expandBounds(bounds: Bounds, margin: number): Bounds {
  return {
    x0: bounds.x0 - margin,
    y0: bounds.y0 - margin,
    x1: bounds.x1 + margin,
    y1: bounds.y1 + margin,
  };
}

function tooltipBackground(background: string): string {
  if (background === "#fafafa") return "rgba(255, 255, 255, 0.92)";
  return "rgba(15, 15, 20, 0.92)";
}

function roundRect(
  ctx: CanvasRenderingContext2D,
  x: number,
  y: number,
  width: number,
  height: number,
  radius: number,
): void {
  ctx.beginPath();
  ctx.moveTo(x + radius, y);
  ctx.lineTo(x + width - radius, y);
  ctx.quadraticCurveTo(x + width, y, x + width, y + radius);
  ctx.lineTo(x + width, y + height - radius);
  ctx.quadraticCurveTo(x + width, y + height, x + width - radius, y + height);
  ctx.lineTo(x + radius, y + height);
  ctx.quadraticCurveTo(x, y + height, x, y + height - radius);
  ctx.lineTo(x, y + radius);
  ctx.quadraticCurveTo(x, y, x + radius, y);
  ctx.closePath();
}

function clamp(value: number, min: number, max: number): number {
  return Math.max(min, Math.min(max, value));
}
