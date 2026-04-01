import { TreesIcon, TableIcon, GitFork, Box } from "lucide-react";
import { Link } from "react-router";
import { Input } from "../../components/ui/input.tsx";
import { Button } from "../../components/ui/button.tsx";
import {
  Tooltip,
  TooltipTrigger,
  TooltipContent,
} from "../../components/ui/tooltip.tsx";

export type ExplorerView = "tree" | "table" | "graph";

type Props = {
  readonly view: ExplorerView;
  readonly onViewChange: (v: ExplorerView) => void;
  readonly filter: string;
  readonly onFilterChange: (f: string) => void;
  readonly stats: { roots: number; files: number; symbols: number };
};

const VIEW_OPTIONS: ReadonlyArray<{
  value: ExplorerView;
  icon: typeof TreesIcon;
  label: string;
}> = [
  { value: "tree", icon: TreesIcon, label: "Tree" },
  { value: "table", icon: TableIcon, label: "Table" },
  { value: "graph", icon: GitFork, label: "2D Graph" },
];

export const ExplorerToolbar = ({
  view,
  onViewChange,
  filter,
  onFilterChange,
  stats,
}: Props): React.JSX.Element => (
  <div className="flex flex-wrap items-center gap-3 border-b px-4 py-2">
    <span className="text-sm text-muted-foreground">
      {stats.roots} roots &middot; {stats.files} files &middot; {stats.symbols}{" "}
      symbols
    </span>

    <div className="ml-auto flex items-center gap-2">
      <Input
        className="w-full max-w-48"
        placeholder="Filter..."
        value={filter}
        onChange={(e) => onFilterChange(e.target.value)}
      />

      <div className="flex items-center rounded-md border">
        {VIEW_OPTIONS.map(({ value, icon: Icon, label }) => (
          <Tooltip key={value}>
            <TooltipTrigger asChild>
              <button
                type="button"
                onClick={() => onViewChange(value)}
                className={`px-2 py-1.5 ${view === value ? "bg-accent text-accent-foreground" : "text-muted-foreground hover:text-foreground"}`}
              >
                <Icon className="size-3.5" />
              </button>
            </TooltipTrigger>
            <TooltipContent>{label}</TooltipContent>
          </Tooltip>
        ))}
      </div>

      <Tooltip>
        <TooltipTrigger asChild>
          <Link to="/graph">
            <Button variant="ghost" size="sm">
              <Box className="size-3.5" />
            </Button>
          </Link>
        </TooltipTrigger>
        <TooltipContent>3D Graph</TooltipContent>
      </Tooltip>
    </div>
  </div>
);
