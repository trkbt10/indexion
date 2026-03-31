/**
 * @file Left sidebar navigation tree for wiki pages.
 */

import { useState } from "react";
import { Link, useParams } from "react-router";
import { ChevronRight } from "lucide-react";
import { ScrollArea } from "../../../components/ui/scroll-area.tsx";
import { cn } from "../../../lib/utils.ts";
import type { WikiNavItem } from "@indexion/api-client";

type Props = {
  readonly items: ReadonlyArray<WikiNavItem>;
  readonly onNavigate?: () => void;
};

export const WikiNav = ({ items, onNavigate }: Props): React.JSX.Element => {
  const params = useParams();
  const activeId = params["*"] || "overview";

  return (
    <ScrollArea className="h-full border-r">
      <div className="p-3">
        <h2 className="mb-2 px-2 text-xs font-semibold uppercase tracking-wider text-muted-foreground">
          Wiki
        </h2>
        <nav className="space-y-0.5">
          {items.map((item) => (
            <NavItem key={item.id} item={item} activeId={activeId} depth={0} onNavigate={onNavigate} />
          ))}
        </nav>
      </div>
    </ScrollArea>
  );
};

type NavItemProps = {
  readonly item: WikiNavItem;
  readonly activeId: string;
  readonly depth: number;
  readonly onNavigate?: () => void;
};

const NavItem = ({ item, activeId, depth, onNavigate }: NavItemProps): React.JSX.Element => {
  const [open, setOpen] = useState(
    activeId === item.id || activeId.startsWith(item.id + "/"),
  );
  const hasChildren = item.children.length > 0;
  const isActive = activeId === item.id;

  return (
    <div>
      <div
        className={cn(
          "flex items-center gap-1 rounded-md px-2 py-1 text-sm transition-colors",
          isActive
            ? "bg-accent text-accent-foreground font-medium"
            : "text-muted-foreground hover:bg-accent/50 hover:text-foreground",
        )}
        style={{ paddingLeft: `${8 + depth * 12}px` }}
      >
        {hasChildren && (
          <button
            type="button"
            onClick={() => setOpen(!open)}
            className="shrink-0 rounded p-0.5 hover:bg-accent"
          >
            <ChevronRight
              className={cn(
                "size-3.5 transition-transform",
                open && "rotate-90",
              )}
            />
          </button>
        )}
        <Link to={`/wiki/${item.id}`} className="flex-1 truncate" onClick={onNavigate}>
          {item.title}
        </Link>
      </div>
      {hasChildren && open && (
        <div>
          {item.children.map((child) => (
            <NavItem
              key={child.id}
              item={child}
              activeId={activeId}
              depth={depth + 1}
              onNavigate={onNavigate}
            />
          ))}
        </div>
      )}
    </div>
  );
};
