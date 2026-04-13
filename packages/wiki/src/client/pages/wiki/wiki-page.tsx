/**
 * @file Wiki page — responsive layout with nav, content, and ToC.
 *
 * Desktop: sticky sidebar nav | body-scrolling content | sticky ToC.
 * Mobile: collapsible nav above content, body scroll throughout.
 */

import { useState } from "react";
import { useParams } from "react-router";
import { ChevronDown } from "lucide-react";
import { LoadingSpinner } from "../../components/shared/loading-spinner.tsx";
import { ErrorPanel } from "../../components/shared/error-panel.tsx";
import { WikiNav } from "./components/wiki-nav.tsx";
import { WikiContent } from "./components/wiki-content.tsx";
import { WikiContentWebEnv } from "./components/wiki-content-web-env.tsx";
import { WikiToc } from "./components/wiki-toc.tsx";
import { useWikiNav, useWikiPage } from "./lib/wiki-hooks.ts";
import { cn } from "../../lib/utils.ts";
import { useDict } from "../../i18n/index.ts";

export const WikiPage = (): React.JSX.Element => {
  const params = useParams();
  const d = useDict();
  const pageId = params["*"] || "overview";
  const [mobileNavOpen, setMobileNavOpen] = useState(false);

  const navState = useWikiNav();
  const pageState = useWikiPage(pageId);

  if (navState.status === "loading") {
    return <LoadingSpinner message={d.loading_wiki} />;
  }
  if (navState.status === "error") {
    return <ErrorPanel message={navState.error} />;
  }
  if (navState.status !== "success") {
    return <LoadingSpinner message={d.loading_wiki} />;
  }

  return (
    <div className="md:grid md:grid-cols-[240px_1fr] lg:grid-cols-[240px_1fr_200px]">
      {/* Desktop nav sidebar — sticky */}
      <aside className="hidden md:block">
        <div className="sticky top-12 h-[calc(100vh-3rem)] overflow-y-auto border-r">
          <WikiNav items={navState.data.pages} />
        </div>
      </aside>

      {/* Main column */}
      <div className="min-w-0">
        {/* Mobile nav toggle */}
        <button
          type="button"
          className="flex w-full items-center gap-1 border-b px-4 py-2 text-left text-sm text-muted-foreground md:hidden"
          onClick={() => setMobileNavOpen((v) => !v)}
        >
          <ChevronDown
            className={cn(
              "size-4 shrink-0 transition-transform",
              mobileNavOpen && "rotate-180",
            )}
          />
          {d.wiki_pages_button}
        </button>
        {mobileNavOpen && (
          <div className="max-h-64 overflow-y-auto border-b md:hidden">
            <WikiNav
              items={navState.data.pages}
              onNavigate={() => setMobileNavOpen(false)}
            />
          </div>
        )}

        <WikiContentPane pageState={pageState} />
      </div>

      {/* TOC — lg+ sticky */}
      <aside className="hidden lg:block">
        <div className="sticky top-12 h-[calc(100vh-3rem)] overflow-y-auto">
          <WikiTocPane pageState={pageState} />
        </div>
      </aside>
    </div>
  );
};

type PaneProps = {
  readonly pageState: ReturnType<typeof useWikiPage>;
};

const WikiContentPane = ({ pageState }: PaneProps): React.JSX.Element => {
  const d = useDict();
  if (pageState.status === "loading") {
    return <LoadingSpinner message={d.loading_page} />;
  }
  if (pageState.status === "error") {
    return <ErrorPanel message={pageState.error} />;
  }
  if (pageState.status !== "success") {
    return <LoadingSpinner message={d.loading_page} />;
  }
  return (
    <WikiContentWebEnv>
      <WikiContent page={pageState.data} />
    </WikiContentWebEnv>
  );
};

const WikiTocPane = ({ pageState }: PaneProps): React.JSX.Element | null => {
  if (pageState.status !== "success") {
    return null;
  }
  return <WikiToc headings={pageState.data.headings} />;
};
