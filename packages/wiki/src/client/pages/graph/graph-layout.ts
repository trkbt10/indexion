import type { FolderNode, Box3D, Size3 } from "./graph-types.ts";

const PAD = 0.4;
const GAP = 0.3;
const LEAF_W = 2.8;
const LEAF_H = 0.6;
const LEAF_D = 1.2;
export const FLOOR_H = 0.06;
export const LABEL_ZONE = 0.9;
const CONTAINER_EXTRA_H = 0.3;

export const gridPack = (childSizes: Size3[]): number[][] => {
  const n = childSizes.length;
  if (n <= 2) {
    return [childSizes.map((_, i) => i)];
  }
  let bestCols = n;
  let bestRatio = Infinity;
  for (let cols = 1; cols <= n; cols++) {
    const rows = Math.ceil(n / cols);
    let maxRowW = 0;
    let totalD = 0;
    for (let r = 0; r < rows; r++) {
      let rowW = 0;
      let rowD = 0;
      for (let c = 0; c < cols && r * cols + c < n; c++) {
        rowW += childSizes[r * cols + c].w + (c > 0 ? GAP : 0);
        rowD = Math.max(rowD, childSizes[r * cols + c].d);
      }
      maxRowW = Math.max(maxRowW, rowW);
      totalD += rowD + (r > 0 ? GAP : 0);
    }
    const ratio =
      maxRowW > 0 && totalD > 0
        ? Math.max(maxRowW / totalD, totalD / maxRowW)
        : Infinity;
    if (ratio < bestRatio) {
      bestRatio = ratio;
      bestCols = cols;
    }
  }
  const rows: number[][] = [];
  for (let i = 0; i < n; i += bestCols) {
    rows.push(childSizes.slice(i, i + bestCols).map((_, j) => i + j));
  }
  return rows;
};

export const computeLayout = (
  nodes: Map<string, FolderNode>,
  roots: string[],
): Map<string, Box3D> => {
  const result = new Map<string, Box3D>();
  const sizeCache = new Map<string, Size3>();
  const measure = (id: string): Size3 => {
    if (sizeCache.has(id)) {
      return sizeCache.get(id)!;
    }
    const node = nodes.get(id)!;
    if (node.children.length === 0) {
      const nFiles = Math.max(node.files.length, 1);
      const cols = Math.max(1, Math.ceil(Math.sqrt(nFiles)));
      const rows = Math.ceil(nFiles / cols);
      const w = Math.max(LEAF_W, cols * 1.8 + PAD * 2);
      const d = Math.max(LEAF_D, rows * 1.4 + PAD * 2);
      const s = { w, h: LEAF_H, d };
      sizeCache.set(id, s);
      return s;
    }
    const childSizes = node.children.map(measure);
    const rows = gridPack(childSizes);
    let maxRowW = 0;
    let totalD = 0;
    let maxH = 0;
    for (const row of rows) {
      let rowW = 0;
      let rowD = 0;
      for (let c = 0; c < row.length; c++) {
        rowW += childSizes[row[c]].w + (c > 0 ? GAP : 0);
        rowD = Math.max(rowD, childSizes[row[c]].d);
        maxH = Math.max(maxH, childSizes[row[c]].h);
      }
      maxRowW = Math.max(maxRowW, rowW);
      totalD += rowD + GAP;
    }
    const s = {
      w: maxRowW + PAD * 2,
      h: maxH + FLOOR_H + CONTAINER_EXTRA_H,
      d: totalD + PAD + LABEL_ZONE,
    };
    sizeCache.set(id, s);
    return s;
  };
  const layout = (id: string, pos: { x: number; y: number; z: number }) => {
    const { x, y, z } = pos;
    const node = nodes.get(id)!;
    const size = measure(id);
    result.set(id, { x, y, z, w: size.w, h: size.h, d: size.d });
    if (node.children.length === 0) {
      return;
    }
    const childSizes = node.children.map(measure);
    const rows = gridPack(childSizes);
    const childY = y + FLOOR_H;
    let curZ = z + LABEL_ZONE + PAD;
    for (const row of rows) {
      let rowW = 0;
      let rowD = 0;
      for (let c = 0; c < row.length; c++) {
        rowW += childSizes[row[c]].w + (c > 0 ? GAP : 0);
        rowD = Math.max(rowD, childSizes[row[c]].d);
      }
      let curX = x + (size.w - rowW) / 2;
      for (const idx of row) {
        layout(node.children[idx], { x: curX, y: childY, z: curZ });
        curX += childSizes[idx].w + GAP;
      }
      curZ += rowD + GAP;
    }
  };
  const rootSizes = roots.map(measure);
  const rootRows = gridPack(rootSizes);
  let curZ = 0;
  for (const row of rootRows) {
    let rowW = 0;
    let rowD = 0;
    for (let c = 0; c < row.length; c++) {
      rowW += rootSizes[row[c]].w + (c > 0 ? 2.0 : 0);
      rowD = Math.max(rowD, rootSizes[row[c]].d);
    }
    let curX = -rowW / 2;
    for (const idx of row) {
      layout(roots[idx], { x: curX, y: 0, z: curZ });
      curX += rootSizes[idx].w + 2.0;
    }
    curZ += rowD + 2.0;
  }
  return result;
};
