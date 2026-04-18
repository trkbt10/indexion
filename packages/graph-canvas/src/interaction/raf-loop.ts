/**
 * @file Tick-on-motion requestAnimationFrame loop for the viewport.
 *
 * The camera is not animated at 60Hz — it only moves when the user
 * drags, zooms, or a fit/focus tween is active. This loop keeps
 * ticking while motion is visible, then parks itself when the camera
 * signature has been stable for `QUIET_FRAMES` consecutive frames.
 * `kick()` restarts it when new motion arrives (e.g. OrbitControls
 * change event, new drag). Idle GPU usage stays at zero.
 */

import type { WebGlRenderer } from "../renderer/webgl/webgl-renderer.ts";

export type RafHandle = {
  readonly kick: () => void;
  readonly stop: () => void;
};

const QUIET_FRAMES = 4;

export function startRafLoop(rendererRef: {
  current: WebGlRenderer | null;
}): RafHandle {
  let stopped = false;
  let rafId = 0;
  let quietFrames = 0;
  const loop = () => {
    if (stopped) {
      return;
    }
    const renderer = rendererRef.current;
    if (!renderer) {
      rafId = 0;
      return;
    }
    const prev = renderer.getCameraSignature();
    renderer.tickControls();
    renderer.render();
    const next = renderer.getCameraSignature();
    if (next === prev && !renderer.hasActiveTween()) {
      quietFrames++;
    } else {
      quietFrames = 0;
    }
    if (quietFrames >= QUIET_FRAMES) {
      rafId = 0;
      return;
    }
    rafId = requestAnimationFrame(loop);
  };
  const kick = () => {
    if (stopped || rafId !== 0) {
      return;
    }
    quietFrames = 0;
    rafId = requestAnimationFrame(loop);
  };
  const stop = () => {
    stopped = true;
    if (rafId !== 0) {
      cancelAnimationFrame(rafId);
      rafId = 0;
    }
  };
  kick();
  return { kick, stop };
}
