/**
 * @file Squarified treemap algorithm.
 *
 * Given a rectangle and a list of weighted children, partition the
 * rectangle into child rectangles whose areas are proportional to the
 * weights and whose aspect ratios stay as close to 1 as possible.
 *
 * Reference: Bruls, Huizing, van Wijk — "Squarified Treemaps" (2000).
 *
 * Why this and not a sphere shell:
 *   The previous hierarchical layout placed sibling clusters on a
 *   Fibonacci sphere, which wastes most of the parent volume on empty
 *   shell space. A treemap uses 100% of the parent area, so cluster
 *   density tracks node count linearly instead of cube-root-ly.
 *
 * Pure module. No DOM, no node mutation; produces plain rectangles.
 */

import type { Rect } from "../../types.ts";

export type WeightedItem<T> = {
  readonly key: T;
  /** Strictly positive weight. Caller must ensure > 0. */
  readonly weight: number;
};

export type LayoutItem<T> = {
  readonly key: T;
  readonly rect: Rect;
};

export type SquarifyArgs<T> = {
  readonly rect: Rect;
  readonly items: readonly WeightedItem<T>[];
};

/** Squarified treemap. Items are placed in the order given; pre-sort
 *  largest first for optimal aspect ratios.
 *
 *  Algorithm: greedy row packing along the shorter side of the
 *  remaining strip. We add items to the current row as long as doing
 *  so does not worsen the maximum aspect ratio in the row; once it
 *  does, we close the row and start a new one.
 *
 *  Special case: when all items carry the same weight, the squarified
 *  algorithm can still produce slightly different aspect ratios across
 *  cells (last row may shrink). Identical weights should *visually*
 *  produce identical cells — so we route them to a uniform grid
 *  layout instead. */
export function squarify<T>(args: SquarifyArgs<T>): LayoutItem<T>[] {
  const { rect, items } = args;
  if (items.length === 0) {
    return [];
  }
  const totalArea = rect.w * rect.h;
  const totalWeight = sumWeights(items);
  if (totalWeight <= 0 || totalArea <= 0) {
    return items.map((it) => ({ key: it.key, rect: { ...rect, w: 0, h: 0 } }));
  }
  if (allEqual(items)) {
    return uniformGrid({ rect, items });
  }
  // Convert weights to areas in the rect's coordinate system.
  const areas = items.map((it) => (it.weight / totalWeight) * totalArea);
  const out: LayoutItem<T>[] = [];
  squarifyRecursive({
    items,
    areas,
    rect,
    start: 0,
    out,
  });
  return out;
}

/** True iff every item shares the first item's weight (within ε). */
function allEqual<T>(items: readonly WeightedItem<T>[]): boolean {
  if (items.length <= 1) {
    return true;
  }
  const first = items[0]!.weight;
  for (let i = 1; i < items.length; i++) {
    if (Math.abs(items[i]!.weight - first) > 1e-9) {
      return false;
    }
  }
  return true;
}

/** Uniform grid layout: split the rect into a (cols × rows) grid where
 *  cols is chosen so per-cell aspect ratio is closest to 1. Trailing
 *  empty cells stay empty (no row collapse), so every placed cell has
 *  identical width and height. */
function uniformGrid<T>(args: SquarifyArgs<T>): LayoutItem<T>[] {
  const { rect, items } = args;
  const n = items.length;
  const ar = rect.w / Math.max(rect.h, 1e-12);
  const cols = Math.max(1, Math.round(Math.sqrt(n * ar)));
  const rows = Math.max(1, Math.ceil(n / cols));
  const cellW = rect.w / cols;
  const cellH = rect.h / rows;
  const out: LayoutItem<T>[] = new Array(n);
  for (let i = 0; i < n; i++) {
    const c = i % cols;
    const r = Math.floor(i / cols);
    out[i] = {
      key: items[i]!.key,
      rect: {
        x: rect.x + c * cellW,
        y: rect.y + r * cellH,
        w: cellW,
        h: cellH,
      },
    };
  }
  return out;
}

type RecursiveArgs<T> = {
  readonly items: readonly WeightedItem<T>[];
  readonly areas: readonly number[];
  readonly rect: Rect;
  readonly start: number;
  readonly out: LayoutItem<T>[];
};

function squarifyRecursive<T>(args: RecursiveArgs<T>): void {
  const { items, areas, rect, start, out } = args;
  if (start >= items.length || rect.w <= 0 || rect.h <= 0) {
    return;
  }
  // Pack along the shorter side so growth happens on the longer side
  // and aspect ratios stay close to 1.
  const shorter = Math.min(rect.w, rect.h);
  // Greedily extend the row while the worst aspect ratio improves.
  let rowEnd = start + 1;
  let bestWorst = worstAspect({
    areas,
    start,
    end: rowEnd,
    shorter,
  });
  while (rowEnd < items.length) {
    const candidate = worstAspect({
      areas,
      start,
      end: rowEnd + 1,
      shorter,
    });
    if (candidate >= bestWorst) {
      // Adding the next item makes the row worse — close it here.
      break;
    }
    bestWorst = candidate;
    rowEnd++;
  }
  // Lay out the row along `shorter`. Row's own thickness =
  // rowArea / shorter so the row itself fills its slab.
  let rowArea = 0;
  for (let i = start; i < rowEnd; i++) {
    rowArea += areas[i]!;
  }
  const rowThickness = rowArea / shorter;
  let cursor = 0;
  let rowRect: Rect;
  let nextRect: Rect;
  if (rect.w <= rect.h) {
    // Row spans the width, stacks vertically.
    rowRect = { x: rect.x, y: rect.y, w: rect.w, h: rowThickness };
    nextRect = {
      x: rect.x,
      y: rect.y + rowThickness,
      w: rect.w,
      h: Math.max(0, rect.h - rowThickness),
    };
  } else {
    // Row spans the height, stacks horizontally.
    rowRect = { x: rect.x, y: rect.y, w: rowThickness, h: rect.h };
    nextRect = {
      x: rect.x + rowThickness,
      y: rect.y,
      w: Math.max(0, rect.w - rowThickness),
      h: rect.h,
    };
  }
  for (let i = start; i < rowEnd; i++) {
    const cellArea = areas[i]!;
    const cellLength = cellArea / Math.max(rowThickness, 1e-12);
    const cellRect: Rect =
      rect.w <= rect.h
        ? {
            x: rowRect.x + cursor,
            y: rowRect.y,
            w: cellLength,
            h: rowRect.h,
          }
        : {
            x: rowRect.x,
            y: rowRect.y + cursor,
            w: rowRect.w,
            h: cellLength,
          };
    out.push({ key: items[i]!.key, rect: cellRect });
    cursor += cellLength;
  }
  squarifyRecursive({
    items,
    areas,
    rect: nextRect,
    start: rowEnd,
    out,
  });
}

type AspectArgs = {
  readonly areas: readonly number[];
  readonly start: number;
  readonly end: number;
  readonly shorter: number;
};

/** Worst aspect ratio (max(w/h, h/w) ≥ 1) among items [start, end)
 *  if they were placed as a row along the strip of length `shorter`. */
function worstAspect(args: AspectArgs): number {
  const { areas, start, end, shorter } = args;
  let sum = 0;
  let maxA = 0;
  let minA = Infinity;
  for (let i = start; i < end; i++) {
    const a = areas[i]!;
    sum += a;
    if (a > maxA) {
      maxA = a;
    }
    if (a < minA) {
      minA = a;
    }
  }
  if (sum <= 0) {
    return Infinity;
  }
  const s2 = shorter * shorter;
  const sum2 = sum * sum;
  // For each cell: thickness = sum / shorter; length = a · shorter / sum.
  // Aspect ratio = max(L/T, T/L). Worst case is the smallest cell
  // (longest thin sliver) or the largest cell.
  const worstA = Math.max(
    (s2 * maxA) / sum2,
    sum2 / (s2 * Math.max(maxA, 1e-12)),
  );
  const worstB = Math.max(
    (s2 * minA) / sum2,
    sum2 / (s2 * Math.max(minA, 1e-12)),
  );
  return Math.max(worstA, worstB);
}

function sumWeights<T>(items: readonly WeightedItem<T>[]): number {
  let s = 0;
  for (const it of items) {
    s += it.weight;
  }
  return s;
}

/** Shrink a rectangle inward by `pad` on each side. Returns a degenerate
 *  rect (w=0/h=0) if the padding consumes the whole rectangle. */
export function inset(rect: Rect, pad: number): Rect {
  const w = Math.max(0, rect.w - 2 * pad);
  const h = Math.max(0, rect.h - 2 * pad);
  return { x: rect.x + pad, y: rect.y + pad, w, h };
}

/** Centre and inscribed-circle radius of a rectangle. The renderer
 *  treats cluster shells as spheres; we expose the inscribed circle so
 *  shells don't poke outside their treemap cell. */
export function inscribedCircle(rect: Rect): {
  readonly cx: number;
  readonly cy: number;
  readonly r: number;
} {
  return {
    cx: rect.x + rect.w / 2,
    cy: rect.y + rect.h / 2,
    r: Math.min(rect.w, rect.h) / 2,
  };
}

/** Circumscribed-circle radius of a rectangle (half-diagonal). Used
 *  when we want the shell circle to *contain* every node in the cell
 *  rather than be inscribed inside it. */
export function circumscribedRadius(rect: Rect): number {
  return Math.sqrt(rect.w * rect.w + rect.h * rect.h) / 2;
}
