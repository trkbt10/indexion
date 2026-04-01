/**
 * @file Wiki page — 3-column layout with nav, content, and ToC.
 *
 * Nav is fetched once and stays stable across page navigations.
 * Only the content pane re-renders on route changes.
 */

import { useState } from "react";
import { useParams } from "react-router";
import { Menu, X } from "lucide-react";
import { Button } from "../../components/ui/button.tsx";
import { LoadingSpinner } from "../../components/shared/loading-spinner.tsx";
import { ErrorPanel } from "../../components/shared/error-panel.tsx";
import { WikiNav } from "./components/wiki-nav.tsx";
import { WikiContent } from "./components/wiki-content.tsx";
import { WikiToc } from "./components/wiki-toc.tsx";
import { useWikiNav, useWikiPage } from "./lib/wiki-hooks.ts";

export const WikiPage = (): React.JSX.Element => {
  const params = useParams();
  const pageId = params["*"] || "overview";
  const [navOpen, setNavOpen] = useState(false);

  // Nav is fetched once (stable URL "/wiki/nav")
  const navState = useWikiNav();
  // Page is fetched per route change
  const pageState = useWikiPage(pageId);

  // Show full-page spinner only while nav is loading for the first time
  if (navState.status === "loading") {
    return <LoadingSpinner message="Loading wiki..." />;
  }

  if (navState.status === "error") {
    return <ErrorPanel message={navState.error} />;
  }

  if (navState.status !== "success") {
    return <LoadingSpinner message="Loading wiki..." />;
  }

  // Once nav is loaded, always render the layout.
  // Desktop: 3-column, Mobile: content only with toggle for nav.
  return (
    <div className="relative grid h-full grid-cols-[1fr] md:grid-cols-[240px_1fr] lg:grid-cols-[240px_1fr_200px]">
      {/* Mobile nav toggle */}
      <Button
        variant="ghost"
        size="sm"
        className="absolute left-2 top-2 z-20 md:hidden"
        onClick={() => setNavOpen(!navOpen)}
      >
        {navOpen ? <X className="size-4" /> : <Menu className="size-4" />}
      </Button>

      {/* Nav sidebar — desktop: always visible, mobile: overlay */}
      <div
        className={`
        md:block
        ${
          navOpen
            ? "absolute inset-y-0 left-0 z-10 w-64 bg-background shadow-lg"
            : "hidden"
        }
      `}
      >
        <WikiNav
          items={navState.data.pages}
          onNavigate={() => setNavOpen(false)}
        />
      </div>

      <WikiContentPane pageState={pageState} />

      {/* TOC — hidden on mobile + tablet, visible on lg+ */}
      <div className="hidden lg:block">
        <WikiTocPane pageState={pageState} />
      </div>
    </div>
  );
};

type PaneProps = {
  readonly pageState: ReturnType<typeof useWikiPage>;
};

const WikiContentPane = ({ pageState }: PaneProps): React.JSX.Element => {
  if (pageState.status === "loading") {
    return <LoadingSpinner message="Loading page..." />;
  }
  if (pageState.status === "error") {
    return <ErrorPanel message={pageState.error} />;
  }
  if (pageState.status !== "success") {
    return <LoadingSpinner message="Loading page..." />;
  }
  return <WikiContent page={pageState.data} />;
};

const WikiTocPane = ({ pageState }: PaneProps): React.JSX.Element | null => {
  if (pageState.status !== "success") {
    return null;
  }
  return <WikiToc headings={pageState.data.headings} />;
};
