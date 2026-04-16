/**
 * @file Camera transform: world ↔ screen coordinate conversion,
 * cursor-centered zoom, pan, and fit-to-view.
 */

import type { Camera, Vec2, ViewNode } from "../types.ts";

/** Convert world coordinates to screen coordinates. */
export function worldToScreen(camera: Camera, world: Vec2): Vec2 {
  return {
    x: world.x * camera.scale + camera.x,
    y: world.y * camera.scale + camera.y,
  };
}

/** Convert screen coordinates to world coordinates. */
export function screenToWorld(camera: Camera, screen: Vec2): Vec2 {
  return {
    x: (screen.x - camera.x) / camera.scale,
    y: (screen.y - camera.y) / camera.scale,
  };
}

/**
 * Zoom centered on the given screen-space cursor position.
 * The world point under the cursor stays fixed after zoom.
 */
export function zoom(camera: Camera, cursorScreen: Vec2, delta: number): void {
  const worldBefore = screenToWorld(camera, cursorScreen);
  const factor = 1 - delta * 0.001;
  camera.scale = clamp(camera.scale * factor, camera.minScale, camera.maxScale);
  // Adjust translation so cursor stays over the same world point
  camera.x = cursorScreen.x - worldBefore.x * camera.scale;
  camera.y = cursorScreen.y - worldBefore.y * camera.scale;
}

/** Pan the camera by a screen-space delta. */
export function pan(camera: Camera, dx: number, dy: number): void {
  camera.x += dx;
  camera.y += dy;
}

/**
 * Calculate and apply the transform that fits all given nodes
 * within the viewport with the specified padding.
 */
export function fitToView(
  camera: Camera,
  nodes: readonly ViewNode[],
  canvasWidth: number,
  canvasHeight: number,
  padding: number = 40,
): void {
  if (nodes.length === 0) return;

  let x0 = Infinity;
  let y0 = Infinity;
  let x1 = -Infinity;
  let y1 = -Infinity;
  for (const n of nodes) {
    if (n.x < x0) x0 = n.x;
    if (n.y < y0) y0 = n.y;
    if (n.x > x1) x1 = n.x;
    if (n.y > y1) y1 = n.y;
  }

  const bboxW = x1 - x0 || 1;
  const bboxH = y1 - y0 || 1;
  const centerX = (x0 + x1) / 2;
  const centerY = (y0 + y1) / 2;

  const availW = canvasWidth - padding * 2;
  const availH = canvasHeight - padding * 2;
  camera.scale = clamp(Math.min(availW / bboxW, availH / bboxH), camera.minScale, camera.maxScale);
  camera.x = canvasWidth / 2 - centerX * camera.scale;
  camera.y = canvasHeight / 2 - centerY * camera.scale;
}

/** Get the visible world-space bounding box for culling. */
export function getVisibleBounds(
  camera: Camera,
  canvasWidth: number,
  canvasHeight: number,
): { x0: number; y0: number; x1: number; y1: number } {
  const topLeft = screenToWorld(camera, { x: 0, y: 0 });
  const bottomRight = screenToWorld(camera, { x: canvasWidth, y: canvasHeight });
  return { x0: topLeft.x, y0: topLeft.y, x1: bottomRight.x, y1: bottomRight.y };
}

function clamp(value: number, min: number, max: number): number {
  return Math.max(min, Math.min(max, value));
}
