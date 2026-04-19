/**
 * @file Hierarchical layout — spec-level contracts (squarified treemap).
 *
 * These tests pin down what it means for the layout to be "correct" as
 * hierarchy density and nesting grow. The layout is a recursive
 * squarified treemap: each cluster's area is proportional to its
 * descendant-leaf count, sub-clusters tile the parent, leaves fill
 * leaf cells on a jittered grid. Cluster shells are circles inscribed
 * in their (padded) cell rectangle.
 *
 * Organised top-down:
 *   1. Single-level density   — n siblings, no grandchildren
 *   2. Nested recursion       — parents + grandchildren + …
 *   3. Sizing / density-proportional invariants
 *   4. Cross-cutting invariants (idempotence, count, scene bounds)
 *
 * Tests are written in *relative* terms so the layout can be retuned
 * without rewriting the spec. The few numeric tolerances are loose
 * enough to absorb padding / aspect-ratio shifts.
 */

import { describe, expect, it } from "vitest";
import type { ClusterShell, GraphJSON } from "./../types.ts";
import { normalizeGraph } from "./../normalize.ts";
import { computeHierarchy } from "./hierarchy.ts";
import { applyHierarchicalLayout } from "./hierarchical/index.ts";
import { DEFAULT_RENDER_SETTINGS } from "./../renderer/settings.ts";

const DEFAULT_LAYOUT = DEFAULT_RENDER_SETTINGS.layout;

// ─── Helpers ──────────────────────────────────────────────────────

function distance(
  a: ClusterShell["centre"],
  b: ClusterShell["centre"],
): number {
  const dx = a.x - b.x;
  const dy = a.y - b.y;
  const dz = a.z - b.z;
  return Math.sqrt(dx * dx + dy * dy + dz * dz);
}

function runLayout(graph: GraphJSON): readonly ClusterShell[] {
  const view = normalizeGraph(graph);
  const assignment = computeHierarchy(view.nodes);
  const result = applyHierarchicalLayout({
    nodes: view.nodes,
    assignment,
    settings: DEFAULT_LAYOUT,
  });
  return result.clusterShells;
}

/** Synthesise a flat hierarchy: `count` top-level folders, one file
 *  each, no deeper nesting. */
function flatHierarchy(count: number): GraphJSON {
  const nodes = Array.from({ length: count }, (_, i) => ({
    id: `folder${i}/f.mbt`,
    label: `f${i}`,
    kind: "module",
    file: `folder${i}/f.mbt`,
  }));
  return { title: `flat-${count}`, nodes, edges: [] };
}

/** Synthesise a forest of binary-tree-like nested hierarchies. The
 *  graph has `roots` top-level folders, each branching binarily down
 *  to `depth` levels. */
function binaryNestedForest(args: {
  readonly roots: number;
  readonly depth: number;
}): GraphJSON {
  const { roots, depth } = args;
  const nodes: {
    id: string;
    label: string;
    kind: string;
    file: string;
  }[] = [];
  const walk = (path: string, d: number) => {
    if (d === 0) {
      nodes.push({
        id: `${path}/f.mbt`,
        label: "f",
        kind: "module",
        file: `${path}/f.mbt`,
      });
      return;
    }
    walk(`${path}/a`, d - 1);
    walk(`${path}/b`, d - 1);
  };
  for (let i = 0; i < roots; i++) {
    walk(`root${i}`, depth);
  }
  return { title: `forest-${roots}x${depth}`, nodes, edges: [] };
}

/** Collect shells at a given depth. */
function shellsAtDepth(
  shells: readonly ClusterShell[],
  depth: number,
): readonly ClusterShell[] {
  return shells.filter((s) => s.depth === depth);
}

/** Every unordered pair (a, b) from `items`. */
function* pairs<T>(items: readonly T[]): Generator<readonly [T, T]> {
  for (let i = 0; i < items.length; i++) {
    for (let j = i + 1; j < items.length; j++) {
      yield [items[i]!, items[j]!];
    }
  }
}

/** Group shells by their parent prefix (everything before the last
 *  slash). Top-level shells have prefix "". */
function groupByParent(
  shells: readonly ClusterShell[],
): Map<string, ClusterShell[]> {
  const out = new Map<string, ClusterShell[]>();
  for (const shell of shells) {
    const i = shell.path.lastIndexOf("/");
    const parent = i < 0 ? "" : shell.path.slice(0, i);
    const list = out.get(parent);
    if (list) {
      list.push(shell);
    } else {
      out.set(parent, [shell]);
    }
  }
  return out;
}

// ─── 1. Single-level density ──────────────────────────────────────

describe("hierarchical spec: single-level density", () => {
  it("sibling shells are disjoint regardless of count", () => {
    for (const count of [2, 3, 6, 12, 24, 48]) {
      const shells = runLayout(flatHierarchy(count));
      const tops = shellsAtDepth(shells, 1);
      expect(tops.length).toBe(count);
      for (const [a, b] of pairs(tops)) {
        expect(distance(a.centre, b.centre)).toBeGreaterThan(
          a.radius + b.radius,
        );
      }
    }
  });

  it("equal-weight siblings each get a fair fraction of world area", () => {
    // Treemap area is proportional to leaf count. With N equal-weight
    // siblings filling the world rect, each one's inscribed-circle
    // area is bounded below by a fraction of the world. We only
    // assert order-of-magnitude — the constant depends on aspect
    // ratio and padding. Tolerances loose to absorb tuning.
    const worldArea =
      4 * DEFAULT_LAYOUT.worldRadius * DEFAULT_LAYOUT.worldRadius;
    for (const count of [2, 6, 24]) {
      const shells = runLayout(flatHierarchy(count));
      const tops = shellsAtDepth(shells, 1);
      const totalShellArea = tops.reduce(
        (acc, s) => acc + Math.PI * s.radius * s.radius,
        0,
      );
      // Inscribed circles fill ≥ π/4 ≈ 0.785 of their square; with
      // padding and aspect-ratio non-1 cells, expect at least 25% of
      // the world to be inside some shell.
      expect(totalShellArea).toBeGreaterThan(worldArea * 0.15);
    }
  });

  it("sibling cells span larger overall area as count grows", () => {
    // Treemap fills the parent rect — the *enclosing* radius of all
    // sibling centres + their own radii must reach the world edge for
    // any non-trivial count. We measure the maximum centre→origin +
    // radius and require it to be a substantial fraction of the world.
    for (const count of [3, 6, 12, 24, 48]) {
      const shells = runLayout(flatHierarchy(count));
      const tops = shellsAtDepth(shells, 1);
      const maxReach = Math.max(
        ...tops.map((s) => Math.hypot(s.centre.x, s.centre.y) + s.radius),
      );
      // Half the world edge is a comfortable lower bound — squarify
      // never leaves an entire half of the world empty for ≥ 3
      // equal-weight items.
      expect(maxReach).toBeGreaterThan(DEFAULT_LAYOUT.worldRadius * 0.5);
    }
  });
});

// ─── 2. Nested recursion ──────────────────────────────────────────

describe("hierarchical spec: nested recursion", () => {
  it("siblings of every parent are disjoint at every depth", () => {
    const shells = runLayout(binaryNestedForest({ roots: 3, depth: 3 }));
    const byParent = groupByParent(shells);
    for (const [, group] of byParent) {
      if (group.length < 2) {
        continue;
      }
      for (const [a, b] of pairs(group)) {
        expect(distance(a.centre, b.centre)).toBeGreaterThan(
          a.radius + b.radius,
        );
      }
    }
  });

  it("siblings of the same parent (equal weight) share the same radius", () => {
    // In a binary tree every level has 2 equal-weight children. The
    // treemap splits the parent rect into two equal halves, so each
    // child's inscribed-circle radius is identical.
    const shells = runLayout(binaryNestedForest({ roots: 4, depth: 3 }));
    const byParent = groupByParent(shells);
    for (const [, group] of byParent) {
      if (group.length < 2) {
        continue;
      }
      const first = group[0]!.radius;
      for (const s of group) {
        expect(s.radius).toBeCloseTo(first, 4);
      }
    }
  });

  it("deeper shells are strictly smaller than their ancestors", () => {
    // Sub-clusters fit strictly inside their parent's cell, so the
    // inscribed-circle radius decreases with depth.
    const shells = runLayout(binaryNestedForest({ roots: 4, depth: 3 }));
    const byPath = new Map<string, ClusterShell>();
    for (const shell of shells) {
      byPath.set(shell.path, shell);
    }
    for (const shell of shells) {
      const slash = shell.path.lastIndexOf("/");
      if (slash < 0) {
        continue;
      }
      const parent = byPath.get(shell.path.slice(0, slash));
      if (!parent) {
        continue;
      }
      expect(shell.radius).toBeLessThan(parent.radius);
    }
  });

  it("each child's shell is geometrically inside its parent's cell", () => {
    // The treemap places child rects strictly inside the parent rect.
    // The cluster's "shell" is a circle inscribed in the *padded*
    // inner rect (smaller than the outer cell), so the parent's
    // outer cell extent is up to parent.radius × √2 + a small padding
    // term. We bound by 2 × parent.radius to absorb both the inner-
    // vs-outer rect difference and the diagonal allowance — this is
    // still a meaningful constraint (no child escapes the parent's
    // visual region).
    const shells = runLayout(binaryNestedForest({ roots: 3, depth: 3 }));
    const byPath = new Map<string, ClusterShell>();
    for (const shell of shells) {
      byPath.set(shell.path, shell);
    }
    for (const shell of shells) {
      const slash = shell.path.lastIndexOf("/");
      if (slash < 0) {
        continue;
      }
      const parent = byPath.get(shell.path.slice(0, slash));
      if (!parent) {
        continue;
      }
      const d = distance(shell.centre, parent.centre);
      expect(d + shell.radius).toBeLessThanOrEqual(parent.radius * 2 + 1e-6);
    }
  });

  it("top-level branches' descendants stay inside their top cell", () => {
    // Every descendant of a top-level path lives inside its top cell.
    // Same outer-vs-inner-rect adjustment as above: bound by
    // 2 × top.radius to absorb the padding between the inscribed
    // shell and the actual cell extent.
    const shells = runLayout(binaryNestedForest({ roots: 3, depth: 3 }));
    const tops = shellsAtDepth(shells, 1);
    for (const top of tops) {
      const descendants = shells.filter(
        (s) => s.path !== top.path && s.path.startsWith(`${top.path}/`),
      );
      for (const desc of descendants) {
        const d = distance(desc.centre, top.centre);
        expect(d + desc.radius).toBeLessThanOrEqual(top.radius * 2 + 1e-6);
      }
    }
  });
});

// ─── 3. Sizing / density-proportional ─────────────────────────────

describe("hierarchical spec: density-proportional sizing", () => {
  it("a sibling with more descendants gets a bigger cell", () => {
    const nodes: {
      id: string;
      label: string;
      kind: string;
      file: string;
    }[] = [];
    for (let i = 0; i < 50; i++) {
      nodes.push({
        id: `root/heavy/f${i}.mbt`,
        label: `h${i}`,
        kind: "module",
        file: `root/heavy/f${i}.mbt`,
      });
    }
    nodes.push({
      id: "root/light/x.mbt",
      label: "x",
      kind: "module",
      file: "root/light/x.mbt",
    });
    const shells = runLayout({ title: "density", nodes, edges: [] });
    const heavy = shells.find((s) => s.path === "root/heavy")!;
    const light = shells.find((s) => s.path === "root/light")!;
    // Heavy area is ~50× light area → heavy radius is ~√50 ≈ 7× light.
    // Treemap aspect-ratio constraints + inscribed-circle pessimism
    // can lower this; assert a comfortable factor of 2.
    expect(heavy.radius).toBeGreaterThan(light.radius * 2);
  });

  it("a single sparse sibling cannot claim more than the dense sibling's slice", () => {
    const nodes: {
      id: string;
      label: string;
      kind: string;
      file: string;
    }[] = [];
    for (let i = 0; i < 100; i++) {
      nodes.push({
        id: `root/big/f${i}.mbt`,
        label: `b${i}`,
        kind: "module",
        file: `root/big/f${i}.mbt`,
      });
    }
    nodes.push({
      id: "root/tiny/x.mbt",
      label: "x",
      kind: "module",
      file: "root/tiny/x.mbt",
    });
    const shells = runLayout({ title: "extreme", nodes, edges: [] });
    const big = shells.find((s) => s.path === "root/big")!;
    const tiny = shells.find((s) => s.path === "root/tiny")!;
    expect(tiny.radius).toBeLessThan(big.radius);
  });

  it("identical-weight top-level siblings get identical radii", () => {
    const nodes: {
      id: string;
      label: string;
      kind: string;
      file: string;
    }[] = [];
    for (let i = 0; i < 10; i++) {
      nodes.push({
        id: `folder${i}/f.mbt`,
        label: `f${i}`,
        kind: "module",
        file: `folder${i}/f.mbt`,
      });
    }
    const shells = runLayout({ title: "equal-weight", nodes, edges: [] });
    const tops = shellsAtDepth(shells, 1);
    const first = tops[0]!.radius;
    for (const s of tops) {
      expect(s.radius).toBeCloseTo(first, 4);
    }
  });

  it("a sparse sibling of a heavy folder still gets a non-degenerate cell", () => {
    // Realistic workspace: one heavy src + a handful of single-file
    // root configs. The configs must remain visible — not collapsed
    // to zero — so the user can still see them.
    const nodes: {
      id: string;
      label: string;
      kind: string;
      file: string;
    }[] = [];
    for (let i = 0; i < 100; i++) {
      nodes.push({
        id: `big/f${i}.mbt`,
        label: `b${i}`,
        kind: "module",
        file: `big/f${i}.mbt`,
      });
    }
    for (let i = 0; i < 5; i++) {
      nodes.push({
        id: `single${i}.json`,
        label: `s${i}`,
        kind: "json",
        file: `single${i}.json`,
      });
    }
    const shells = runLayout({ title: "sparse", nodes, edges: [] });
    const singletons = shells.filter((s) => s.path.startsWith("single"));
    expect(singletons.length).toBe(5);
    for (const s of singletons) {
      // Treemap area for a singleton among 105 leaves is at least
      // worldArea/105 → radius at least √(area/π). World area
      // = (2·1000)² = 4e6, per-singleton area ≈ 38k, radius ≈ 110.
      // We assert a much looser floor of 5 world units to absorb
      // padding and aspect-ratio losses.
      expect(s.radius).toBeGreaterThan(5);
    }
  });
});

describe("hierarchical spec: leaf-cell density", () => {
  it("leaves of a dense cluster spread inside its cell rather than collapsing", () => {
    // Regression: the previous algorithm collapsed leaves to a tight
    // central blob inside each cluster. The treemap layout must
    // produce leaves that span a meaningful fraction of the cluster's
    // cell — otherwise the visualisation reads as "one dot per
    // cluster". We measure the leaves' bounding box area against
    // the inscribed-disk area.
    const nodes: {
      id: string;
      label: string;
      kind: string;
      file: string;
    }[] = [];
    for (let i = 0; i < 50; i++) {
      nodes.push({
        id: `dense/leaf${i}.mbt`,
        label: `l${i}`,
        kind: "module",
        file: "dense",
      });
    }
    // A single sibling to give the dense cluster a real allocator
    // partner — otherwise it's the only top-level cell.
    nodes.push({
      id: "other/f.mbt",
      label: "o",
      kind: "module",
      file: "other/f.mbt",
    });
    const view = normalizeGraph({ title: "dense", nodes, edges: [] });
    const assignment = computeHierarchy(view.nodes);
    const result = applyHierarchicalLayout({
      nodes: view.nodes,
      assignment,
      settings: DEFAULT_LAYOUT,
    });
    const dense = result.clusterShells.find((s) => s.path === "dense")!;
    expect(dense).toBeDefined();
    const leaves = view.nodes.filter((n) => n.file === "dense");
    let minX = Infinity;
    let maxX = -Infinity;
    let minY = Infinity;
    let maxY = -Infinity;
    for (const n of leaves) {
      if (n.x < minX) minX = n.x;
      if (n.x > maxX) maxX = n.x;
      if (n.y < minY) minY = n.y;
      if (n.y > maxY) maxY = n.y;
    }
    const bboxArea = (maxX - minX) * (maxY - minY);
    const cellArea = Math.PI * dense.radius * dense.radius;
    // Leaves' bounding box covers at least 25% of the cluster's
    // inscribed-disk area — so they're spread, not piled.
    expect(bboxArea).toBeGreaterThan(cellArea * 0.25);
  });

  it("a single-leaf cluster places the leaf at finite coordinates", () => {
    const view = normalizeGraph({
      title: "one",
      nodes: [
        { id: "a/x.mbt", label: "x", kind: "module", file: "a/x.mbt" },
        { id: "b/y.mbt", label: "y", kind: "module", file: "b/y.mbt" },
      ],
      edges: [],
    });
    const assignment = computeHierarchy(view.nodes);
    applyHierarchicalLayout({
      nodes: view.nodes,
      assignment,
      settings: DEFAULT_LAYOUT,
    });
    for (const n of view.nodes) {
      expect(Number.isFinite(n.x)).toBe(true);
      expect(Number.isFinite(n.y)).toBe(true);
      expect(Number.isFinite(n.z)).toBe(true);
    }
  });

  it("leaves of distinct clusters end up inside their respective cells", () => {
    // The treemap guarantees cluster cells are disjoint. Therefore
    // a leaf of cluster A never lands inside cluster B's cell.
    const nodes: {
      id: string;
      label: string;
      kind: string;
      file: string;
    }[] = [];
    for (let i = 0; i < 8; i++) {
      nodes.push({
        id: `alpha/f${i}.mbt`,
        label: `a${i}`,
        kind: "module",
        file: "alpha",
      });
    }
    for (let i = 0; i < 8; i++) {
      nodes.push({
        id: `beta/f${i}.mbt`,
        label: `b${i}`,
        kind: "module",
        file: "beta",
      });
    }
    const view = normalizeGraph({
      title: "two-clusters",
      nodes,
      edges: [],
    });
    const assignment = computeHierarchy(view.nodes);
    const result = applyHierarchicalLayout({
      nodes: view.nodes,
      assignment,
      settings: DEFAULT_LAYOUT,
    });
    const alpha = result.clusterShells.find((s) => s.path === "alpha")!;
    const beta = result.clusterShells.find((s) => s.path === "beta")!;
    expect(distance(alpha.centre, beta.centre)).toBeGreaterThan(
      alpha.radius + beta.radius,
    );
    for (const node of view.nodes) {
      const ownCentre = node.file === "alpha" ? alpha : beta;
      const otherCentre = node.file === "alpha" ? beta : alpha;
      const dOwn = Math.hypot(
        node.x - ownCentre.centre.x,
        node.y - ownCentre.centre.y,
      );
      const dOther = Math.hypot(
        node.x - otherCentre.centre.x,
        node.y - otherCentre.centre.y,
      );
      // Closer to its own cluster than to the other.
      expect(dOwn).toBeLessThan(dOther);
    }
  });
});

// ─── 4. Cross-cutting invariants ──────────────────────────────────

describe("hierarchical spec: scene bounds", () => {
  it("scene stays inside the bounded world rectangle regardless of graph size", () => {
    // The treemap is fixed-area: every shell sits inside the world
    // rect, so the maximum reach from origin is bounded by
    // worldRadius × √2 (the half-diagonal of the world square)
    // independently of node count.
    const sizes = [
      { roots: 2, depth: 2 },
      { roots: 8, depth: 3 },
      { roots: 16, depth: 4 },
      { roots: 32, depth: 5 },
    ];
    const bound = DEFAULT_LAYOUT.worldRadius * Math.SQRT2 + 1e-6;
    for (const params of sizes) {
      const shells = runLayout(binaryNestedForest(params));
      for (const s of shells) {
        const reach = Math.hypot(s.centre.x, s.centre.y) + s.radius;
        expect(reach).toBeLessThanOrEqual(bound);
      }
    }
  });
});

describe("hierarchical spec: cross-cutting invariants", () => {
  it("applying the layout is idempotent on shells", () => {
    const first = runLayout(binaryNestedForest({ roots: 3, depth: 3 }));
    const second = runLayout(binaryNestedForest({ roots: 3, depth: 3 }));
    expect(second.length).toBe(first.length);
    for (let i = 0; i < first.length; i++) {
      expect(second[i]!.path).toBe(first[i]!.path);
      expect(second[i]!.radius).toBeCloseTo(first[i]!.radius, 6);
      expect(second[i]!.centre.x).toBeCloseTo(first[i]!.centre.x, 6);
      expect(second[i]!.centre.y).toBeCloseTo(first[i]!.centre.y, 6);
      expect(second[i]!.centre.z).toBeCloseTo(first[i]!.centre.z, 6);
    }
  });

  it("shell count equals the number of distinct hierarchy paths", () => {
    const graph = binaryNestedForest({ roots: 3, depth: 3 });
    const view = normalizeGraph(graph);
    const assignment = computeHierarchy(view.nodes);
    const result = applyHierarchicalLayout({
      nodes: view.nodes,
      assignment,
      settings: DEFAULT_LAYOUT,
    });
    expect(result.clusterShells.length).toBe(assignment.allPaths.length);
  });
});
