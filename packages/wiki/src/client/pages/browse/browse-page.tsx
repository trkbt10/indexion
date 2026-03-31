import { useState, useMemo, useCallback } from "react";
import { useApiCall } from "../../lib/hooks.ts";
import { client } from "../../lib/client.ts";
import { fetchGraph, fetchDigestIndex, type CodeGraph, type IndexedFunction } from "@indexion/api-client";
import { LoadingSpinner } from "../../components/shared/loading-spinner.tsx";
import { ErrorPanel } from "../../components/shared/error-panel.tsx";
import { Input } from "../../components/ui/input.tsx";
import { ScrollArea } from "../../components/ui/scroll-area.tsx";
import type { FolderEntry, SymEntry } from "./browse-types.ts";
import { buildFolderTree, filterTree } from "./browse-tree-builder.ts";
import { FolderItem } from "./components/folder-item.tsx";
import { FunctionDetail } from "./components/function-detail.tsx";

export const BrowsePage = (): React.JSX.Element => {
  const graphState = useApiCall((signal) => fetchGraph(client, signal));
  const indexState = useApiCall((signal) => fetchDigestIndex(client, signal));
  const [selectedSym, setSelectedSym] = useState<SymEntry | null>(null);
  const [filter, setFilter] = useState("");

  const tree = useMemo(() => {
    if (graphState.status !== "success") return null;
    const fns = indexState.status === "success" ? indexState.data : [];
    return buildFolderTree(graphState.data, fns);
  }, [graphState, indexState]);

  const selectedFn = useMemo(() => {
    if (!selectedSym || indexState.status !== "success") return null;
    return indexState.data.find((f) => f.id === selectedSym.id) ?? null;
  }, [selectedSym, indexState]);

  const handleSelectSym = useCallback((sym: SymEntry) => {
    setSelectedSym(sym);
  }, []);

  const filteredTree = useMemo(() => {
    if (!tree || !filter) return tree;
    return filterTree(tree, filter);
  }, [tree, filter]);

  const loading = graphState.status !== "success" || indexState.status === "loading";
  const error = graphState.status === "error" ? graphState.error
    : indexState.status === "error" ? indexState.error : null;

  if (loading) return <LoadingSpinner message="Loading..." />;
  if (error) return <ErrorPanel message={error} />;

  const totalFiles = tree?.reduce(function count(s: number, f: FolderEntry): number {
    return f.children.reduce(count, s + f.files.length);
  }, 0) ?? 0;

  return (
    <div className="grid h-full grid-rows-[auto_1fr]">
      <div className="flex items-center gap-4 border-b px-4 py-2">
        <span className="text-sm text-muted-foreground">
          {tree?.length ?? 0} roots &middot; {totalFiles} files
        </span>
        <Input
          className="ml-auto w-full max-w-56"
          placeholder="Filter..."
          value={filter}
          onChange={(e) => setFilter(e.target.value)}
        />
      </div>

      <div className="relative grid min-h-0 grid-cols-[1fr] md:data-[detail]:grid-cols-[1fr_360px]" data-detail={selectedFn ? "" : undefined}>
        <ScrollArea className="h-full">
          <div className="p-2">
            {(filteredTree ?? []).map((folder) => (
              <FolderItem key={folder.path} folder={folder} depth={0} onSelectSym={handleSelectSym} />
            ))}
          </div>
        </ScrollArea>
        {selectedFn && (
          <ScrollArea className="absolute inset-0 z-10 bg-background md:static md:inset-auto md:z-auto h-full border-l">
            <FunctionDetail fn={selectedFn} onClose={() => setSelectedSym(null)} />
          </ScrollArea>
        )}
      </div>
    </div>
  );
};
