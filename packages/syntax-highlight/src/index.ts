/**
 * @file Public API for @indexion/syntax-highlight.
 *
 * KGF-based syntax highlighting for code blocks.
 * Provides the React hook, component, and context for spec resolution.
 */

export { KgfCodeBlock, LANG_ALIASES } from "./kgf-code-block.tsx";
export {
  useKgfHighlight,
  type HighlightResult,
  type HighlightSegment,
} from "./use-kgf-highlight.ts";
export {
  KgfSpecProvider,
  useKgfSpecFetcher,
  type FetchKgfSpec,
} from "./highlight-context.ts";
