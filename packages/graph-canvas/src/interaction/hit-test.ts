/**
 * @file Grid spatial hash for node hit testing.
 */

import type { ViewNode } from "../types.ts";

export type SpatialHash = {
  rebuild(nodes: readonly ViewNode[]): void;
  queryPoint(worldX: number, worldY: number, maxRadius: number): ViewNode | null;
};

export function createSpatialHash(cellSize: number = 40): SpatialHash {
  return new GridSpatialHash(cellSize);
}

class GridSpatialHash implements SpatialHash {
  private readonly cellSize: number;
  private readonly cells = new Map<string, ViewNode[]>();

  constructor(cellSize: number) {
    this.cellSize = Math.max(1, cellSize);
  }

  rebuild(nodes: readonly ViewNode[]): void {
    this.cells.clear();
    for (const node of nodes) {
      const key = this.keyForWorld(node.x, node.y);
      const bucket = this.cells.get(key);
      if (bucket) {
        bucket.push(node);
      } else {
        this.cells.set(key, [node]);
      }
    }
  }

  queryPoint(worldX: number, worldY: number, maxRadius: number): ViewNode | null {
    const col = Math.floor(worldX / this.cellSize);
    const row = Math.floor(worldY / this.cellSize);
    const maxDistSq = maxRadius * maxRadius;
    let nearest: ViewNode | null = null;
    let nearestDistSq = maxDistSq;

    for (let dc = -1; dc <= 1; dc++) {
      for (let dr = -1; dr <= 1; dr++) {
        const bucket = this.cells.get(this.key(col + dc, row + dr));
        if (!bucket) continue;
        for (const node of bucket) {
          const dx = node.x - worldX;
          const dy = node.y - worldY;
          const distSq = dx * dx + dy * dy;
          if (distSq <= nearestDistSq) {
            nearest = node;
            nearestDistSq = distSq;
          }
        }
      }
    }

    return nearest;
  }

  private keyForWorld(worldX: number, worldY: number): string {
    return this.key(Math.floor(worldX / this.cellSize), Math.floor(worldY / this.cellSize));
  }

  private key(col: number, row: number): string {
    return `${col},${row}`;
  }
}
