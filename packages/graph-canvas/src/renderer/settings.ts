/**
 * @file Default RenderSettings + deep-merge helper.
 *
 * Every visual tuning value flows through this module. The renderer
 * never reads hard-coded constants directly; callers can override any
 * subset of the defaults via the component's `renderSettings` prop.
 *
 * Pure module, no side effects.
 */

import type { DeepPartial, RenderSettings } from "../types.ts";

export const DEFAULT_RENDER_SETTINGS: RenderSettings = {
  node: {
    // Leaf nodes are tiny dots; hubs scale up ~7× so the high-degree
    // nodes inside a dense cluster pop out. Pixel target is the
    // screen-space radius, back-solved to world radius per frame,
    // so nodes stay legible at any zoom level.
    pixelTarget: 2.4,
    hubScale: 7,
    sphereSegments: { width: 14, height: 10 },
    fadeRadius: 2.2,
    cullRadius: 0.8,
    // Interior LOD — nodes inside a tightly-projected cluster would
    // otherwise pack into a solid gray disc. Below `interiorFadeLoPx`
    // of projected cluster radius they're hidden; they fade in
    // smoothly up to `interiorFadeHiPx`.
    interiorFadeLoPx: 32,
    interiorFadeHiPx: 96,
  },
  shell: {
    // Ring (silhouette circle) resolution. 64 segments renders a
    // smooth circle at any projected size.
    sphereSegments: { width: 64, height: 1 },
    fadeInPx: 14,
    peakLoPx: 70,
    peakHiPx: 900,
    fadeOutPx: 2400,
    opacityPeak: 0.22,
    ringWidthFrac: 0.008,
    targetBandPx: 2.5,
  },
  edge: {
    linewidth: 1.0,
    opacity: 0.18,
    bezierSegments: 12,
    bundleStrength: 0.65,
    // Short = bottom 40%, Long = top 80% of length distribution.
    shortQuantile: 0.4,
    longQuantile: 0.85,
    // A ghost visibility for long edges so relationships never fully
    // disappear; small enough that local structure dominates.
    longEdgeFloor: 0.1,
  },
  camera: {
    fov: 50,
    near: 0.01,
    far: 50000,
    minDistance: 0.01,
    maxDistance: 20000,
    zoomPerTick: 0.12,
    targetFollow: 0.55,
  },
  layout: {
    worldRadius: 1000,
    siblingGap: 0.22,
    minClusterFraction: 0.08,
    innerFraction: 0.45,
    ownedLeafFootprint: 32,
    intraRelax: {
      // Tuned so relaxation brings connected pairs together without
      // overwhelming the kind-band's radial distribution. Lower
      // iterations + mild repulsion preserve the initial volume
      // spread while still pulling call-clusters closer.
      iterations: 12,
      attraction: 0.08,
      repulsion: 30,
      damping: 0.65,
      maxStep: 0.04,
    },
  },
};

/** Deep-merge the user's partial override over the defaults. Only
 *  plain objects recurse; arrays & primitives replace. This keeps
 *  callers' overrides typed and nothing leaks through. */
export function resolveRenderSettings(
  override: DeepPartial<RenderSettings> | undefined,
): RenderSettings {
  if (!override) {
    return DEFAULT_RENDER_SETTINGS;
  }
  return deepMerge(DEFAULT_RENDER_SETTINGS, override) as RenderSettings;
}

function deepMerge<T>(base: T, patch: DeepPartial<T>): T {
  if (!isPlainObject(base) || !isPlainObject(patch)) {
    return (patch as T) ?? base;
  }
  const result: Record<string, unknown> = {
    ...(base as Record<string, unknown>),
  };
  for (const key of Object.keys(patch as object)) {
    const b = (base as Record<string, unknown>)[key];
    const p = (patch as Record<string, unknown>)[key];
    if (p === undefined) {
      continue;
    }
    if (isPlainObject(b) && isPlainObject(p)) {
      result[key] = deepMerge(
        b as Record<string, unknown>,
        p as DeepPartial<Record<string, unknown>>,
      );
    } else {
      result[key] = p;
    }
  }
  return result as T;
}

function isPlainObject(value: unknown): value is Record<string, unknown> {
  if (value === null || typeof value !== "object") {
    return false;
  }
  const proto = Object.getPrototypeOf(value);
  return proto === Object.prototype || proto === null;
}
