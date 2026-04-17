/**
 * @file Parse mermaid's raw SVG output into normalized dimensions.
 *
 * Ensures a viewBox exists, extracts intrinsic width/height, and strips
 * mermaid's injected inline style (which sets max-width and breaks scaling).
 */

export type SvgData = {
  html: string;
  w: number;
  h: number;
};

const DEFAULT_SIZE = { w: 800, h: 600 };

export function parseMermaidSvg(raw: string): SvgData {
  const doc = new DOMParser().parseFromString(raw, "image/svg+xml");
  const el = doc.querySelector("svg");
  if (!el) {
    return { html: raw, ...DEFAULT_SIZE };
  }

  let { w, h } = extractViewBoxSize(el);
  if (w <= 0 || h <= 0) {
    w = parseFloat(el.getAttribute("width") ?? String(DEFAULT_SIZE.w));
    h = parseFloat(el.getAttribute("height") ?? String(DEFAULT_SIZE.h));
    el.setAttribute("viewBox", `0 0 ${w} ${h}`);
  }

  el.setAttribute("width", String(w));
  el.setAttribute("height", String(h));
  el.removeAttribute("style");

  return { html: el.outerHTML, w, h };
}

function extractViewBoxSize(el: SVGSVGElement): { w: number; h: number } {
  const vb = el.getAttribute("viewBox");
  if (!vb) {
    return { w: 0, h: 0 };
  }
  const parts = vb.split(/[\s,]+/).map(Number);
  if (parts.length === 4 && parts[2]! > 0 && parts[3]! > 0) {
    return { w: parts[2]!, h: parts[3]! };
  }
  return { w: 0, h: 0 };
}
