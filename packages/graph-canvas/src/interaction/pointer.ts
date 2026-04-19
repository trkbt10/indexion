/**
 * @file Pointer state machine: drag / click / double-click.
 *
 * Owns only pointer-level state — the drag mode, click-vs-drag
 * threshold, and the timing/id comparison that detects a double
 * click. Higher-level effects (selection reducer, RAF kick, redraw)
 * are supplied by the caller via callbacks so this module has no
 * knowledge of React state or the renderer's selection layer.
 */

import type { ViewGraph, ViewNode } from "../types.ts";
import type { WebGlRenderer } from "../renderer/webgl/webgl-renderer.ts";
import { relaxNeighbours } from "../layout/index.ts";

export type PointerHandlersArgs = {
  readonly canvas: HTMLCanvasElement;
  readonly rendererRef: { current: WebGlRenderer | null };
  readonly graphRef: { current: ViewGraph | null };
  readonly hoverNodeRef: { current: ViewNode | null };
  readonly onHoverChange: () => void;
  readonly onDragMove: () => void;
  readonly onClick: (node: ViewNode | null, shift: boolean) => void;
  readonly onDoubleClick: (node: ViewNode | null) => void;
};

export type PointerHandle = {
  readonly dispose: () => void;
};

const CLICK_DISTANCE = 5;
const DOUBLE_CLICK_MS = 300;

export function installPointerHandlers(
  args: PointerHandlersArgs,
): PointerHandle {
  const {
    canvas,
    rendererRef,
    graphRef,
    hoverNodeRef,
    onHoverChange,
    onDragMove,
    onClick,
    onDoubleClick,
  } = args;

  type Mode = "idle" | "dragging-node" | "orbiting";
  let mode: Mode = "idle";
  let startX = 0;
  let startY = 0;
  let dragNode: ViewNode | null = null;
  let lastClickTs = 0;
  let lastClickNodeId: string | null = null;
  /** While the user is moving the camera (orbit / pan / zoom), the
   *  pointer crosses many nodes and edges that the user does NOT
   *  intend to inspect. Hover-driven highlight + redraw cycles in
   *  that window cause the screen to flash with each crossing.
   *  Suppressing hover updates while the pointer is held down — the
   *  same condition that gates orbit / pan in the renderer's
   *  OrbitControls — eliminates that flicker without losing hover
   *  responsiveness when the user is just moving the cursor. */
  let pointerDown = false;

  const canvasPoint = (e: PointerEvent) => {
    const rect = canvas.getBoundingClientRect();
    return { x: e.clientX - rect.left, y: e.clientY - rect.top };
  };

  const onPointerDown = (e: PointerEvent) => {
    const renderer = rendererRef.current;
    if (!renderer) {
      return;
    }
    const p = canvasPoint(e);
    startX = p.x;
    startY = p.y;
    pointerDown = true;
    const hit = renderer.pickNodeAt(p.x, p.y);
    if (hit) {
      dragNode = hit;
      mode = "dragging-node";
      renderer.setControlsEnabled(false);
      canvas.setPointerCapture(e.pointerId);
    } else {
      // Pointer is down without a node target → user is starting an
      // orbit / pan with OrbitControls. Hover updates are suppressed
      // for the duration so passing over nodes mid-orbit doesn't
      // strobe the highlight.
      mode = "orbiting";
    }
    // Clear any stale hover state at the start of any pointer-down
    // gesture so the highlight doesn't linger through the gesture.
    if (hoverNodeRef.current !== null) {
      hoverNodeRef.current = null;
      onHoverChange();
    }
  };

  const onPointerMove = (e: PointerEvent) => {
    const renderer = rendererRef.current;
    if (!renderer) {
      return;
    }
    const p = canvasPoint(e);
    if (mode === "dragging-node" && dragNode) {
      const world = renderer.screenToWorldOnPlane(p.x, p.y, dragNode);
      if (world) {
        dragNode.x = world.x;
        dragNode.y = world.y;
        dragNode.z = world.z;
        dragNode.pinned = true;
        const graph = graphRef.current;
        if (graph) {
          relaxNeighbours(graph, dragNode);
        }
        onDragMove();
      }
      return;
    }
    if (pointerDown) {
      // Pointer is held (orbit / pan / drag-node) — do not run hover
      // pickup. This is the flicker fix: without it, every pointer
      // move during an orbit hit-tests a new node, producing a
      // strobing highlight + redraw cycle.
      return;
    }
    const hit = renderer.pickNodeAt(p.x, p.y);
    if (hoverNodeRef.current?.id !== hit?.id) {
      hoverNodeRef.current = hit;
      onHoverChange();
    }
  };

  const dispatchClick = (node: ViewNode | null, shift: boolean, ts: number) => {
    const nodeId = node?.id ?? null;
    const elapsed = ts - lastClickTs;
    const isDouble = elapsed <= DOUBLE_CLICK_MS && lastClickNodeId === nodeId;
    lastClickTs = ts;
    lastClickNodeId = nodeId;
    if (isDouble) {
      onDoubleClick(node);
    } else {
      onClick(node, shift);
    }
  };

  const onPointerUp = (e: PointerEvent) => {
    const renderer = rendererRef.current;
    if (!renderer) {
      return;
    }
    const p = canvasPoint(e);
    const dist = Math.hypot(p.x - startX, p.y - startY);
    const wasClick = dist < CLICK_DISTANCE;
    const clicked = dragNode;
    mode = "idle";
    dragNode = null;
    pointerDown = false;
    renderer.setControlsEnabled(true);
    if (canvas.hasPointerCapture(e.pointerId)) {
      canvas.releasePointerCapture(e.pointerId);
    }
    if (wasClick) {
      dispatchClick(clicked, e.shiftKey, e.timeStamp);
    }
  };

  canvas.addEventListener("pointerdown", onPointerDown);
  canvas.addEventListener("pointermove", onPointerMove);
  canvas.addEventListener("pointerup", onPointerUp);
  canvas.addEventListener("pointercancel", onPointerUp);
  return {
    dispose: () => {
      canvas.removeEventListener("pointerdown", onPointerDown);
      canvas.removeEventListener("pointermove", onPointerMove);
      canvas.removeEventListener("pointerup", onPointerUp);
      canvas.removeEventListener("pointercancel", onPointerUp);
    },
  };
}
