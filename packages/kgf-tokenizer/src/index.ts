/**
 * @file KGF tokenizer — stub implementation.
 *
 * This is the default export when `moon build --target js` hasn't been run.
 * Returns an empty token array, causing syntax highlighting to fall through
 * to plain text rendering.
 *
 * When the MoonBit build artifact exists, consumer bundlers should alias
 * `@indexion/kgf-tokenizer` to the artifact path to get real tokenization:
 *
 *   _build/js/debug/build/cmd/kgf-tokenizer/kgf-tokenizer.js
 *
 * The MoonBit source lives at `cmd/kgf-tokenizer/main.mbt` and exports
 * the same `tokenize(spec_text, source) -> JSON string` signature.
 */

/**
 * Tokenize source code using a KGF spec string.
 * Returns a JSON string: `[{"kind":"...","text":"...","pos":N}, ...]`
 */
export function tokenize(_spec_text: string, _source: string): string {
  return "[]";
}
