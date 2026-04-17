/**
 * @file Fit-to-width hook for the inline mermaid preview.
 *
 * Measures container width, computes display height from the SVG aspect
 * ratio, and drives react-zoom-pan-pinch via setTransform to scale the
 * diagram. `ready` tracks whether the current svg has been fitted — the
 * caller uses it to hide the container until the first fit completes so
 * users never see an unscaled flash.
 *
 * Version counters: `svgVersionRef` increments when the svg identity
 * changes (a new diagram is not yet fitted); `fitVersion` increments when
 * fitToWidth finishes. ready = fitVersion >= svgVersion.
 */

import { useCallback, useEffect, useRef, useState } from "react";
import type { ReactZoomPanPinchRef } from "react-zoom-pan-pinch";
import type { SvgData } from "./svg-parser.ts";

const MIN_HEIGHT = 120;
const MAX_VH = 0.8;

export function useFitToWidth(svg: SvgData | null): {
  outerRef: React.RefObject<HTMLDivElement | null>;
  transformRef: React.RefObject<ReactZoomPanPinchRef | null>;
  displayHeight: number;
  fitToWidth: () => void;
  ready: boolean;
} {
  const outerRef = useRef<HTMLDivElement>(null);
  const transformRef = useRef<ReactZoomPanPinchRef>(null);
  const [displayHeight, setDisplayHeight] = useState(300);
  const prevWidthRef = useRef(0);

  const svgVersionRef = useRef(0);
  const [fitVersion, setFitVersion] = useState(0);

  // svg identity is the intentional trigger — tracked via ref, not deps
  const prevSvgRef = useRef(svg);
  if (prevSvgRef.current !== svg) {
    prevSvgRef.current = svg;
    svgVersionRef.current++;
  }
  const currentSvgVersion = svgVersionRef.current;

  const ready = fitVersion >= currentSvgVersion;

  const fitToWidth = useCallback(() => {
    const el = outerRef.current;
    if (!el || !svg) {
      return;
    }
    const cw = el.clientWidth;
    if (cw <= 0) {
      return;
    }

    const scale = cw / svg.w;
    const maxH = window.innerHeight * MAX_VH;
    const containerH = Math.max(Math.min(svg.h * scale, maxH), MIN_HEIGHT);
    setDisplayHeight(containerH);

    // setDisplayHeight triggers re-render → wait for DOM update.
    // Double-rAF: first waits for React commit, second for browser layout.
    const targetVersion = svgVersionRef.current;
    requestAnimationFrame(() => {
      requestAnimationFrame(() => {
        const ref = transformRef.current;
        if (!ref) {
          return;
        }
        const scaledH = svg.h * scale;
        const y = scaledH < containerH ? (containerH - scaledH) / 2 : 0;
        ref.setTransform(0, y, scale, 0);
        setFitVersion(targetVersion);
      });
    });
  }, [svg]);

  // Observe width only — observing height would feed displayHeight updates
  // back into fitToWidth and loop.
  useEffect(() => {
    const el = outerRef.current;
    if (!el || !svg) {
      return;
    }
    const ro = new ResizeObserver((entries) => {
      for (const entry of entries) {
        const w = entry.contentRect.width;
        if (Math.abs(w - prevWidthRef.current) > 1) {
          prevWidthRef.current = w;
          fitToWidth();
        }
      }
    });
    ro.observe(el);
    fitToWidth();
    return () => ro.disconnect();
  }, [svg, fitToWidth]);

  return { outerRef, transformRef, displayHeight, fitToWidth, ready };
}
