/**
 * @file Process-wide mermaid render cache exposed via a React hook.
 *
 * Mermaid is dynamically imported on first use and its output is memoized
 * per source string. `useMermaidSvg` subscribes to the store so every caller
 * rendering the same code shares one render pass.
 */

import { useEffect, useMemo, useSyncExternalStore } from "react";
import { parseMermaidSvg, type SvgData } from "./svg-parser.ts";

type MermaidEntry =
  | { readonly state: "resolved"; readonly svg: SvgData }
  | { readonly state: "error"; readonly message: string };

const cache = new Map<string, MermaidEntry>();
const inflight = new Set<string>();
const listeners = new Set<() => void>();
let version = 0;

function subscribe(cb: () => void): () => void {
  listeners.add(cb);
  return () => listeners.delete(cb);
}

function getSnapshot(): number {
  return version;
}

function notify(): void {
  version++;
  for (const cb of listeners) {
    cb();
  }
}

function ensureRender(code: string): void {
  if (cache.has(code) || inflight.has(code)) {
    return;
  }
  inflight.add(code);
  render(code);
}

async function render(code: string): Promise<void> {
  try {
    const { default: mermaid } = await import("mermaid");
    mermaid.initialize({ startOnLoad: false, theme: "dark" });
    const { svg: raw } = await mermaid.render(
      `mermaid-${Math.random().toString(36).slice(2)}`,
      code,
    );
    cache.set(code, { state: "resolved", svg: parseMermaidSvg(raw) });
  } catch (err: unknown) {
    console.error("[mermaid-viewer] Render failed:", err);
    cache.set(code, { state: "error", message: String(err) });
  }
  inflight.delete(code);
  notify();
}

/** Lazy-load mermaid, render code to normalized SVG data. */
export function useMermaidSvg(code: string): {
  svg: SvgData | null;
  error: string | null;
} {
  const v = useSyncExternalStore(subscribe, getSnapshot, getSnapshot);

  useEffect(() => {
    if (code.trim()) {
      ensureRender(code);
    }
  }, [code]);

  return useMemo(() => {
    void v;
    if (!code.trim()) {
      return { svg: null, error: null };
    }
    const entry = cache.get(code);
    if (!entry) {
      return { svg: null, error: null };
    }
    switch (entry.state) {
      case "resolved":
        return { svg: entry.svg, error: null };
      case "error":
        return { svg: null, error: entry.message };
    }
  }, [code, v]);
}
