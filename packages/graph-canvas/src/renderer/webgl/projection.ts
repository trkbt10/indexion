/**
 * @file Pure projection / interpolation primitives.
 *
 * No three.js types and no scene state. These are the maths the layers
 * use to translate world units into screen pixels and to fade values
 * smoothly across thresholds. Kept here so every layer reads from a
 * single source of truth and tests can pin them down without spinning
 * up a renderer.
 */

import type { PerspectiveCamera } from "three";

/** World-radius → screen-pixel multiplier for the *vertical* viewport.
 *  At the camera's focal distance d, a world radius r maps to a screen
 *  radius `r × pixelScale / d`. Used everywhere we back-solve a world
 *  size from a desired pixel size. */
export function pixelScale(camera: PerspectiveCamera, height: number): number {
  const halfFov = (camera.fov * Math.PI) / 360;
  return height / (2 * Math.tan(halfFov));
}

/** Standard smoothstep — 3t² − 2t³. C¹-continuous ramp from 0 at
 *  `edge0` to 1 at `edge1`, zero-slope at both ends so the fade has
 *  no visible kink. Values outside the range are clamped. */
export function smoothstep(
  edge0: number,
  edge1: number,
  value: number,
): number {
  if (edge1 === edge0) {
    return value < edge0 ? 0 : 1;
  }
  const t = clamp((value - edge0) / (edge1 - edge0), 0, 1);
  return t * t * (3 - 2 * t);
}

export function clamp(value: number, min: number, max: number): number {
  if (value < min) {
    return min;
  }
  if (value > max) {
    return max;
  }
  return value;
}

export function easeOutCubic(t: number): number {
  const u = 1 - t;
  return 1 - u * u * u;
}

/** Smooth 1→0 ramp that classifies edges by length. Shorter than
 *  `shortThreshold` → 1 (fully local). Longer than `longThreshold` →
 *  0 (cross-scene). Linear fade between. */
export function lengthProximity(
  length: number,
  shortThreshold: number,
  longThreshold: number,
): number {
  if (length <= shortThreshold) {
    return 1;
  }
  if (length >= longThreshold) {
    return 0;
  }
  return 1 - (length - shortThreshold) / (longThreshold - shortThreshold);
}

/**
 * Continuous [0, 1] value that fades static labels in between the
 * overview zoom and the detail zoom levels. Mirrors the canvas2d
 * renderer's `detailFactor` so both backends feel the same.
 */
export function detailFactorFromZoom(zoom: number): number {
  return smoothstep(0.9, 1.4, zoom);
}
