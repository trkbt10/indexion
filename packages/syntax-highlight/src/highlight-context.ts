/**
 * @file Context for KGF spec resolution.
 *
 * The syntax highlighter needs to fetch KGF specs to tokenize code.
 * How specs are fetched depends on the host environment:
 *   - Wiki SPA: HTTP fetch from /api/kgf/specs/:lang
 *   - VSCode webview: message passing through extension host
 *
 * This context lets the host inject spec resolution.
 */

import { createContext, useContext } from "react";

/**
 * Fetch a KGF spec by language name.
 * Returns the spec content string, or null if unavailable.
 */
export type FetchKgfSpec = (lang: string) => Promise<string | null>;

const KgfSpecContext = createContext<FetchKgfSpec | null>(null);

export const KgfSpecProvider = KgfSpecContext.Provider;

export const useKgfSpecFetcher = (): FetchKgfSpec | null =>
  useContext(KgfSpecContext);
