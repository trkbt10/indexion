/**
 * @file Default WikiContentEnv for the standalone wiki SPA.
 *
 * Uses react-router Links, lucide SourceBadge, and i18n dict.
 * Provides KGF spec fetching via the wiki SPA's HTTP client.
 */

import { useCallback, useMemo } from "react";
import { Link } from "react-router";
import { KgfSpecProvider } from "@indexion/syntax-highlight";
import { SourceBadge } from "./source-badge.tsx";
import { WikiContentEnvProvider, type WikiContentEnv } from "./wiki-content-context.tsx";
import { useDict } from "../../../i18n/index.ts";
import { client } from "../../../lib/client.ts";

type Props = {
  readonly children: React.ReactNode;
};

export const WikiContentWebEnv = ({ children }: Props): React.JSX.Element => {
  const d = useDict();

  const env = useMemo(
    (): WikiContentEnv => ({
      renderWikiLink: (pageId, linkChildren) => (
        <Link to={`/wiki/${pageId}`}>{linkChildren}</Link>
      ),
      renderSourceBadge: (source) => <SourceBadge source={source} />,
      sourceFilesLabel: d.wiki_source_files,
      relatedPagesLabel: null,
    }),
    [d],
  );

  const fetchSpec = useCallback(
    async (lang: string): Promise<string | null> => {
      const res = await client.get<string>(`/kgf/specs/${lang}`);
      return res.ok ? res.data : null;
    },
    [],
  );

  return (
    <KgfSpecProvider value={fetchSpec}>
      <WikiContentEnvProvider value={env}>{children}</WikiContentEnvProvider>
    </KgfSpecProvider>
  );
};
