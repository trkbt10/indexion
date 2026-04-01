import { useState } from "react";
import { ChevronRight, FileCode2 } from "lucide-react";
import { Badge } from "../../../components/ui/badge.tsx";
import {
  Collapsible,
  CollapsibleTrigger,
  CollapsibleContent,
} from "../../../components/ui/collapsible.tsx";
import { cn } from "../../../lib/utils.ts";
import type { FileEntry, SymEntry } from "../explorer-types.ts";
import { kindBadgeClass } from "../../../lib/kind-colors.ts";

type Props = {
  readonly file: FileEntry;
  readonly depth: number;
  readonly onSelectSym: (sym: SymEntry) => void;
};

export const FileItem = ({
  file,
  depth,
  onSelectSym,
}: Props): React.JSX.Element => {
  const [open, setOpen] = useState(false);

  return (
    <Collapsible open={open} onOpenChange={setOpen}>
      <CollapsibleTrigger asChild>
        <button
          className="flex w-full items-center gap-1.5 rounded-md px-2 py-1 text-sm hover:bg-accent"
          style={{ paddingLeft: 8 + depth * 16 }}
        >
          {file.symbols.length > 0 ? (
            <ChevronRight
              className={cn(
                "size-4 shrink-0 text-muted-foreground transition-transform",
                open && "rotate-90",
              )}
            />
          ) : (
            <span className="size-4 shrink-0" />
          )}
          <FileCode2 className="size-4 shrink-0 text-muted-foreground" />
          <span className="font-mono text-sm text-muted-foreground">
            {file.name}
          </span>
          {file.symbols.length > 0 && (
            <Badge variant="outline" className="ml-auto text-[10px]">
              {file.symbols.length}
            </Badge>
          )}
        </button>
      </CollapsibleTrigger>
      {file.symbols.length > 0 && (
        <CollapsibleContent>
          {file.symbols.map((sym) => (
            <button
              key={sym.id}
              className="flex w-full items-center gap-2 rounded-md px-2 py-0.5 text-sm hover:bg-accent"
              style={{ paddingLeft: 24 + depth * 16 }}
              onClick={() => onSelectSym(sym)}
            >
              <Badge
                variant="outline"
                className={cn(
                  "font-mono text-[10px]",
                  kindBadgeClass(sym.kind),
                )}
              >
                {sym.kind.slice(0, 3).toLowerCase()}
              </Badge>
              <span className="font-mono text-sm">{sym.name}</span>
            </button>
          ))}
        </CollapsibleContent>
      )}
    </Collapsible>
  );
};
