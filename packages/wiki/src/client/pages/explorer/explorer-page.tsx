import { useState, useMemo, useCallback } from "react";
import { useSearchParams } from "react-router";
import { useCachedApiCall } from "../../lib/hooks.ts";
import { client } from "../../lib/client.ts";
import { CacheKey } from "../../lib/api-cache.ts";

import {
  fetchGraph,
  fetchDigestIndex,
  type CodeGraph,
  type IndexedFunction,
} from "@indexion/api-client";
import { LoadingSpinner } from "../../components/shared/loading-spinner.tsx";
import { ErrorPanel } from "../../components/shared/error-panel.tsx";
import { ScrollArea } from "../../components/ui/scroll-area.tsx";
import type { FolderEntry, SymEntry } from "./explorer-types.ts";
import { buildFolderTree, filterTree } from "./explorer-tree-builder.ts";
import { ExplorerToolbar, type ExplorerView } from "./explorer-toolbar.tsx";
import { ExplorerTreeView } from "./explorer-tree-view.tsx";
import { ExplorerTableView } from "./explorer-table-view.tsx";
import { ExplorerGraph2D } from "./explorer-graph-2d.tsx";
import { FunctionDetail } from "./components/function-detail.tsx";

export const ExplorerPage = (): React.JSX.Element => {
  const [searchParams] = useSearchParams();
  const graphState = useCachedApiCall<CodeGraph>(CacheKey.digest.graph, () =>
    fetchGraph(client),
  );
  const indexState = useCachedApiCall<ReadonlyArray<IndexedFunction>>(
    CacheKey.digest.index,
    () => fetchDigestIndex(client),
  );
  const [selectedSym, setSelectedSym] = useState<SymEntry | null>(null);
  const [selectedFnDirect, setSelectedFnDirect] =
    useState<IndexedFunction | null>(null);
  const [filter, setFilter] = useState(searchParams.get("filter") ?? "");
  const [view, setView] = useState<ExplorerView>("tree");

  const tree = useMemo(() => {
    if (graphState.status !== "success") {
      return null;
    }
    const fns = indexState.status === "success" ? indexState.data : [];
    return buildFolderTree(graphState.data, fns);
  }, [graphState, indexState]);

  const filteredTree = useMemo(() => {
    if (!tree || !filter) {
      return tree;
    }
    return filterTree(tree, filter);
  }, [tree, filter]);

  const selectedFn = useMemo(() => {
    if (selectedFnDirect) {
      return selectedFnDirect;
    }
    if (!selectedSym || indexState.status !== "success") {
      return null;
    }
    return indexState.data.find((f) => f.id === selectedSym.id) ?? null;
  }, [selectedSym, selectedFnDirect, indexState]);

  const handleSelectSym = useCallback((sym: SymEntry) => {
    setSelectedFnDirect(null);
    setSelectedSym(sym);
  }, []);
  const handleSelectFn = useCallback((fn: IndexedFunction) => {
    setSelectedSym(null);
    setSelectedFnDirect(fn);
  }, []);

  const loading =
    graphState.status !== "success" || indexState.status === "loading";
  const error =
    (graphState.status === "error" && graphState.error) ||
    (indexState.status === "error" && indexState.error) ||
    null;

  if (loading) {
    return <LoadingSpinner message="Loading..." />;
  }
  if (error) {
    return <ErrorPanel message={error} />;
  }

  const totalFiles =
    tree?.reduce(function count(s: number, f: FolderEntry): number {
      return f.children.reduce(count, s + f.files.length);
    }, 0) ?? 0;

  const totalSymbols =
    indexState.status === "success" ? indexState.data.length : 0;

  return (
    <div className="grid h-full grid-rows-[auto_1fr]">
      <ExplorerToolbar
        view={view}
        onViewChange={setView}
        filter={filter}
        onFilterChange={setFilter}
        stats={{
          roots: tree?.length ?? 0,
          files: totalFiles,
          symbols: totalSymbols,
        }}
      />

      <div
        className="relative grid min-h-0 grid-cols-[1fr] md:data-[detail]:grid-cols-[1fr_360px]"
        data-detail={selectedFn ? "" : undefined}
      >
        {view === "tree" && (
          <ExplorerTreeView
            tree={filteredTree ?? []}
            onSelectSym={handleSelectSym}
          />
        )}
        {view === "table" && (
          <ExplorerTableView
            functions={indexState.status === "success" ? indexState.data : []}
            filter={filter}
            onSelectFn={handleSelectFn}
          />
        )}
        {view === "graph" && graphState.status === "success" && (
          <ExplorerGraph2D
            graph={graphState.data}
            indexFns={indexState.status === "success" ? indexState.data : []}
          />
        )}
        {selectedFn && (
          <ScrollArea className="absolute inset-0 z-10 h-full border-l bg-background md:static md:inset-auto md:z-auto">
            <FunctionDetail
              fn={selectedFn}
              onClose={() => {
                setSelectedSym(null);
                setSelectedFnDirect(null);
              }}
            />
          </ScrollArea>
        )}
      </div>
    </div>
  );
};
