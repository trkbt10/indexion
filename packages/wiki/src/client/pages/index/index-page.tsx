import { useState, useMemo } from "react";
import { useApiCall } from "../../lib/hooks.ts";
import { client } from "../../lib/client.ts";
import { fetchDigestIndex, fetchDigestStats, type IndexedFunction } from "@indexion/api-client";
import { LoadingSpinner } from "../../components/shared/loading-spinner.tsx";
import { ErrorPanel } from "../../components/shared/error-panel.tsx";
import { Input } from "../../components/ui/input.tsx";
import { Badge } from "../../components/ui/badge.tsx";
import { ScrollArea } from "../../components/ui/scroll-area.tsx";

type SortKey = "name" | "kind" | "module" | "depth" | "callers" | "callees";
type SortDir = "asc" | "desc";

type DigestStats = {
  readonly indexDirectory: string;
  readonly provider: string;
  readonly embeddingDim: number;
  readonly totalSymbols: number;
  readonly totalModules: number;
  readonly totalEdges: number;
};

const kindColor = (kind: string): string => {
  switch (kind.toLowerCase()) {
    case "function": return "text-blue-400";
    case "struct": case "class": return "text-green-400";
    case "enum": case "variant": return "text-yellow-400";
    case "trait": case "interface": return "text-purple-400";
    default: return "text-muted-foreground";
  }
};

export const IndexPage = (): React.JSX.Element => {
  const indexState = useApiCall((signal) => fetchDigestIndex(client, signal));
  const statsState = useApiCall((signal) => fetchDigestStats<DigestStats>(client, signal));
  const [filter, setFilter] = useState("");
  const [sortKey, setSortKey] = useState<SortKey>("module");
  const [sortDir, setSortDir] = useState<SortDir>("asc");

  const handleSort = (key: SortKey) => {
    if (sortKey === key) {
      setSortDir(sortDir === "asc" ? "desc" : "asc");
    } else {
      setSortKey(key);
      setSortDir("asc");
    }
  };

  const data = useMemo(() => {
    if (indexState.status !== "success") return [];
    const lower = filter.toLowerCase();
    const filtered = lower
      ? indexState.data.filter(
          (f) =>
            f.name.toLowerCase().includes(lower) ||
            f.module.toLowerCase().includes(lower) ||
            f.kind.toLowerCase().includes(lower) ||
            (f.doc ?? "").toLowerCase().includes(lower),
        )
      : [...indexState.data];

    filtered.sort((a, b) => {
      const dir = sortDir === "asc" ? 1 : -1;
      switch (sortKey) {
        case "name": return a.name.localeCompare(b.name) * dir;
        case "kind": return a.kind.localeCompare(b.kind) * dir;
        case "module": return a.module.localeCompare(b.module) * dir;
        case "depth": return (a.depth - b.depth) * dir;
        case "callers": return (a.callers.length - b.callers.length) * dir;
        case "callees": return (a.callees.length - b.callees.length) * dir;
      }
    });
    return filtered;
  }, [indexState, filter, sortKey, sortDir]);

  if (indexState.status === "loading" || indexState.status === "idle") {
    return <LoadingSpinner message="Loading index..." />;
  }
  if (indexState.status === "error") {
    return <ErrorPanel message={indexState.error} />;
  }

  const stats = statsState.status === "success" ? statsState.data : null;
  const arrow = (key: SortKey) =>
    sortKey === key ? (sortDir === "asc" ? " \u2191" : " \u2193") : "";

  return (
    <div className="grid h-full grid-rows-[auto_auto_1fr]">
      {/* Stats bar */}
      <div className="flex flex-wrap items-center gap-3 border-b px-4 py-2 text-xs text-muted-foreground">
        <span>{indexState.data.length} functions indexed</span>
        {stats && (
          <>
            <span>&middot; {stats.totalSymbols} symbols</span>
            <span>&middot; {stats.totalModules} modules</span>
            <span>&middot; {stats.totalEdges} edges</span>
            <Badge variant="outline" className="ml-auto text-xs">{stats.provider}</Badge>
          </>
        )}
      </div>

      {/* Filter */}
      <div className="border-b px-4 py-2">
        <Input
          placeholder="Filter by name, module, kind, doc..."
          value={filter}
          onChange={(e) => setFilter(e.target.value)}
          className="max-w-md"
        />
        {filter && (
          <span className="ml-3 text-xs text-muted-foreground">{data.length} matches</span>
        )}
      </div>

      {/* Table */}
      <ScrollArea className="h-full">
        <div className="min-w-[640px]">
        <table className="w-full text-left text-sm">
          <thead className="sticky top-0 z-10 bg-background border-b">
            <tr className="text-xs text-muted-foreground">
              {([
                ["name", "Name"],
                ["kind", "Kind"],
                ["module", "Module"],
                ["depth", "Depth"],
                ["callers", "In"],
                ["callees", "Out"],
              ] as const).map(([key, label]) => (
                <th
                  key={key}
                  className="cursor-pointer select-none px-4 py-2 font-medium hover:text-foreground"
                  onClick={() => handleSort(key)}
                >
                  {label}{arrow(key)}
                </th>
              ))}
              <th className="px-4 py-2 font-medium">Doc</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-border">
            {data.map((fn) => (
              <tr key={fn.id} className="hover:bg-muted/50 transition-colors">
                <td className="whitespace-nowrap px-4 py-1.5 font-mono text-xs">{fn.name}</td>
                <td className={`whitespace-nowrap px-4 py-1.5 text-xs ${kindColor(fn.kind)}`}>{fn.kind}</td>
                <td className="whitespace-nowrap px-4 py-1.5 font-mono text-xs text-muted-foreground">{fn.module}</td>
                <td className="px-4 py-1.5 text-xs text-center tabular-nums">{fn.depth}</td>
                <td className="px-4 py-1.5 text-xs text-center tabular-nums">{fn.callers.length || ""}</td>
                <td className="px-4 py-1.5 text-xs text-center tabular-nums">{fn.callees.length || ""}</td>
                <td className="max-w-xs truncate px-4 py-1.5 text-xs text-muted-foreground">
                  {fn.doc ?? fn.summary ?? ""}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
        </div>
      </ScrollArea>
    </div>
  );
};
