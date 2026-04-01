import { ScrollArea } from "../../components/ui/scroll-area.tsx";
import type { FolderEntry, SymEntry } from "./explorer-types.ts";
import { FolderItem } from "./components/folder-item.tsx";

type Props = {
  readonly tree: ReadonlyArray<FolderEntry>;
  readonly onSelectSym: (sym: SymEntry) => void;
};

export const ExplorerTreeView = ({
  tree,
  onSelectSym,
}: Props): React.JSX.Element => (
  <ScrollArea className="h-full">
    <div className="p-2">
      {tree.map((folder) => (
        <FolderItem
          key={folder.path}
          folder={folder}
          depth={0}
          onSelectSym={onSelectSym}
        />
      ))}
    </div>
  </ScrollArea>
);
