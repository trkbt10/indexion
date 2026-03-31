import { useState } from "react";
import { NavLink } from "react-router";
import { RefreshCw, Menu, X } from "lucide-react";
import { useApiMutationCall } from "../../lib/hooks.ts";
import { client } from "../../lib/client.ts";
import { rebuildDigest } from "@indexion/api-client";
import { Button } from "../ui/button.tsx";
import { Separator } from "../ui/separator.tsx";
import { cn } from "../../lib/utils.ts";

const NAV_ITEMS = [
  ["/", "Browse", true],
  ["/graph", "Graph", false],
  ["/search", "Search", false],
  ["/index", "Index", false],
  ["/wiki/overview", "Wiki", false],
] as const;

export const Header = (): React.JSX.Element => {
  const { state, mutate } = useApiMutationCall<{ readonly rebuilt: boolean; readonly functions: number }>();
  const [menuOpen, setMenuOpen] = useState(false);

  return (
    <header className="shrink-0 border-b">
      <div className="flex h-12 items-center gap-4 px-4">
        <span className="font-mono text-sm font-bold tracking-tight">ix</span>

        <Separator orientation="vertical" className="hidden h-5 md:block" />

        {/* Desktop nav */}
        <nav className="hidden items-center gap-1 md:flex">
          {NAV_ITEMS.map(([to, label, end]) => (
            <NavLink key={to} to={to} end={end}>
              {({ isActive }) => (
                <Button variant={isActive ? "secondary" : "ghost"} size="sm">
                  {label}
                </Button>
              )}
            </NavLink>
          ))}
        </nav>

        <div className="ml-auto flex items-center gap-2">
          {state.status === "success" && (
            <span className="hidden text-xs text-muted-foreground sm:inline">{state.data.functions} functions indexed</span>
          )}
          {state.status === "error" && (
            <span className="text-xs text-destructive">Rebuild failed</span>
          )}
          <Button
            variant="outline"
            size="sm"
            onClick={() => mutate(() => rebuildDigest(client))}
            disabled={state.status === "loading"}
          >
            <RefreshCw className={cn("size-3.5", state.status === "loading" && "animate-spin")} />
            <span className="hidden sm:inline">Rebuild</span>
          </Button>

          {/* Mobile hamburger */}
          <Button
            variant="ghost"
            size="sm"
            className="md:hidden"
            onClick={() => setMenuOpen(!menuOpen)}
          >
            {menuOpen ? <X className="size-4" /> : <Menu className="size-4" />}
          </Button>
        </div>
      </div>

      {/* Mobile nav dropdown */}
      {menuOpen && (
        <nav className="flex flex-col gap-1 border-t px-4 py-2 md:hidden">
          {NAV_ITEMS.map(([to, label, end]) => (
            <NavLink key={to} to={to} end={end} onClick={() => setMenuOpen(false)}>
              {({ isActive }) => (
                <Button variant={isActive ? "secondary" : "ghost"} size="sm" className="w-full justify-start">
                  {label}
                </Button>
              )}
            </NavLink>
          ))}
        </nav>
      )}
    </header>
  );
};
