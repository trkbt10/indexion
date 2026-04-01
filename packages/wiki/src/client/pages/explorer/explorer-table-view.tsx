import { useState, useMemo } from "react";
import type { IndexedFunction } from "@indexion/api-client";
import { ScrollArea } from "../../components/ui/scroll-area.tsx";
import { kindTextClass } from "../../lib/kind-colors.ts";

type SortKey = "name" | "kind" | "module" | "depth" | "callers" | "callees";
type SortDir = "asc" | "desc";

type Props = {
  readonly functions: ReadonlyArray<IndexedFunction>;
  readonly filter: string;
  readonly onSelectFn?: (fn: IndexedFunction) => void;
};

export const ExplorerTableView = ({
  functions,
  filter,
  onSelectFn,
}: Props): React.JSX.Element => {
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
    const lower = filter.toLowerCase();
    const filtered = lower
      ? functions.filter(
          (f) =>
            f.name.toLowerCase().includes(lower) ||
            f.module.toLowerCase().includes(lower) ||
            f.kind.toLowerCase().includes(lower) ||
            (f.doc ?? "").toLowerCase().includes(lower),
        )
      : [...functions];

    filtered.sort((a, b) => {
      const dir = sortDir === "asc" ? 1 : -1;
      switch (sortKey) {
        case "name":
          return a.name.localeCompare(b.name) * dir;
        case "kind":
          return a.kind.localeCompare(b.kind) * dir;
        case "module":
          return a.module.localeCompare(b.module) * dir;
        case "depth":
          return (a.depth - b.depth) * dir;
        case "callers":
          return (a.callers.length - b.callers.length) * dir;
        case "callees":
          return (a.callees.length - b.callees.length) * dir;
      }
    });
    return filtered;
  }, [functions, filter, sortKey, sortDir]);

  const arrowMap = { asc: " ↑", desc: " ↓" } as const;
  const arrow = (key: SortKey) => (sortKey === key ? arrowMap[sortDir] : "");

  return (
    <ScrollArea className="h-full">
      <div className="min-w-[640px]">
        <table className="w-full text-left text-sm">
          <thead className="sticky top-0 z-10 border-b bg-background">
            <tr className="text-xs text-muted-foreground">
              {(
                [
                  ["name", "Name"],
                  ["kind", "Kind"],
                  ["module", "Module"],
                  ["depth", "Depth"],
                  ["callers", "In"],
                  ["callees", "Out"],
                ] as const
              ).map(([key, label]) => (
                <th
                  key={key}
                  className="cursor-pointer select-none px-4 py-2 font-medium hover:text-foreground"
                  onClick={() => handleSort(key)}
                >
                  {label}
                  {arrow(key)}
                </th>
              ))}
              <th className="px-4 py-2 font-medium">Doc</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-border">
            {data.map((fn) => (
              <tr
                key={fn.id}
                className="cursor-pointer transition-colors hover:bg-muted/50"
                onClick={() => onSelectFn?.(fn)}
              >
                <td className="whitespace-nowrap px-4 py-1.5 font-mono text-xs">
                  {fn.name}
                </td>
                <td
                  className={`whitespace-nowrap px-4 py-1.5 text-xs ${kindTextClass(fn.kind)}`}
                >
                  {fn.kind}
                </td>
                <td className="whitespace-nowrap px-4 py-1.5 font-mono text-xs text-muted-foreground">
                  {fn.module}
                </td>
                <td className="px-4 py-1.5 text-center text-xs tabular-nums">
                  {fn.depth}
                </td>
                <td className="px-4 py-1.5 text-center text-xs tabular-nums">
                  {fn.callers.length || ""}
                </td>
                <td className="px-4 py-1.5 text-center text-xs tabular-nums">
                  {fn.callees.length || ""}
                </td>
                <td className="max-w-xs truncate px-4 py-1.5 text-xs text-muted-foreground">
                  {fn.doc ?? fn.summary ?? ""}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </ScrollArea>
  );
};
