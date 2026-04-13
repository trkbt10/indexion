/**
 * @file Context for WikiContent environment-specific behavior.
 *
 * WikiContent needs to render links, source badges, and i18n labels
 * differently depending on the host environment (standalone wiki SPA
 * vs. VSCode webview). This context injects those behaviors.
 */

import { createContext, useContext } from "react";
import type { WikiSourceRef } from "@indexion/api-client";

export type WikiContentEnv = {
  /** Render a wiki:// internal link. Receives the page ID (wiki:// prefix stripped). */
  readonly renderWikiLink: (
    pageId: string,
    children: React.ReactNode,
  ) => React.JSX.Element;

  /** Render a source badge for a file reference. */
  readonly renderSourceBadge: (source: WikiSourceRef) => React.JSX.Element;

  /** Label for the "Relevant source files" collapsible. */
  readonly sourceFilesLabel: string;

  /**
   * Label for the "Related pages" section showing page.children.
   * When null, the section is hidden (e.g. wiki SPA where sidebar
   * navigation already shows the tree structure).
   */
  readonly relatedPagesLabel: string | null;
};

const WikiContentEnvContext = createContext<WikiContentEnv | null>(null);

export const WikiContentEnvProvider = WikiContentEnvContext.Provider;

export const useWikiContentEnv = (): WikiContentEnv => {
  const env = useContext(WikiContentEnvContext);
  if (!env) {
    throw new Error(
      "useWikiContentEnv must be used within a WikiContentEnvProvider",
    );
  }
  return env;
};
