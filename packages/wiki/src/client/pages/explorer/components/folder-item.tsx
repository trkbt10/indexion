import { useState } from "react";
import { ChevronRight, FolderOpen } from "lucide-react";
import { Badge } from "../../../components/ui/badge.tsx";
import {
  Collapsible,
  CollapsibleTrigger,
  CollapsibleContent,
} from "../../../components/ui/collapsible.tsx";
import { cn } from "../../../lib/utils.ts";
import type { FolderEntry, SymEntry } from "../explorer-types.ts";
import { FileItem } from "./file-item.tsx";

type Props = {
  readonly folder: FolderEntry;
  readonly depth: number;
  readonly onSelectSym: (sym: SymEntry) => void;
};

export const FolderItem = ({
  folder,
  depth,
  onSelectSym,
}: Props): React.JSX.Element => {
  const [open, setOpen] = useState(depth < 1);
  const totalSyms = folder.files.reduce((s, f) => s + f.symbols.length, 0);

  return (
    <Collapsible open={open} onOpenChange={setOpen}>
      <CollapsibleTrigger asChild>
        <button
          className="flex w-full items-center gap-1.5 rounded-md px-2 py-1 text-sm hover:bg-accent"
          style={{ paddingLeft: 8 + depth * 16 }}
        >
          <ChevronRight
            className={cn(
              "size-4 shrink-0 text-muted-foreground transition-transform",
              open && "rotate-90",
            )}
          />
          <FolderOpen className="size-4 shrink-0 text-muted-foreground" />
          <span className="font-mono text-sm font-medium">{folder.name}</span>
          <div className="ml-auto flex items-center gap-1.5">
            {totalSyms > 0 && (
              <Badge variant="secondary" className="text-[10px]">
                {totalSyms} sym
              </Badge>
            )}
            <Badge variant="outline" className="text-[10px]">
              {folder.files.length} files
            </Badge>
          </div>
        </button>
      </CollapsibleTrigger>
      <CollapsibleContent>
        {folder.children.map((child) => (
          <FolderItem
            key={child.path}
            folder={child}
            depth={depth + 1}
            onSelectSym={onSelectSym}
          />
        ))}
        {folder.files.map((file) => (
          <FileItem
            key={file.path}
            file={file}
            depth={depth + 1}
            onSelectSym={onSelectSym}
          />
        ))}
      </CollapsibleContent>
    </Collapsible>
  );
};
