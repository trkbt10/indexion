import type { CodeGraph, IndexedFunction } from "@indexion/api-client";
import type { FolderEntry, SymEntry } from "./explorer-types.ts";

const packageOf = (m: string): string => {
  const i = m.lastIndexOf("/");
  return i > 0 ? m.slice(0, i) : m;
};

export const buildFolderTree = (
  graph: CodeGraph,
  _fns: ReadonlyArray<IndexedFunction>,
): FolderEntry[] => {
  const localMods = Object.entries(graph.modules)
    .filter(([, mod]) => mod.file != null)
    .map(([m]) => m);

  const fileSym = new Map<string, SymEntry[]>();
  for (const [sid, s] of Object.entries(graph.symbols)) {
    const arr = fileSym.get(s.module) ?? [];
    arr.push({ id: sid, name: s.name, kind: s.kind });
    fileSym.set(s.module, arr);
  }

  const leafDirs = new Set<string>();
  for (const m of localMods) {
    const p = packageOf(m);
    if (p && p !== m) {
      leafDirs.add(p);
    }
  }
  const allDirs = new Set<string>();
  for (const d of leafDirs) {
    const parts = d.split("/");
    for (let i = 1; i <= parts.length; i++) {
      allDirs.add(parts.slice(0, i).join("/"));
    }
  }

  const dirFiles = new Map<
    string,
    { path: string; name: string; symbols: SymEntry[] }[]
  >();
  for (const m of localMods) {
    const p = packageOf(m);
    const arr = dirFiles.get(p) ?? [];
    arr.push({
      path: m,
      name: m.split("/").pop() ?? m,
      symbols: fileSym.get(m) ?? [],
    });
    dirFiles.set(p, arr);
  }

  const dirChildren = new Map<string, string[]>();
  for (const d of allDirs) {
    const parts = d.split("/");
    if (parts.length > 1) {
      const parent = parts.slice(0, -1).join("/");
      if (allDirs.has(parent)) {
        const arr = dirChildren.get(parent) ?? [];
        arr.push(d);
        dirChildren.set(parent, arr);
      }
    }
  }

  const buildNode = (path: string): FolderEntry => ({
    path,
    name: path.split("/").pop() ?? path,
    children: (dirChildren.get(path) ?? []).sort().map(buildNode),
    files: (dirFiles.get(path) ?? []).sort((a, b) =>
      a.name.localeCompare(b.name),
    ),
  });

  const roots = [...allDirs].filter((d) => {
    const parts = d.split("/");
    return parts.length === 1 || !allDirs.has(parts.slice(0, -1).join("/"));
  });
  return roots.sort().map(buildNode);
};

export const filterTree = (
  tree: FolderEntry[],
  filter: string,
): FolderEntry[] => {
  const lower = filter.toLowerCase();
  const filterFolder = (f: FolderEntry): FolderEntry | null => {
    const matchedChildren = f.children
      .map(filterFolder)
      .filter(Boolean) as FolderEntry[];
    const matchedFiles = f.files.filter(
      (file) =>
        file.name.toLowerCase().includes(lower) ||
        file.symbols.some((s) => s.name.toLowerCase().includes(lower)),
    );
    if (
      matchedChildren.length === 0 &&
      matchedFiles.length === 0 &&
      !f.name.toLowerCase().includes(lower)
    ) {
      return null;
    }
    return { ...f, children: matchedChildren, files: matchedFiles };
  };
  return tree.map(filterFolder).filter(Boolean) as FolderEntry[];
};
