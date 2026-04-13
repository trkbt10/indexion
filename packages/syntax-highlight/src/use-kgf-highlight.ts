/**
 * @file Hook that fetches a KGF spec and tokenizes code.
 *
 * Specs are cached per language so repeat renders don't re-fetch.
 * The spec fetcher is injected via KgfSpecProvider context.
 * If no provider is present, falls back to "unsupported" (plain text).
 */

import { useEffect, useState } from "react";
import { tokenize } from "@indexion/kgf-tokenizer";
import { useKgfSpecFetcher } from "./highlight-context.ts";

type Tok = { kind: string; text: string; pos: number };

const specCache = new Map<string, string>();

/** FNV-1a hash → deterministic HSL color for a token kind (dark theme). */
function colorForKind(kind: string): string {
  const FNV_OFFSET = 0x811c9dc5;
  const FNV_PRIME = 0x01000193;
  let h = FNV_OFFSET;
  for (let i = 0; i < kind.length; i++) {
    h = Math.imul(h ^ kind.charCodeAt(i), FNV_PRIME) >>> 0;
  }
  const hue = h % 360;
  const sat = 55 + ((h >>> 8) % 25);
  const light = 55 + ((h >>> 16) % 15);
  return `hsl(${hue},${sat}%,${light}%)`;
}

export type HighlightSegment = {
  readonly text: string;
  readonly color: string | null;
};

export type HighlightResult = {
  readonly status: "idle" | "loading" | "ready" | "unsupported";
  readonly segments: ReadonlyArray<HighlightSegment>;
};

/**
 * Given a language name and source code, returns colored segments.
 * Falls back to unstyled text when the spec isn't available or
 * no KgfSpecProvider is present.
 */
export function useKgfHighlight(
  lang: string | null,
  code: string,
): HighlightResult {
  const fetchSpec = useKgfSpecFetcher();

  const [result, setResult] = useState<HighlightResult>({
    status: "idle",
    segments: [{ text: code, color: null }],
  });

  useEffect(() => {
    if (!lang || !fetchSpec) {
      setResult({
        status: "unsupported",
        segments: [{ text: code, color: null }],
      });
      return;
    }

    // Check cache first
    const cached = specCache.get(lang);
    if (cached !== undefined) {
      setResult(tokenizeToResult(cached, code));
      return;
    }

    let cancelled = false;
    setResult((prev) => ({ ...prev, status: "loading" }));

    fetchSpec(lang).then((spec) => {
      if (cancelled) {
        return;
      }
      if (!spec) {
        setResult({
          status: "unsupported",
          segments: [{ text: code, color: null }],
        });
        return;
      }
      specCache.set(lang, spec);
      setResult(tokenizeToResult(spec, code));
    });

    return () => {
      cancelled = true;
    };
  }, [lang, code, fetchSpec]);

  return result;
}

function tokenizeToResult(spec: string, code: string): HighlightResult {
  const raw = tokenize(spec, code);
  const tokens: Tok[] = JSON.parse(raw);
  const segments: Array<HighlightSegment> = [];
  let lastEnd = 0;
  for (const tok of tokens) {
    if (tok.pos > lastEnd) {
      segments.push({ text: code.slice(lastEnd, tok.pos), color: null });
    }
    segments.push({ text: tok.text, color: colorForKind(tok.kind) });
    lastEnd = tok.pos + tok.text.length;
  }
  if (lastEnd < code.length) {
    segments.push({ text: code.slice(lastEnd), color: null });
  }
  return { status: "ready", segments };
}
