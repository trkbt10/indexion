/**
 * @file Cluster identity labels — a DOM overlay that names the
 * groups the user is looking at.
 *
 * Top-level labels appear at overview zoom. As the user zooms in,
 * nested clusters reveal their own labels in turn — so the user
 * can read "this green region is `cmd`" at overview, and "this
 * sub-cell inside `src` is `src/spec/align`" when zoomed closer.
 *
 * LOD strategy (single-axis, per-shell):
 *   - The shell projects to a screen-space pixel radius `px`.
 *   - We require `px >= revealPx(depth)` for the chip to appear.
 *     `revealPx` grows with depth, so deeper shells need more zoom.
 *   - The chip fades smoothstep across `[reveal, reveal+ramp]` so
 *     there's no pop.
 *   - A hard upper cap fades the chip back out when the shell
 *     becomes huge (camera essentially inside it) — the chip is
 *     no longer locating anything once its centre is off-screen.
 *
 * Crowding control:
 *   - Shells are ranked by an LOD-aware priority (depth penalty +
 *     leafCount + projected size) so the most informative chips
 *     win when there's no room.
 *   - Greedy bbox collision: a chip whose box overlaps an already-
 *     placed chip is dropped.
 *   - A hard cap (`MAX_VISIBLE_LABELS`) keeps the absolute count
 *     bounded even at deep zoom.
 *
 * Display name shortens nested paths relative to the parent so the
 * chip text is the *new* information the chip adds. `src/spec/align`
 * inside `src` reads as `spec/align`, not the full path again.
 */

import { Vector3 } from "three";
import type { ClusterShell, ThemeColors } from "../../types.ts";
import { clusterColor, topLevelOf } from "./cluster-palette.ts";
import type { SceneContext } from "./scene-context.ts";

export type ClusterLabelLayerInit = {
  readonly ctx: SceneContext;
  readonly container: HTMLElement;
  readonly theme: ThemeColors;
};

const MAX_LABEL_CHARS = 28;

/** Hard cap on simultaneously visible chips across all depths. The
 *  cap prevents deep zooms from suddenly producing a wall of nested
 *  text. Tuned to keep the canvas readable without losing the
 *  hierarchy: 28 is roughly "8 top + 20 nested". */
const MAX_VISIBLE_LABELS = 28;

/** LOD reveal threshold per depth, in projected pixel radius.
 *  Depth 1 (top groups) appear early; each deeper level needs the
 *  shell to be ~1.6× larger on screen before its chip fades in.
 *  These multiply as `BASE * GROWTH^(depth-1)` — a geometric ramp
 *  that mirrors how zoom multiplies projected sizes. */
const REVEAL_BASE_PX = 60;
const REVEAL_GROWTH = 1.55;
const REVEAL_RAMP_PX = 60;

/** Above this projected size, the chip starts fading out so it
 *  doesn't linger when the camera is essentially inside the
 *  cluster. Constant across depths — the underlying signal is the
 *  same: the cluster is no longer a "place" you're looking at, you're
 *  inside it. */
const FADE_OUT_FROM_PX = 2200;
const FADE_OUT_TO_PX = 4500;

/** Per-depth chip styling. Deeper levels are visually subordinate
 *  to their parents — smaller font, thinner padding — so the
 *  hierarchy reads at a glance even when many chips share the
 *  screen. Capped at depth 4 to avoid degenerate styling on very
 *  deep nests; deeper shells share the depth-4 style. */
const DEPTH_STYLE: readonly {
  readonly fontPx: number;
  readonly padY: number;
  readonly padX: number;
  readonly dotPx: number;
  readonly opacityCap: number;
}[] = [
  { fontPx: 11.5, padY: 3, padX: 8, dotPx: 8, opacityCap: 1 },
  { fontPx: 10.5, padY: 2, padX: 7, dotPx: 7, opacityCap: 0.92 },
  { fontPx: 10, padY: 2, padX: 6, dotPx: 6, opacityCap: 0.82 },
  { fontPx: 9.5, padY: 1, padX: 6, dotPx: 5, opacityCap: 0.72 },
];

type Candidate = {
  readonly shell: ClusterShell;
  readonly screen: { readonly x: number; readonly y: number };
  readonly projectedPx: number;
  readonly alpha: number;
  /** Sort key — bigger wins. Depth penalty makes shallow > deep
   *  at equal projected size; leafCount breaks ties within a
   *  depth (bigger group wins); projected size folds in zoom-
   *  weight so a strongly-zoomed sub-cluster can outrank a
   *  faraway top-level one. */
  readonly priority: number;
};

export class ClusterLabelLayer {
  private readonly ctx: SceneContext;
  private readonly root: HTMLElement;
  private readonly pool: HTMLElement[] = [];
  private theme: ThemeColors;
  private disposed = false;
  private readonly projVec = new Vector3();

  constructor(init: ClusterLabelLayerInit) {
    this.ctx = init.ctx;
    this.theme = init.theme;
    this.root = document.createElement("div");
    this.root.style.position = "absolute";
    this.root.style.inset = "0";
    this.root.style.pointerEvents = "none";
    this.root.style.overflow = "hidden";
    this.root.style.contain = "strict";
    init.container.appendChild(this.root);
  }

  setTheme(theme: ThemeColors): void {
    this.theme = theme;
    for (const el of this.pool) {
      this.applyChipTheme(el);
    }
  }

  rebuild(shells: readonly ClusterShell[]): void {
    if (this.disposed) {
      return;
    }
    if (shells.length === 0) {
      this.hideFrom(0);
      return;
    }

    const cam = this.ctx.camera.position;
    const px = pixelScale(this.ctx);

    // Build the candidate list: project + score every shell, drop
    // the ones outside their reveal window before any layout work.
    const candidates: Candidate[] = [];
    const margin = 80;
    for (const shell of shells) {
      const dx = shell.centre.x - cam.x;
      const dy = shell.centre.y - cam.y;
      const dz = shell.centre.z - cam.z;
      const dist = Math.sqrt(dx * dx + dy * dy + dz * dz) || 1;
      const projectedPx = (shell.radius * px) / dist;
      const reveal = revealPxFor(shell.depth);
      const fadeIn = smoothstep(reveal, reveal + REVEAL_RAMP_PX, projectedPx);
      const fadeOut =
        1 - smoothstep(FADE_OUT_FROM_PX, FADE_OUT_TO_PX, projectedPx);
      const depthStyle = styleForDepth(shell.depth);
      const alpha = Math.min(fadeIn, fadeOut) * depthStyle.opacityCap;
      if (alpha <= 0.02) {
        continue;
      }
      const screen = this.projectToScreen(shell.centre);
      if (!screen) {
        continue;
      }
      if (
        screen.x < -margin ||
        screen.x > this.ctx.width + margin ||
        screen.y < -margin ||
        screen.y > this.ctx.height + margin
      ) {
        continue;
      }
      const priority = scorePriority(shell, projectedPx);
      candidates.push({ shell, screen, projectedPx, alpha, priority });
    }

    // Highest-priority first so collision drops favour the
    // information-dense labels.
    candidates.sort((a, b) => b.priority - a.priority);

    let used = 0;
    const placed: Box[] = [];
    for (const cand of candidates) {
      if (used >= MAX_VISIBLE_LABELS) {
        break;
      }
      const chip = this.getChip(used);
      const path = cand.shell.path;
      // Display the new information at this depth — the leaf
      // segment relative to the parent — so a chip on a nested
      // cluster doesn't repeat what the parent chip already says.
      const text = displayName(path);
      this.styleChip(chip, cand.shell.depth);
      this.setChipText(chip, text, path);

      // Off-screen measure so width/height are the laid-out values.
      chip.style.display = "flex";
      chip.style.opacity = "0";
      chip.style.transform = `translate3d(-9999px, -9999px, 0)`;
      const w = chip.offsetWidth;
      const h = chip.offsetHeight;
      const x = cand.screen.x - w / 2;
      const y = cand.screen.y - h / 2;
      const box: Box = { x0: x, y0: y, x1: x + w, y1: y + h };
      if (intersectsAny(box, placed)) {
        chip.style.display = "none";
        continue;
      }
      chip.style.transform = `translate3d(${x}px, ${y}px, 0)`;
      chip.style.opacity = `${cand.alpha}`;
      placed.push(box);
      used++;
    }

    this.hideFrom(used);
  }

  dispose(): void {
    if (this.disposed) {
      return;
    }
    this.disposed = true;
    this.root.remove();
    this.pool.length = 0;
  }

  private hideFrom(index: number): void {
    for (let i = index; i < this.pool.length; i++) {
      this.pool[i]!.style.display = "none";
    }
  }

  private getChip(index: number): HTMLElement {
    const existing = this.pool[index];
    if (existing) {
      return existing;
    }
    const chip = document.createElement("div");
    chip.style.position = "absolute";
    chip.style.left = "0";
    chip.style.top = "0";
    chip.style.borderRadius = "12px";
    chip.style.fontFamily =
      "Inter, ui-sans-serif, system-ui, -apple-system, sans-serif";
    chip.style.fontWeight = "500";
    chip.style.lineHeight = "1.1";
    chip.style.letterSpacing = "-0.005em";
    chip.style.whiteSpace = "nowrap";
    chip.style.alignItems = "center";
    chip.style.gap = "5px";
    chip.style.willChange = "transform, opacity";
    chip.style.transition = "opacity 240ms ease-out";
    chip.style.backdropFilter = "blur(6px)";
    chip.style.setProperty("-webkit-backdrop-filter", "blur(6px)");
    this.applyChipTheme(chip);

    const dot = document.createElement("span");
    dot.dataset.role = "swatch";
    dot.style.borderRadius = "50%";
    dot.style.flexShrink = "0";
    chip.appendChild(dot);

    const label = document.createElement("span");
    label.dataset.role = "text";
    chip.appendChild(label);

    this.root.appendChild(chip);
    this.pool.push(chip);
    return chip;
  }

  private applyChipTheme(el: HTMLElement): void {
    el.style.backgroundColor = this.theme.tooltipBackground;
    el.style.color = this.theme.labelColor;
    el.style.border = `1px solid ${this.theme.tooltipBorder}`;
  }

  private styleChip(chip: HTMLElement, depth: number): void {
    const s = styleForDepth(depth);
    chip.style.padding = `${s.padY}px ${s.padX}px ${s.padY}px ${s.padX - 2}px`;
    chip.style.fontSize = `${s.fontPx}px`;
    const dot = chip.children[0] as HTMLElement | undefined;
    if (dot) {
      dot.style.width = `${s.dotPx}px`;
      dot.style.height = `${s.dotPx}px`;
    }
  }

  private setChipText(chip: HTMLElement, text: string, path: string): void {
    const dot = chip.children[0] as HTMLElement | undefined;
    const label = chip.children[1] as HTMLElement | undefined;
    if (!dot || !label) return;
    const c = clusterColor(topLevelOf(path));
    const r = Math.round(c.r * 255);
    const g = Math.round(c.g * 255);
    const b = Math.round(c.b * 255);
    dot.style.backgroundColor = `rgb(${r}, ${g}, ${b})`;
    if (label.textContent !== text) {
      label.textContent = text;
    }
  }

  private projectToScreen(
    pos: { readonly x: number; readonly y: number; readonly z: number },
  ): { readonly x: number; readonly y: number } | null {
    this.projVec.set(pos.x, pos.y, pos.z);
    this.projVec.project(this.ctx.camera);
    if (this.projVec.z < -1 || this.projVec.z > 1) {
      return null;
    }
    return {
      x: ((this.projVec.x + 1) / 2) * this.ctx.width,
      y: ((1 - this.projVec.y) / 2) * this.ctx.height,
    };
  }
}

// ─── helpers ─────────────────────────────────────────────────────

type Box = { readonly x0: number; readonly y0: number; readonly x1: number; readonly y1: number };

function intersectsAny(box: Box, others: readonly Box[]): boolean {
  for (const o of others) {
    if (box.x0 < o.x1 && box.x1 > o.x0 && box.y0 < o.y1 && box.y1 > o.y0) {
      return true;
    }
  }
  return false;
}

function smoothstep(edge0: number, edge1: number, value: number): number {
  if (edge1 === edge0) {
    return value < edge0 ? 0 : 1;
  }
  const t = clamp((value - edge0) / (edge1 - edge0), 0, 1);
  return t * t * (3 - 2 * t);
}

function clamp(v: number, lo: number, hi: number): number {
  return v < lo ? lo : v > hi ? hi : v;
}

function pixelScale(ctx: SceneContext): number {
  const halfFov = (ctx.camera.fov * Math.PI) / 360;
  return ctx.height / (2 * Math.tan(halfFov));
}

function revealPxFor(depth: number): number {
  const d = Math.max(1, depth);
  return REVEAL_BASE_PX * Math.pow(REVEAL_GROWTH, d - 1);
}

function styleForDepth(depth: number): (typeof DEPTH_STYLE)[number] {
  const idx = Math.min(DEPTH_STYLE.length - 1, Math.max(0, depth - 1));
  return DEPTH_STYLE[idx]!;
}

/** Score a shell for chip-placement ranking. Bigger wins.
 *
 *  Components:
 *    - depthWeight: top-level shells get a strong head-start so
 *      they always beat nested rivals at equal projected size.
 *    - sizeWeight: log-scaled leaf count, so an enormous group
 *      isn't infinitely more important than a sizeable one.
 *    - zoomWeight: the projected size — a sub-cluster the user
 *      has zoomed into outranks an off-screen top-level shell. */
function scorePriority(shell: ClusterShell, projectedPx: number): number {
  const depthWeight = 1 / Math.max(1, shell.depth);
  const sizeWeight = Math.log10(1 + shell.leafCount);
  const zoomWeight = Math.log10(1 + projectedPx);
  return depthWeight * 2 + sizeWeight + zoomWeight;
}

/** Strip strategy-specific prefixes / synthetic ids so the label
 *  reads as the user's mental model. Long paths are abbreviated to
 *  their last meaningful segment + parent so the chip stays short
 *  but still locates the group. */
function displayName(path: string): string {
  if (path === "__isolates__") return "isolates";
  if (path.startsWith("__isolates_") && path.endsWith("__")) return "isolates";
  if (path.startsWith("kmeans-")) return `cluster ${path.slice(7)}`;
  let stripped = path;
  for (const prefix of ["mod:", "kind:", "dir:", "c:"]) {
    if (stripped.startsWith(prefix)) {
      stripped = stripped.slice(prefix.length);
      break;
    }
  }
  return truncate(abbreviatePath(stripped), MAX_LABEL_CHARS);
}

/** Keep the trailing 2 path segments at most. Adds an ellipsis
 *  prefix when we drop earlier segments so the user knows it's a
 *  tail. The parent chip carries the early path; this chip should
 *  add what's *new* at this depth. */
function abbreviatePath(s: string): string {
  const parts = s.split("/");
  if (parts.length <= 2) {
    return s;
  }
  return `…/${parts[parts.length - 2]}/${parts[parts.length - 1]}`;
}

function truncate(s: string, max: number): string {
  if (s.length <= max) return s;
  return s.slice(0, max - 1) + "…";
}
