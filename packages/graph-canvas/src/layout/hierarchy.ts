/**
 * @file Hierarchical path assignment + tree indices (layout-internal).
 *
 * Consumed only by the hierarchical layout strategy. Derives a full
 * ancestor path per node from node.file / node.id, then exposes the
 * tree indices (children, roots, owned-under) the placer walks.
 *
 * Language-agnostic: we only depend on
 *   - `node.file`   — populated for every internal node
 *   - `node.id`     — split on `/` when it contains one
 * No per-language prefixes (pkg:, url:, npm:, …) are hard-coded.
 */

import type { ViewNode } from "../types.ts";

export type HierarchicalAssignment = {
  /** For each node, its ancestors from broadest to most specific. */
  readonly pathOf: ReadonlyMap<string, readonly string[]>;
  /** All unique ancestor paths seen, ordered shallow → deep. */
  readonly allPaths: readonly string[];
};

export function computeHierarchy(
  nodes: readonly ViewNode[],
): HierarchicalAssignment {
  const pathOf = new Map<string, readonly string[]>();
  const seen = new Set<string>();
  const ordered: string[] = [];

  for (const node of nodes) {
    const path = ancestorsOf(node);
    pathOf.set(node.id, path);
    for (const ancestor of path) {
      if (!seen.has(ancestor)) {
        seen.add(ancestor);
        ordered.push(ancestor);
      }
    }
  }
  // Stable shallow-first ordering — shorter paths first, then
  // lexicographic. Helps the layout visit broader clusters before
  // diving into their children.
  ordered.sort((a, b) => {
    const da = depthOf(a);
    const db = depthOf(b);
    if (da !== db) {
      return da - db;
    }
    if (a < b) {
      return -1;
    }
    if (a > b) {
      return 1;
    }
    return 0;
  });
  return { pathOf, allPaths: ordered };
}

/** Derive a hierarchical path from any node.
 *
 *  Priority:
 *  1. `node.file` — the canonical grouping signal when present.
 *  2. The node id itself, split on `/`. This handles *any*
 *     path-like id format (moonbit `pkg:foo/bar`, npm `@scope/pkg`,
 *     python `foo.bar.baz` is not `/`-separated so stays flat,
 *     urls that happen to contain `/`, etc.) without any
 *     language-specific prefix check.
 *  3. Flat single-level fallback for opaque ids like `url:Overview`.
 *
 *  No prefix is stripped or treated specially — the whole id
 *  contributes to the ancestor chain. That way groupings show up
 *  naturally for whatever id scheme the host language uses. */
function ancestorsOf(node: ViewNode): string[] {
  if (node.file && node.file.length > 0) {
    return splitToAncestors(node.file);
  }
  if (node.id.includes("/")) {
    return splitToAncestors(node.id);
  }
  return [node.id];
}

/**
 * Split `"src/pipeline/discover.mbt"` into
 * `["src", "src/pipeline", "src/pipeline/discover.mbt"]`.
 * With a prefix, prepends it to every element.
 */
function splitToAncestors(
  path: string,
  options?: { readonly prefix?: string },
): string[] {
  const prefix = options?.prefix ?? "";
  const parts = path.split("/").filter((p) => p.length > 0);
  const out: string[] = [];
  for (let i = 0; i < parts.length; i++) {
    const joined = parts.slice(0, i + 1).join("/");
    out.push(`${prefix}${joined}`);
  }
  return out;
}

function depthOf(path: string): number {
  let depth = 1;
  for (let i = 0; i < path.length; i++) {
    if (path[i] === "/") {
      depth++;
    }
  }
  return depth;
}

/**
 * Build a direct-children map: for each ancestor path, the set of
 * immediate child ancestor paths (one level deeper, with this path as
 * prefix). Used by the hierarchical layout to walk the tree.
 */
export function buildChildrenIndex(
  assignment: HierarchicalAssignment,
): ReadonlyMap<string, readonly string[]> {
  const children = new Map<string, string[]>();
  const paths = new Set(assignment.allPaths);
  for (const path of assignment.allPaths) {
    const parent = parentOf(path);
    if (parent === null || !paths.has(parent)) {
      continue;
    }
    const list = children.get(parent);
    if (list) {
      list.push(path);
    } else {
      children.set(parent, [path]);
    }
  }
  return children;
}

/** Return the parent path one level up, or null at the root. */
export function parentOf(path: string): string | null {
  const slash = path.lastIndexOf("/");
  if (slash < 0) {
    return null;
  }
  return path.slice(0, slash);
}

/**
 * Build a map from ancestor path → all nodes that sit under it at any
 * depth. Used for weight calculation in the hierarchical layout.
 */
export function buildNodesUnderIndex(
  nodes: readonly ViewNode[],
  assignment: HierarchicalAssignment,
): ReadonlyMap<string, readonly ViewNode[]> {
  const out = new Map<string, ViewNode[]>();
  for (const node of nodes) {
    const path = assignment.pathOf.get(node.id);
    if (!path || path.length === 0) {
      continue;
    }
    for (const ancestor of path) {
      const list = out.get(ancestor);
      if (list) {
        list.push(node);
      } else {
        out.set(ancestor, [node]);
      }
    }
  }
  return out;
}

/**
 * Build a map from a path to the nodes whose deepest path equals that
 * path (i.e. nodes "owned" by that path, not merely descended under
 * it). This is what the layout actually places at each level — it
 * guarantees every node gets written exactly once regardless of where
 * its deepest path sits in the tree.
 */
export function buildOwnedNodesIndex(
  nodes: readonly ViewNode[],
  assignment: HierarchicalAssignment,
): ReadonlyMap<string, readonly ViewNode[]> {
  const out = new Map<string, ViewNode[]>();
  for (const node of nodes) {
    const path = assignment.pathOf.get(node.id);
    if (!path || path.length === 0) {
      continue;
    }
    const deepest = path[path.length - 1]!;
    const list = out.get(deepest);
    if (list) {
      list.push(node);
    } else {
      out.set(deepest, [node]);
    }
  }
  return out;
}

/**
 * Tops of the hierarchy — ancestor paths with no parent inside the
 * assignment. Layout starts here.
 */
export function rootsOf(assignment: HierarchicalAssignment): string[] {
  const all = new Set(assignment.allPaths);
  const roots: string[] = [];
  for (const path of assignment.allPaths) {
    const p = parentOf(path);
    if (p === null || !all.has(p)) {
      roots.push(path);
    }
  }
  return roots;
}
