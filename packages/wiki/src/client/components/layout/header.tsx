import { NavLink } from "react-router";
import { Search, Settings } from "lucide-react";
import { Button } from "../ui/button.tsx";
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

export const Header = ({ onSearchClick }: Props): React.JSX.Element => (
  <header className="sticky top-0 z-40 border-b bg-background">
    <div className="flex h-12 items-center gap-2 px-3 sm:gap-4 sm:px-4">
      <NavLink to="/" className="flex shrink-0 items-center">
        <Logo className="h-5 sm:h-6" />
      </NavLink>

      {/* Nav tabs — always visible on all screen sizes */}
      <nav className="flex items-center gap-0.5 sm:gap-1">
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

      <div className="ml-auto flex items-center gap-1 sm:gap-2">
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

        {!isStaticMode && (
          <Tooltip>
            <TooltipTrigger asChild>
              <NavLink to="/settings">
                {({ isActive }) => (
                  <Button variant={isActive ? "secondary" : "ghost"} size="sm">
                    <Settings className="size-4" />
                  </Button>
                )}
              </NavLink>
            </TooltipTrigger>
            <TooltipContent>Settings</TooltipContent>
          </Tooltip>
        )}
      </div>
    </div>
  </header>
);
