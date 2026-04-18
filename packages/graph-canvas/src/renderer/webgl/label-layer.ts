/**
 * @file DOM label overlay for the WebGL renderer.
 *
 * Labels are plain absolute-positioned <div> elements placed on top of
 * the WebGL canvas. For each frame we:
 *
 *   1. collect label candidates (hover, selection, focus, top-degree
 *      hubs) — same policy as the canvas2d renderer
 *   2. project their 3D world position to screen space via the camera
 *      (no three.js CSS2DRenderer dependency — a one-liner per label)
 *   3. run a greedy screen-space collision test so overlapping chips
 *      drop to lower priority
 *   4. apply transform + opacity to DOM elements drawn from a pool
 *
 * Chips that aren't used this frame are hidden with `display: none`
 * rather than removed so the layout cost stays constant across frames.
 */

import { PerspectiveCamera, Vector3, type OrthographicCamera } from "three";
import type {
  FilterResult,
  SelectionState,
  ThemeColors,
  ViewGraph,
  ViewNode,
} from "../../types.ts";

export type LabelLayerInit = {
  /** Container that will host the label <div> pool. */
  readonly container: HTMLElement;
  readonly theme: ThemeColors;
};

export type LabelUpdateArgs = {
  readonly graph: ViewGraph;
  readonly filter: FilterResult;
  readonly selection: SelectionState;
  readonly hoverNode: ViewNode | null;
  readonly degreeMap: ReadonlyMap<string, number>;
  readonly camera: OrthographicCamera | PerspectiveCamera;
  readonly width: number;
  readonly height: number;
  /** 0 — zoomed out, 1 — zoomed in. Drives static-label opacity & cap. */
  readonly detailFactor: number;
  readonly theme: ThemeColors;
};

const MAX_STATIC_LABELS = 12;
const LABEL_MAX_CHARS = 22;
/** Hover label can be longer — users want the full cluster path to
 *  identify what they're looking at. Truncate only if ridiculous. */
const HOVER_LABEL_MAX_CHARS = 60;

export class LabelLayer {
  private readonly root: HTMLElement;
  private readonly pool: HTMLElement[] = [];
  private theme: ThemeColors;
  private disposed = false;
  private readonly projVec = new Vector3();

  constructor(init: LabelLayerInit) {
    this.theme = init.theme;
    this.root = document.createElement("div");
    applyRootStyle(this.root);
    init.container.appendChild(this.root);
  }

  dispose(): void {
    if (this.disposed) {
      return;
    }
    this.disposed = true;
    this.root.remove();
    this.pool.length = 0;
  }

  setTheme(theme: ThemeColors): void {
    this.theme = theme;
    // Theme change affects chip colours; force a redraw on next update
    // by marking each DOM element dirty so its CSS vars get updated.
    for (const el of this.pool) {
      applyChipTheme(el, theme);
    }
  }

  update(args: LabelUpdateArgs): void {
    if (this.disposed) {
      return;
    }
    const candidates = collectCandidates(args);
    const placed: Box[] = [];
    let used = 0;

    for (const cand of candidates) {
      if (cand.opacity < 0.02) {
        continue;
      }
      const screen = projectToScreen({
        camera: args.camera,
        position: cand.node,
        width: args.width,
        height: args.height,
        scratch: this.projVec,
      });
      if (!screen || !insideViewport(screen, args.width, args.height)) {
        continue;
      }

      const chip = this.getChip(used);
      const isHover = cand.node === args.hoverNode;
      // On hover we want to answer "what cluster does this node
      // belong to?" — surfacing the file path (or node id if no
      // file), which reads as the cluster hierarchy. Other labels
      // (selected, search hit) keep the compact display name.
      const rawText = pickLabelText(cand.node, isHover);
      const text = truncate(
        rawText,
        isHover ? HOVER_LABEL_MAX_CHARS : LABEL_MAX_CHARS,
      );
      if (chip.textContent !== text) {
        chip.textContent = text;
      }
      // Measure once laid out — before we know the box bounds we
      // temporarily show the chip off-screen to get its width.
      chip.style.display = "block";
      chip.style.opacity = "0";
      chip.style.transform = `translate3d(-9999px, -9999px, 0)`;
      const width = chip.offsetWidth;
      const height = chip.offsetHeight;

      const nodeScreenRadius = 6; // approximate; collision-avoidance
      // only needs consistency, not the exact pixel radius.
      const box: Box = {
        x0: screen.x + nodeScreenRadius + 4,
        y0: screen.y - height / 2,
        x1: screen.x + nodeScreenRadius + 4 + width,
        y1: screen.y + height / 2,
      };
      if (intersectsAny(box, placed) && cand.priority < 3) {
        chip.style.display = "none";
        continue;
      }

      chip.style.transform = `translate3d(${box.x0}px, ${box.y0}px, 0)`;
      chip.style.opacity = `${cand.opacity}`;
      chip.dataset.emphasis = cand.priority >= 3 ? "true" : "false";
      applyChipEmphasis(chip, cand.priority >= 3, this.theme);
      placed.push(box);
      used++;
    }

    for (let i = used; i < this.pool.length; i++) {
      this.pool[i]!.style.display = "none";
    }
  }

  private getChip(index: number): HTMLElement {
    const existing = this.pool[index];
    if (existing) {
      return existing;
    }
    const el = document.createElement("div");
    applyChipBaseStyle(el, this.theme);
    this.root.appendChild(el);
    this.pool.push(el);
    return el;
  }
}

// ─── DOM styling ─────────────────────────────────────────────────

function applyRootStyle(root: HTMLElement): void {
  root.style.position = "absolute";
  root.style.inset = "0";
  root.style.pointerEvents = "none";
  root.style.overflow = "hidden";
  root.style.contain = "strict";
}

function applyChipBaseStyle(el: HTMLElement, theme: ThemeColors): void {
  el.style.position = "absolute";
  el.style.left = "0";
  el.style.top = "0";
  el.style.padding = "2px 6px";
  el.style.borderRadius = "3px";
  el.style.fontFamily =
    "Inter, ui-sans-serif, system-ui, -apple-system, sans-serif";
  el.style.fontSize = "11.5px";
  el.style.lineHeight = "1.1";
  el.style.letterSpacing = "-0.005em";
  el.style.whiteSpace = "nowrap";
  el.style.willChange = "transform, opacity";
  el.style.transition = "opacity 180ms ease-out";
  applyChipTheme(el, theme);
  applyChipEmphasis(el, false, theme);
}

function applyChipTheme(el: HTMLElement, theme: ThemeColors): void {
  el.style.backgroundColor = theme.tooltipBackground;
  el.style.color = theme.labelColor;
}

function applyChipEmphasis(
  el: HTMLElement,
  emphasised: boolean,
  theme: ThemeColors,
): void {
  if (emphasised) {
    el.style.border = `1px solid ${theme.selectionColor}`;
    el.style.color = theme.selectionColor;
  } else {
    el.style.border = `1px solid ${theme.tooltipBorder}`;
    el.style.color = theme.labelColor;
  }
}

// ─── Candidate selection ─────────────────────────────────────────

type Candidate = {
  readonly node: ViewNode;
  readonly priority: number;
  readonly opacity: number;
};

function collectCandidates(args: LabelUpdateArgs): Candidate[] {
  const { graph, filter, selection, hoverNode, degreeMap, detailFactor } = args;
  const out: Candidate[] = [];
  const seen = new Set<string>();
  const push = (node: ViewNode, priority: number, opacity: number) => {
    if (!filter.visibleNodes.has(node.id)) {
      return;
    }
    if (seen.has(node.id)) {
      return;
    }
    seen.add(node.id);
    out.push({ node, priority, opacity });
  };

  if (hoverNode) {
    push(hoverNode, 3, 1);
  }
  for (const id of selection.selected) {
    const node = graph.nodeIndex.get(id);
    if (node) {
      push(node, 3, 1);
    }
  }
  if (selection.focusCenter) {
    const node = graph.nodeIndex.get(selection.focusCenter);
    if (node) {
      push(node, 3, 1);
    }
    for (const id of selection.focusNeighbors) {
      const neighbour = graph.nodeIndex.get(id);
      if (neighbour) {
        push(neighbour, 2, 1);
      }
    }
  }

  if (detailFactor <= 0.01) {
    return out;
  }
  const cap = Math.max(1, Math.round(MAX_STATIC_LABELS * detailFactor));
  const sorted = graph.nodes
    .filter((n) => filter.visibleNodes.has(n.id))
    .sort((a, b) => (degreeMap.get(b.id) ?? 0) - (degreeMap.get(a.id) ?? 0));
  for (let i = 0; i < sorted.length && out.length - intrinsic(out) < cap; i++) {
    const node = sorted[i]!;
    if ((degreeMap.get(node.id) ?? 0) < 3) {
      break;
    }
    push(node, 1, detailFactor);
  }
  return out;
}

function intrinsic(list: readonly Candidate[]): number {
  let count = 0;
  for (const c of list) {
    if (c.priority >= 2) {
      count++;
    }
  }
  return count;
}

// ─── Projection & collision ──────────────────────────────────────

type ScreenPos = { readonly x: number; readonly y: number };
type Box = { x0: number; y0: number; x1: number; y1: number };

function projectToScreen(args: {
  readonly camera: OrthographicCamera | PerspectiveCamera;
  readonly position: ViewNode;
  readonly width: number;
  readonly height: number;
  readonly scratch: Vector3;
}): ScreenPos | null {
  const { camera, position, width, height, scratch } = args;
  scratch.set(position.x, position.y, position.z).project(camera);
  // NDC outside [-1, 1] on any axis → behind camera or off-screen.
  if (
    scratch.x < -1.5 ||
    scratch.x > 1.5 ||
    scratch.y < -1.5 ||
    scratch.y > 1.5 ||
    scratch.z > 1
  ) {
    return null;
  }
  return {
    x: ((scratch.x + 1) * width) / 2,
    y: ((1 - scratch.y) * height) / 2,
  };
}

function insideViewport(p: ScreenPos, w: number, h: number): boolean {
  return p.x >= 0 && p.x <= w && p.y >= 0 && p.y <= h;
}

function intersectsAny(box: Box, placed: readonly Box[]): boolean {
  for (const o of placed) {
    if (box.x0 < o.x1 && box.x1 > o.x0 && box.y0 < o.y1 && box.y1 > o.y0) {
      return true;
    }
  }
  return false;
}

function truncate(value: string, max: number): string {
  if (value.length <= max) {
    return value;
  }
  return `${value.slice(0, max - 1)}…`;
}

/** Compact display name by default; on hover we surface the file
 *  path (or node id) so the reader sees the cluster context. */
function pickLabelText(node: ViewNode, isHover: boolean): string {
  if (!isHover) {
    return node.label;
  }
  if (node.file && node.file.length > 0) {
    return node.file;
  }
  return node.id;
}
