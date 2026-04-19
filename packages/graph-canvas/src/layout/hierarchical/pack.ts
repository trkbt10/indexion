/**
 * @file Recursive treemap packer.
 *
 * Walks the path tree top-down: at each level, partition the parent
 * rectangle into child rectangles via squarified treemap (area
 * proportional to descendant-leaf count), then recurse. At each leaf
 * cluster, place owned nodes inside the cell.
 *
 * Emits one ClusterShell per visited path so the renderer can
 * outline cluster regions. Shell circles are inscribed in their cell
 * rectangle, then expanded slightly to enclose the node positions
 * (ensuring the interior-fade LOD finds the right enclosing shell).
 */

import type {
  ClusterShell,
  LayoutSettings,
  Rect,
  ViewNode,
} from "../../types.ts";
import { placeCellNodes } from "./place-cell.ts";
import {
  inscribedCircle,
  inset,
  squarify,
  type WeightedItem,
} from "./treemap.ts";

export type PackArgs = {
  readonly rect: Rect;
  readonly depth: number;
  readonly children: readonly string[];
  readonly childrenOf: ReadonlyMap<string, readonly string[]>;
  readonly ownedNodes: ReadonlyMap<string, readonly ViewNode[]>;
  /** Total number of leaf nodes under each path. Used as the treemap
   *  weight so denser branches get larger rectangles. */
  readonly weightOf: ReadonlyMap<string, number>;
  /** Optional adjacency map used to order leaves so connected nodes
   *  end up in nearby grid slots. */
  readonly adjacency: ReadonlyMap<string, readonly string[]> | null;
  readonly settings: LayoutSettings;
  readonly collectShell: (shell: ClusterShell) => void;
};

/** Recursively pack `children` into `rect` and place their owned
 *  leaves. Each child's rectangle is shrunk by `cellPadding(depth)`
 *  before recursing so nested cells visibly nest. */
export function packChildren(args: PackArgs): void {
  const {
    rect,
    depth,
    children,
    childrenOf,
    ownedNodes,
    weightOf,
    adjacency,
    settings,
    collectShell,
  } = args;
  if (children.length === 0 || rect.w <= 0 || rect.h <= 0) {
    return;
  }
  // Sort largest-first so squarify produces the best aspect ratios.
  const sorted = [...children].sort(
    (a, b) => (weightOf.get(b) ?? 0) - (weightOf.get(a) ?? 0),
  );
  const items: WeightedItem<string>[] = sorted.map((path) => ({
    key: path,
    weight: Math.max(1, weightOf.get(path) ?? 1),
  }));
  const placed = squarify({ rect, items });
  const basePadding = cellPadding(depth, settings);

  for (const { key: childPath, rect: childRect } of placed) {
    if (childRect.w <= 0 || childRect.h <= 0) {
      // Degenerate — skip to avoid NaN downstream. This only happens
      // when the parent rect has been over-padded relative to its size.
      continue;
    }
    // Cap padding so it never consumes more than 25% of the smaller
    // cell dimension. Without this clamp, tiny cells (singleton paths
    // inside a heavy parent) would inset to zero size and the
    // inscribed shell radius would collapse to 0 — invisible to both
    // the shell drawer and the interior-LOD logic.
    const minDim = Math.min(childRect.w, childRect.h);
    const padding = Math.min(basePadding, minDim * 0.25);
    const innerRect = inset(childRect, padding);
    const owned = ownedNodes.get(childPath) ?? [];
    const grandchildren = childrenOf.get(childPath) ?? [];
    // Shell circle: inscribed in the *inner* (post-padding) rectangle
    // so adjacent siblings always have a visible gap and the renderer's
    // disjointness invariant holds. Sub-clusters and owned leaves both
    // sit inside this same inner rectangle, so the shell visibly
    // contains its content.
    const ic = inscribedCircle(innerRect);
    const isLeafCluster = grandchildren.length === 0;
    collectShell({
      path: childPath,
      centre: { x: ic.cx, y: ic.cy, z: 0 },
      radius: ic.r,
      depth,
      rect: innerRect,
      kind: "treemap",
      isLeaf: isLeafCluster,
      leafCount: weightOf.get(childPath) ?? 0,
    });
    if (owned.length > 0) {
      // If the cell has both owned leaves AND sub-clusters, give the
      // leaves a band on the outer edge so they don't collide with
      // sub-bubbles. We carve a thin rim out of the inner rect.
      if (grandchildren.length > 0) {
        placeOwnedInRim({
          nodes: owned,
          rect: innerRect,
          rimFraction: settings.innerFraction,
          padding: padding * 0.5,
          adjacency,
        });
      } else {
        const ordered = orderByAdjacency(owned, adjacency);
        placeCellNodes({
          nodes: owned,
          rect: innerRect,
          padding: leafPadding(settings),
          ordered,
        });
      }
    }
    if (grandchildren.length > 0) {
      // Carve out the centre of innerRect for the sub-clusters; the
      // outer rim hosts owned leaves (placed above) so they remain
      // visible alongside the nested clusters.
      const subRect =
        owned.length > 0
          ? centreSubRect(innerRect, settings.innerFraction)
          : innerRect;
      packChildren({
        rect: subRect,
        depth: depth + 1,
        children: grandchildren,
        childrenOf,
        ownedNodes,
        weightOf,
        adjacency,
        settings,
        collectShell,
      });
    }
  }
}

type RimArgs = {
  readonly nodes: readonly ViewNode[];
  readonly rect: Rect;
  /** Fraction of each side used by the central sub-cluster region.
   *  Owned leaves sit in the rim outside this central rect. */
  readonly rimFraction: number;
  readonly padding: number;
  readonly adjacency: ReadonlyMap<string, readonly string[]> | null;
};

/** Place owned nodes in the rim around the central sub-cluster
 *  region. The rim is the symmetric difference between `rect` and
 *  the centred sub-rect. We place nodes uniformly along the rim
 *  perimeter so they don't bunch in corners. */
function placeOwnedInRim(args: RimArgs): void {
  const { nodes, rect, rimFraction, adjacency } = args;
  const ordered = orderByAdjacency(nodes, adjacency);
  const n = ordered.length;
  if (n === 0) {
    return;
  }
  // Compute the inner sub-rect that the rim wraps around.
  const innerW = rect.w * rimFraction;
  const innerH = rect.h * rimFraction;
  const innerX = rect.x + (rect.w - innerW) / 2;
  const innerY = rect.y + (rect.h - innerH) / 2;
  // Walk the rim along its perimeter; the rim is a "frame" of
  // thickness rimMargin = (rect.w - innerW) / 2 horizontally and
  // (rect.h - innerH) / 2 vertically. We place nodes along the
  // centre-line of the frame.
  const xLeft = (rect.x + innerX) / 2;
  const xRight = (rect.x + rect.w + innerX + innerW) / 2;
  const yTop = (rect.y + innerY) / 2;
  const yBot = (rect.y + rect.h + innerY + innerH) / 2;
  // Length of each side of the rim centre-line.
  const horizLen = xRight - xLeft;
  const vertLen = yBot - yTop;
  const perim = 2 * (horizLen + vertLen);
  if (perim <= 0) {
    // Degenerate — fall back to grid placement.
    placeCellNodes({ nodes: ordered, rect, padding: 0 });
    return;
  }
  for (let i = 0; i < n; i++) {
    const t = (i + 0.5) / n;
    const s = t * perim;
    const pos = perimeterPoint({
      s,
      xLeft,
      xRight,
      yTop,
      yBot,
      horizLen,
      vertLen,
    });
    ordered[i]!.x = pos.x;
    ordered[i]!.y = pos.y;
    ordered[i]!.z = 0;
    ordered[i]!.vx = 0;
    ordered[i]!.vy = 0;
    ordered[i]!.vz = 0;
  }
}

type PerimArgs = {
  readonly s: number;
  readonly xLeft: number;
  readonly xRight: number;
  readonly yTop: number;
  readonly yBot: number;
  readonly horizLen: number;
  readonly vertLen: number;
};

function perimeterPoint(args: PerimArgs): { readonly x: number; readonly y: number } {
  const { s, xLeft, xRight, yTop, yBot, horizLen, vertLen } = args;
  // Walk: top edge → right edge → bottom edge → left edge.
  let remaining = s;
  if (remaining < horizLen) {
    return { x: xLeft + remaining, y: yTop };
  }
  remaining -= horizLen;
  if (remaining < vertLen) {
    return { x: xRight, y: yTop + remaining };
  }
  remaining -= vertLen;
  if (remaining < horizLen) {
    return { x: xRight - remaining, y: yBot };
  }
  remaining -= horizLen;
  return { x: xLeft, y: yBot - remaining };
}

function centreSubRect(rect: Rect, fraction: number): Rect {
  const w = rect.w * fraction;
  const h = rect.h * fraction;
  return {
    x: rect.x + (rect.w - w) / 2,
    y: rect.y + (rect.h - h) / 2,
    w,
    h,
  };
}

/** Cell padding is depth-dependent so nested rectangles visibly nest
 *  rather than touching their parent. We shrink the padding with
 *  depth so deep nests don't lose all interior space. */
function cellPadding(depth: number, settings: LayoutSettings): number {
  // Base padding in world units, derived from the world radius so the
  // value scales when the world is resized via settings.
  const base = Math.max(2, settings.worldRadius * settings.siblingGap * 0.05);
  return base / Math.max(1, depth);
}

function leafPadding(settings: LayoutSettings): number {
  // Margin from the cell edge to the outermost leaf. Smaller than the
  // sibling-gap padding so leaves still fill the cell well.
  return Math.max(1, settings.ownedLeafFootprint * 0.25);
}

function orderByAdjacency(
  nodes: readonly ViewNode[],
  adjacency: ReadonlyMap<string, readonly string[]> | null,
): readonly ViewNode[] {
  if (!adjacency || nodes.length <= 2) {
    return nodes;
  }
  // BFS-style ordering: start from the highest-degree node, then
  // visit neighbours first. Connected pairs end up adjacent in the
  // grid, which keeps short edges short.
  const ids = new Set(nodes.map((n) => n.id));
  const byId = new Map(nodes.map((n) => [n.id, n] as const));
  const degree = (id: string): number => {
    const list = adjacency.get(id);
    if (!list) {
      return 0;
    }
    let d = 0;
    for (const o of list) {
      if (ids.has(o)) {
        d++;
      }
    }
    return d;
  };
  const sortedByDegree = [...nodes].sort((a, b) => degree(b.id) - degree(a.id));
  const visited = new Set<string>();
  const out: ViewNode[] = [];
  for (const seed of sortedByDegree) {
    if (visited.has(seed.id)) {
      continue;
    }
    const queue: string[] = [seed.id];
    visited.add(seed.id);
    while (queue.length > 0) {
      const id = queue.shift()!;
      const node = byId.get(id);
      if (node) {
        out.push(node);
      }
      const neighbours = adjacency.get(id);
      if (!neighbours) {
        continue;
      }
      // Visit neighbours in degree-descending order so hubs anchor.
      const localNeighbours = neighbours
        .filter((nb) => ids.has(nb) && !visited.has(nb))
        .sort((a, b) => degree(b) - degree(a));
      for (const nb of localNeighbours) {
        if (!visited.has(nb)) {
          visited.add(nb);
          queue.push(nb);
        }
      }
    }
  }
  return out;
}

/** Compute the leaf-count weight for every path: number of leaves
 *  ANYWHERE under that path (including its own owned leaves and any
 *  descendant clusters' leaves). This is the natural "size" of a
 *  cluster for a treemap. */
export function computeWeights(
  args: WeightArgs,
): Map<string, number> {
  const { roots, childrenOf, ownedNodes } = args;
  const cache = new Map<string, number>();
  const visit = (path: string): number => {
    const cached = cache.get(path);
    if (cached !== undefined) {
      return cached;
    }
    let total = ownedNodes.get(path)?.length ?? 0;
    const kids = childrenOf.get(path);
    if (kids) {
      for (const kid of kids) {
        total += visit(kid);
      }
    }
    // Every cluster carries at least 1 unit of weight so an
    // intermediate path with only sub-clusters still claims a
    // visible rectangle.
    const final = Math.max(1, total);
    cache.set(path, final);
    return final;
  };
  for (const root of roots) {
    visit(root);
  }
  return cache;
}

export type WeightArgs = {
  readonly roots: readonly string[];
  readonly childrenOf: ReadonlyMap<string, readonly string[]>;
  readonly ownedNodes: ReadonlyMap<string, readonly ViewNode[]>;
};
