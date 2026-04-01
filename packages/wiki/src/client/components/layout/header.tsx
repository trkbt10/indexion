import { useState } from "react";
import { NavLink } from "react-router";
import { Search, Settings, Menu, X } from "lucide-react";
import { Button } from "../ui/button.tsx";
import { Separator } from "../ui/separator.tsx";
import { Tooltip, TooltipTrigger, TooltipContent } from "../ui/tooltip.tsx";
import { Logo } from "../shared/logo.tsx";
import { isStaticMode } from "../../lib/client.ts";

const NAV_ITEMS = [
  ["/", "Explorer", true],
  ["/wiki/overview", "Wiki", false],
] as const;

type Props = {
  readonly onSearchClick: () => void;
};

export const Header = ({ onSearchClick }: Props): React.JSX.Element => {
  const [menuOpen, setMenuOpen] = useState(false);

  return (
    <header className="shrink-0 border-b">
      <div className="flex h-12 items-center gap-4 px-4">
        <NavLink to="/" className="flex items-center">
          <Logo className="h-6" />
        </NavLink>

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
          {/* Search */}
          <Tooltip>
            <TooltipTrigger asChild>
              <Button variant="ghost" size="sm" onClick={onSearchClick}>
                <Search className="size-4" />
                <span className="hidden text-xs text-muted-foreground sm:inline ml-1">
                  ⌘K
                </span>
              </Button>
            </TooltipTrigger>
            <TooltipContent>Search (⌘K)</TooltipContent>
          </Tooltip>

          {/* Settings — hidden in static mode */}
          {!isStaticMode && (
            <Tooltip>
              <TooltipTrigger asChild>
                <NavLink to="/settings">
                  {({ isActive }) => (
                    <Button
                      variant={isActive ? "secondary" : "ghost"}
                      size="sm"
                    >
                      <Settings className="size-4" />
                    </Button>
                  )}
                </NavLink>
              </TooltipTrigger>
              <TooltipContent>Settings</TooltipContent>
            </Tooltip>
          )}

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
            <NavLink
              key={to}
              to={to}
              end={end}
              onClick={() => setMenuOpen(false)}
            >
              {({ isActive }) => (
                <Button
                  variant={isActive ? "secondary" : "ghost"}
                  size="sm"
                  className="w-full justify-start"
                >
                  {label}
                </Button>
              )}
            </NavLink>
          ))}
          <Button
            variant="ghost"
            size="sm"
            className="w-full justify-start"
            onClick={() => {
              setMenuOpen(false);
              onSearchClick();
            }}
          >
            Search
          </Button>
          {!isStaticMode && (
            <NavLink to="/settings" onClick={() => setMenuOpen(false)}>
              {({ isActive }) => (
                <Button
                  variant={isActive ? "secondary" : "ghost"}
                  size="sm"
                  className="w-full justify-start"
                >
                  Settings
                </Button>
              )}
            </NavLink>
          )}
        </nav>
      )}
    </header>
  );
};
