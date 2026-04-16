/**
 * @file Unified pointer and wheel interaction manager.
 */

import type { Camera, Vec2, ViewNode } from "../types.ts";
import { pan, screenToWorld, zoom } from "../renderer/camera.ts";
import type { SpatialHash } from "./hit-test.ts";

export type PointerCallbacks = {
  readonly onNodeClick?: (node: ViewNode, shift: boolean) => void;
  readonly onNodeDoubleClick?: (node: ViewNode, shift: boolean) => void;
  readonly onBackgroundClick?: (shift: boolean) => void;
  readonly onBackgroundDoubleClick?: (shift: boolean) => void;
  readonly onDrag?: (node: ViewNode) => void;
  readonly onHover?: (node: ViewNode | null) => void;
  readonly onReheat?: () => void;
  readonly requestRedraw: () => void;
};

export type PointerHandler = {
  attach(): void;
  detach(): void;
};

type PointerMode = "idle" | "panning" | "dragging";

type PointerState = {
  mode: PointerMode;
  startScreen: Vec2;
  lastScreen: Vec2;
  dragNode: ViewNode | null;
  hoverNode: ViewNode | null;
  lastClickTime: number;
  lastClickNodeId: string | null;
};

const CLICK_DISTANCE = 5;
const DOUBLE_CLICK_MS = 300;
const HIT_RADIUS_SCREEN = 14;

export function createPointerHandler(
  canvas: HTMLCanvasElement,
  camera: Camera,
  spatialHash: SpatialHash,
  callbacks: PointerCallbacks,
): PointerHandler {
  const state: PointerState = {
    mode: "idle",
    startScreen: { x: 0, y: 0 },
    lastScreen: { x: 0, y: 0 },
    dragNode: null,
    hoverNode: null,
    lastClickTime: 0,
    lastClickNodeId: null,
  };

  const getNodeAt = (screen: Vec2): ViewNode | null => {
    const world = screenToWorld(camera, screen);
    return spatialHash.queryPoint(world.x, world.y, HIT_RADIUS_SCREEN / camera.scale);
  };

  const setHover = (node: ViewNode | null): void => {
    if (state.hoverNode?.id === node?.id) return;
    state.hoverNode = node;
    callbacks.onHover?.(node);
    callbacks.requestRedraw();
  };

  const onPointerDown = (event: PointerEvent): void => {
    const screen = eventToCanvasPoint(canvas, event);
    const node = getNodeAt(screen);
    state.startScreen = screen;
    state.lastScreen = screen;
    state.dragNode = node;
    state.mode = node ? "dragging" : "panning";
    if (node) {
      node.pinned = true;
    }
    canvas.setPointerCapture(event.pointerId);
    callbacks.requestRedraw();
  };

  const onPointerMove = (event: PointerEvent): void => {
    const screen = eventToCanvasPoint(canvas, event);
    if (state.mode === "dragging" && state.dragNode) {
      const world = screenToWorld(camera, screen);
      state.dragNode.x = world.x;
      state.dragNode.y = world.y;
      state.dragNode.vx = 0;
      state.dragNode.vy = 0;
      callbacks.onDrag?.(state.dragNode);
      callbacks.onReheat?.();
      callbacks.requestRedraw();
    }
    if (state.mode === "panning") {
      pan(camera, screen.x - state.lastScreen.x, screen.y - state.lastScreen.y);
      callbacks.requestRedraw();
    }
    state.lastScreen = screen;
    setHover(getNodeAt(screen));
  };

  const onPointerUp = (event: PointerEvent): void => {
    const screen = eventToCanvasPoint(canvas, event);
    const wasClick = distance(state.startScreen, screen) < CLICK_DISTANCE;
    const clickedNode = state.dragNode ?? getNodeAt(screen);
    state.mode = "idle";
    state.dragNode = null;
    if (canvas.hasPointerCapture(event.pointerId)) {
      canvas.releasePointerCapture(event.pointerId);
    }

    if (wasClick) {
      dispatchClick(clickedNode, event.shiftKey, event.timeStamp);
    }
    callbacks.requestRedraw();
  };

  const dispatchClick = (node: ViewNode | null, shift: boolean, timeStamp: number): void => {
    const nodeId = node?.id ?? null;
    const elapsed = timeStamp - state.lastClickTime;
    const isDouble = elapsed <= DOUBLE_CLICK_MS && state.lastClickNodeId === nodeId;
    state.lastClickTime = timeStamp;
    state.lastClickNodeId = nodeId;

    if (isDouble) {
      if (node) callbacks.onNodeDoubleClick?.(node, shift);
      if (!node) callbacks.onBackgroundDoubleClick?.(shift);
      return;
    }

    if (node) {
      callbacks.onNodeClick?.(node, shift);
    } else {
      callbacks.onBackgroundClick?.(shift);
    }
  };

  const onWheel = (event: WheelEvent): void => {
    event.preventDefault();
    zoom(camera, eventToCanvasPoint(canvas, event), event.deltaY);
    callbacks.requestRedraw();
  };

  const attach = (): void => {
    canvas.addEventListener("pointerdown", onPointerDown);
    canvas.addEventListener("pointermove", onPointerMove);
    canvas.addEventListener("pointerup", onPointerUp);
    canvas.addEventListener("pointercancel", onPointerUp);
    canvas.addEventListener("wheel", onWheel, { passive: false });
  };

  const detach = (): void => {
    canvas.removeEventListener("pointerdown", onPointerDown);
    canvas.removeEventListener("pointermove", onPointerMove);
    canvas.removeEventListener("pointerup", onPointerUp);
    canvas.removeEventListener("pointercancel", onPointerUp);
    canvas.removeEventListener("wheel", onWheel);
  };

  return { attach, detach };
}

function eventToCanvasPoint(canvas: HTMLCanvasElement, event: MouseEvent): Vec2 {
  const rect = canvas.getBoundingClientRect();
  return {
    x: event.clientX - rect.left,
    y: event.clientY - rect.top,
  };
}

function distance(a: Vec2, b: Vec2): number {
  return Math.hypot(a.x - b.x, a.y - b.y);
}
