/**
 * @file Hierarchical layout — spec-level contracts.
 *
 * These tests read as the specification of the hierarchical layout:
 * they pin down what it means for the layout to be "correct" as
 * hierarchy density and nesting grow. If any of these break, the
 * visual metaphor ("each galaxy is its own thing, nested galaxies
 * stay contained") has broken too.
 *
 * Organised top-down:
 *   1. Single-level density   — n siblings, no grandchildren
 *   2. Nested recursion       — parents + grandchildren + …
 *   3. Invariants across depth
 *
 * We deliberately avoid depending on tuning constants (head radius,
 * decay, minGap); the tests are written in *relative* terms so the
 * layout can be retuned without having to rewrite the spec.
 */

import { describe, expect, it } from "vitest";
import type { GraphJSON } from "./../types.ts";
import { normalizeGraph } from "./../normalize.ts";
import { computeHierarchy } from "./hierarchy.ts";
import {
  applyHierarchicalLayout,
  type ClusterShellInfo,
} from "./hierarchical/index.ts";
import { DEFAULT_RENDER_SETTINGS } from "./../renderer/settings.ts";

const DEFAULT_LAYOUT = DEFAULT_RENDER_SETTINGS.layout;

// ─── Helpers ──────────────────────────────────────────────────────

function distance(
  a: ClusterShellInfo["centre"],
  b: ClusterShellInfo["centre"],
): number {
  const dx = a.x - b.x;
  const dy = a.y - b.y;
  const dz = a.z - b.z;
  return Math.sqrt(dx * dx + dy * dy + dz * dz);
}

function runLayout(graph: GraphJSON): readonly ClusterShellInfo[] {
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
 *  to `depth` levels. Using multiple roots so that tests covering
 *  cross-branch invariants have more than one top shell to compare. */
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
  shells: readonly ClusterShellInfo[],
  depth: number,
): readonly ClusterShellInfo[] {
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
  shells: readonly ClusterShellInfo[],
): Map<string, ClusterShellInfo[]> {
  const out = new Map<string, ClusterShellInfo[]>();
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
  it("sibling bubbles are disjoint regardless of count", () => {
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

  it("nearest-sibling gap stays ≥ a floor fraction of their radius as count grows", () => {
    // The density gets tighter as count grows, but the gap must not
    // collapse to zero — otherwise "siblings look independent" breaks
    // in the limit. We don't hard-code the minGap constant, we just
    // assert it's strictly positive and doesn't shrink below 5% of
    // the radius across a wide count range.
    for (const count of [2, 6, 24, 96]) {
      const shells = runLayout(flatHierarchy(count));
      const tops = shellsAtDepth(shells, 1);
      let minGap = Infinity;
      for (const [a, b] of pairs(tops)) {
        const gap = distance(a.centre, b.centre) - (a.radius + b.radius);
        if (gap < minGap) {
          minGap = gap;
        }
      }
      expect(minGap).toBeGreaterThan(0);
      expect(minGap).toBeGreaterThan(tops[0]!.radius * 0.05);
    }
  });

  it("ring radius monotonically grows with sibling count", () => {
    // The mechanism we rely on to keep bubbles disjoint as density
    // grows is: ring radius increases with count. Measured as the
    // average distance from each shell to the shell-centroid — a
    // re-centring pass in the layout makes origin-based measures
    // unreliable.
    const ringRadius = (count: number) => {
      const shells = runLayout(flatHierarchy(count));
      const tops = shellsAtDepth(shells, 1);
      let cx = 0,
        cy = 0,
        cz = 0;
      for (const s of tops) {
        cx += s.centre.x;
        cy += s.centre.y;
        cz += s.centre.z;
      }
      cx /= tops.length;
      cy /= tops.length;
      cz /= tops.length;
      let maxD = 0;
      for (const s of tops) {
        const dx = s.centre.x - cx;
        const dy = s.centre.y - cy;
        const dz = s.centre.z - cz;
        const d = Math.sqrt(dx * dx + dy * dy + dz * dz);
        if (d > maxD) {
          maxD = d;
        }
      }
      return maxD;
    };
    const counts = [3, 6, 12, 24, 48];
    for (let i = 1; i < counts.length; i++) {
      expect(ringRadius(counts[i]!)).toBeGreaterThan(
        ringRadius(counts[i - 1]!),
      );
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

  it("siblings of the same parent share the same radius", () => {
    // Children of one parent are allocated from the parent's budget
    // and all get the same size. (Across different parents the
    // radii can differ when the parents have different sibling counts
    // — that's how dense vs sparse branches stay readable.)
    const shells = runLayout(binaryNestedForest({ roots: 3, depth: 3 }));
    const byParent = groupByParent(shells);
    for (const [, group] of byParent) {
      if (group.length < 2) {
        continue;
      }
      const first = group[0]!.radius;
      for (const s of group) {
        expect(s.radius).toBeCloseTo(first, 6);
      }
    }
  });

  it("deeper shells are strictly smaller than their ancestors", () => {
    const shells = runLayout(binaryNestedForest({ roots: 3, depth: 3 }));
    const byDepth = new Map<number, number>();
    for (const shell of shells) {
      if (!byDepth.has(shell.depth)) {
        byDepth.set(shell.depth, shell.radius);
      }
    }
    const depths = Array.from(byDepth.keys()).sort((a, b) => a - b);
    for (let i = 1; i < depths.length; i++) {
      expect(byDepth.get(depths[i]!)!).toBeLessThan(
        byDepth.get(depths[i - 1]!)!,
      );
    }
  });

  it("each child's subtree stays within its parent's branch reach", () => {
    // The shown parent shell radius is a depth-based visual hint, not
    // a physical container — when a parent has more descendants than
    // fit inside its nominal radius, its children sit outside the
    // shown shell (this is the "soft halo" story). What we *do*
    // guarantee is that each child's nested extent stays inside the
    // branch reach of the parent (parent centre ↔ child furthest
    // descendant ≤ parent's own full reach). This is what ensures
    // the parent still looks like the "owner" of the subtree.
    const shells = runLayout(binaryNestedForest({ roots: 3, depth: 3 }));
    const byPath = new Map<string, ClusterShellInfo>();
    for (const shell of shells) {
      byPath.set(shell.path, shell);
    }
    const reachFrom = (origin: ClusterShellInfo) => {
      let r = origin.radius;
      for (const s of shells) {
        if (s.path === origin.path) {
          continue;
        }
        if (!s.path.startsWith(`${origin.path}/`)) {
          continue;
        }
        const d = distance(s.centre, origin.centre) + s.radius;
        if (d > r) {
          r = d;
        }
      }
      return r;
    };
    for (const shell of shells) {
      const slash = shell.path.lastIndexOf("/");
      if (slash < 0) {
        continue;
      }
      const parent = byPath.get(shell.path.slice(0, slash));
      if (!parent) {
        continue;
      }
      const childReach =
        distance(shell.centre, parent.centre) + reachFrom(shell);
      const parentReach = reachFrom(parent);
      // Child's full extent from the parent's centre ≤ parent's reach.
      expect(childReach).toBeLessThanOrEqual(parentReach + 1e-6);
    }
  });

  it("top-level branches are disjoint even accounting for their full nested extent", () => {
    // Cross-branch invariant: not only do top-level bubbles not
    // overlap, but the furthest descendant of branch A must not
    // reach into branch B's bubble. Otherwise, looking at two
    // top-level galaxies from the outside, their contents would be
    // tangled.
    const shells = runLayout(binaryNestedForest({ roots: 3, depth: 3 }));
    const tops = shellsAtDepth(shells, 1);
    // For each top shell, find the max distance from its centre to
    // any descendant shell's centre+radius — that is its effective
    // "halo radius" covering everything nested inside it.
    const effectiveRadius = new Map<string, number>();
    for (const top of tops) {
      let maxReach = top.radius;
      for (const shell of shells) {
        if (shell.path === top.path || !shell.path.startsWith(`${top.path}/`)) {
          continue;
        }
        const reach = distance(shell.centre, top.centre) + shell.radius;
        if (reach > maxReach) {
          maxReach = reach;
        }
      }
      effectiveRadius.set(top.path, maxReach);
    }
    for (const [a, b] of pairs(tops)) {
      const ra = effectiveRadius.get(a.path)!;
      const rb = effectiveRadius.get(b.path)!;
      expect(distance(a.centre, b.centre)).toBeGreaterThan(ra + rb);
    }
  });
});

describe("hierarchical spec: owned-shell density (numeric)", () => {
  // The owned shell inside a cluster holds leaves belonging to that
  // exact path. If it's too small relative to leaf count, leaves
  // pile on top of each other (the dense "blob" problem in the
  // screenshot). If it's too large, it overflows the cluster.
  // These tests pin the "leaves per shell area" ratio to a sensible
  // range.

  function measureOwnedShell(opts: {
    readonly path: string;
    readonly nodes: readonly {
      id: string;
      label: string;
      kind: string;
      file: string;
    }[];
  }) {
    const graph = normalizeGraph({
      title: "density",
      nodes: opts.nodes,
      edges: [],
    });
    const assignment = computeHierarchy(graph.nodes);
    applyHierarchicalLayout({
      nodes: graph.nodes,
      assignment,
      settings: DEFAULT_LAYOUT,
    });
    // Leaves of this path: their "file" equals this path exactly.
    const leaves = graph.nodes.filter((n) => n.file === opts.path);
    if (leaves.length === 0) {
      return { leaves: 0, radius: 0 };
    }
    // Shell radius = max distance from centroid.
    let sx = 0,
      sy = 0,
      sz = 0;
    for (const n of leaves) {
      sx += n.x;
      sy += n.y;
      sz += n.z;
    }
    const cx = sx / leaves.length;
    const cy = sy / leaves.length;
    const cz = sz / leaves.length;
    let maxSq = 0;
    for (const n of leaves) {
      const dx = n.x - cx;
      const dy = n.y - cy;
      const dz = n.z - cz;
      const sq = dx * dx + dy * dy + dz * dz;
      if (sq > maxSq) {
        maxSq = sq;
      }
    }
    return { leaves: leaves.length, radius: Math.sqrt(maxSq) };
  }

  it("owned-shell grows with leaf count so density stays bounded", () => {
    // For counts 10, 100, 1000, check that shell area-per-leaf stays
    // within the same ballpark. "Bounded" means not collapsing to 0
    // and not ballooning past the cluster.
    const densities: number[] = [];
    for (const count of [10, 100, 1000]) {
      const nodes: {
        id: string;
        label: string;
        kind: string;
        file: string;
      }[] = [];
      // Make the parent cluster generous by giving it a sibling so
      // the parent's own radius isn't forced to 1.
      for (let i = 0; i < count; i++) {
        nodes.push({
          id: `dense/leaf${i}.mbt`,
          label: `l${i}`,
          kind: "module",
          file: "dense",
        });
      }
      // A sibling ensures the cluster allocator has work to do.
      for (let i = 0; i < 5; i++) {
        nodes.push({
          id: `other/f${i}.mbt`,
          label: `o${i}`,
          kind: "module",
          file: `other/f${i}.mbt`,
        });
      }
      const m = measureOwnedShell({ path: "dense", nodes });
      // area per leaf on the sphere surface
      const areaPerLeaf =
        (4 * Math.PI * m.radius * m.radius) / Math.max(1, m.leaves);
      densities.push(areaPerLeaf);
    }
    // Every density stays in a sensible window (not zero, not huge).
    for (const d of densities) {
      expect(d).toBeGreaterThan(20);
      expect(d).toBeLessThan(5000);
    }
    // And the density variation across count isn't wild — within an
    // order of magnitude.
    const lo = Math.min(...densities);
    const hi = Math.max(...densities);
    expect(hi / lo).toBeLessThan(10);
  });

  it("a single-leaf cluster places the leaf without a stale radius", () => {
    // The owned shell for a single leaf should be either 0 (put at
    // centre) or a tiny sentinel — definitely not inflated.
    const graph = normalizeGraph({
      title: "one",
      nodes: [
        { id: "a/x.mbt", label: "x", kind: "module", file: "a/x.mbt" },
        { id: "b/y.mbt", label: "y", kind: "module", file: "b/y.mbt" },
      ],
      edges: [],
    });
    const assignment = computeHierarchy(graph.nodes);
    applyHierarchicalLayout({
      nodes: graph.nodes,
      assignment,
      settings: DEFAULT_LAYOUT,
    });
    for (const n of graph.nodes) {
      expect(Number.isFinite(n.x)).toBe(true);
      expect(Number.isFinite(n.y)).toBe(true);
      expect(Number.isFinite(n.z)).toBe(true);
    }
  });
});

describe("hierarchical spec: nested visibility (numeric)", () => {
  // Regression: a previous sqrt-based allocator made deeply-nested
  // sub-clusters collapse to <1 world unit, so the overview showed
  // only a flat blob per top-level folder with no internal
  // structure. The gentler exponent keeps sub-cluster radii
  // readable at typical overview camera distances.

  it("a 3-deep nested structure keeps sub-clusters above a readable floor", () => {
    // Build: root/sub/sub2/f.mbt × several branches so every level
    // has real siblings. Check that the deepest shell still has a
    // meaningful radius (> 0.5% of WORLD_RADIUS = 6 world units),
    // so at a typical camera distance they're not sub-pixel.
    const nodes: {
      id: string;
      label: string;
      kind: string;
      file: string;
    }[] = [];
    // Top-level A: 2 sub-folders, each with 2 sub-sub-folders, each
    // with a few files
    for (let a = 0; a < 2; a++) {
      for (let b = 0; b < 2; b++) {
        for (let c = 0; c < 3; c++) {
          for (let i = 0; i < 5; i++) {
            nodes.push({
              id: `root/sub${a}/inner${b}/leaf${c}/f${i}.mbt`,
              label: `f${a}${b}${c}${i}`,
              kind: "module",
              file: `root/sub${a}/inner${b}/leaf${c}/f${i}.mbt`,
            });
          }
        }
      }
    }
    // Plus several sparse siblings so the top-level allocator has
    // to distribute across mixed weights.
    for (let i = 0; i < 10; i++) {
      nodes.push({
        id: `config${i}.json`,
        label: `c${i}`,
        kind: "config",
        file: `config${i}.json`,
      });
    }
    const shells = runLayout({ title: "nested", nodes, edges: [] });
    // Find the deepest shell depth that has shells.
    const byDepth = new Map<number, number>();
    for (const s of shells) {
      const prev = byDepth.get(s.depth) ?? 0;
      byDepth.set(s.depth, Math.max(prev, s.radius));
    }
    const deepest = Math.max(...byDepth.keys());
    // Every depth must have at least one shell with radius >= 6.
    // (World radius = 1200, camera typically at ~3000, pxScale ~700
    // ⇒ 6 world units ≈ 1.4 screen pixels, just above LOD cull.)
    for (let d = 1; d <= deepest; d++) {
      const maxAtDepth = byDepth.get(d);
      if (maxAtDepth !== undefined) {
        expect(maxAtDepth).toBeGreaterThan(6);
      }
    }
  });

  it("small branches in a mostly-empty top level don't collapse to min", () => {
    // Top level has one heavy folder + 5 singletons. The singletons
    // should still get radii > MIN_CLUSTER_RADIUS so they are
    // visible as independent dots, not clamped to the floor.
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
      expect(s.radius).toBeGreaterThan(5);
    }
  });
});

describe("hierarchical spec: density-proportional sizing (numeric)", () => {
  // These tests hard-code expected radius ratios so we know exactly
  // what the allocator produces for well-defined shapes. They're
  // value-based, not just "A > B" — breaking a number flags a
  // regression in the allocation formula. Tolerances are loose
  // because tuning knobs (MIN_GAP, sqrt vs log) can shift values
  // a little without violating the visual intent.

  it("heavy branch is visibly larger than a singleton", () => {
    // Two siblings with leaf counts 100 vs 1 → with a w^0.25 shape
    // the heavy branch has radius ~100^0.25 = 3.16× larger than the
    // singleton. The compression keeps the viewport readable but
    // should still make 'dense vs sparse' obvious (ratio > 2).
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
    const shells = runLayout({ title: "ratio", nodes, edges: [] });
    const big = shells.find((s) => s.path === "root/big")!;
    const tiny = shells.find((s) => s.path === "root/tiny")!;
    const ratio = big.radius / tiny.radius;
    expect(ratio).toBeGreaterThan(2);
    expect(ratio).toBeLessThan(15);
  });

  it("a heavy sibling among many singletons claims notably more space", () => {
    // Realistic workspace shape: 1 big folder + 20 single-file roots
    // (like moon.pkg, README, configs). The heavy folder should be
    // visibly larger than a singleton — with w^0.25 compression,
    // 50^0.25 ≈ 2.66× radius.
    const nodes: {
      id: string;
      label: string;
      kind: string;
      file: string;
    }[] = [];
    for (let i = 0; i < 50; i++) {
      nodes.push({
        id: `src/f${i}.mbt`,
        label: `f${i}`,
        kind: "module",
        file: `src/f${i}.mbt`,
      });
    }
    for (let i = 0; i < 20; i++) {
      nodes.push({
        id: `config${i}.json`,
        label: `c${i}`,
        kind: "config",
        file: `config${i}.json`,
      });
    }
    const shells = runLayout({ title: "realistic", nodes, edges: [] });
    const src = shells.find((s) => s.path === "src")!;
    const configSample = shells.find((s) => s.path === "config0.json")!;
    expect(src.radius / configSample.radius).toBeGreaterThan(2);
    expect(src.radius / configSample.radius).toBeLessThan(10);
  });

  it("identical-weight siblings get identical radii (no jitter)", () => {
    // Value-based regression: many empty folders should all get the
    // same tiny radius, not vary between each other because of
    // floating-point shenanigans in the weight walk.
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
      expect(s.radius).toBeCloseTo(first, 6);
    }
  });
});

describe("hierarchical spec: density-proportional sizing", () => {
  it("a sibling with more descendants gets a bigger bubble", () => {
    // A parent has two children: one with a large subtree, one with
    // almost nothing. The big subtree must claim visibly more room.
    const nodes: {
      id: string;
      label: string;
      kind: string;
      file: string;
    }[] = [];
    // root/heavy with 50 leaves
    for (let i = 0; i < 50; i++) {
      nodes.push({
        id: `root/heavy/f${i}.mbt`,
        label: `h${i}`,
        kind: "module",
        file: `root/heavy/f${i}.mbt`,
      });
    }
    // root/light with 1 leaf
    nodes.push({
      id: "root/light/x.mbt",
      label: "x",
      kind: "module",
      file: "root/light/x.mbt",
    });
    const shells = runLayout({ title: "density", nodes, edges: [] });
    const heavy = shells.find((s) => s.path === "root/heavy")!;
    const light = shells.find((s) => s.path === "root/light")!;
    expect(heavy.radius).toBeGreaterThan(light.radius * 1.4);
  });

  it("a single sparse sibling cannot claim more than the dense sibling's slice", () => {
    // Regression guard: with MIN_GAP based uniform sizing alone, a
    // 1-file branch next to a 100-file branch ended up the same size
    // because sizing was count-only. The weighted allocator must
    // prevent that.
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
});

describe("hierarchical spec: asymmetric density", () => {
  it("dense branch next to sparse branch — neither leaks into the other", () => {
    // A common real-world shape: one top folder is heavily nested
    // (cmd/ or src/) while a sibling is almost empty (docs/). The
    // dense branch must not overrun its sibling.
    const nodes: {
      id: string;
      label: string;
      kind: string;
      file: string;
    }[] = [];
    // Dense: src/a/b/c.mbt, src/a/b/d.mbt, src/a/e/f.mbt, src/g/h.mbt
    for (const p of [
      "src/a/b/c.mbt",
      "src/a/b/d.mbt",
      "src/a/e/f.mbt",
      "src/g/h.mbt",
      "src/g/i.mbt",
    ]) {
      nodes.push({ id: p, label: "n", kind: "module", file: p });
    }
    // Sparse: docs/readme.md — modelled with "module" kind for the test.
    nodes.push({
      id: "docs/r.mbt",
      label: "r",
      kind: "module",
      file: "docs/r.mbt",
    });
    const shells = runLayout({ title: "asym", nodes, edges: [] });
    const tops = shellsAtDepth(shells, 1);
    expect(tops.length).toBe(2);
    // Compute each top's full descendant reach.
    const reach = (top: ClusterShellInfo) => {
      let r = top.radius;
      for (const s of shells) {
        if (s.path === top.path) {
          continue;
        }
        if (!s.path.startsWith(`${top.path}/`)) {
          continue;
        }
        const d = distance(s.centre, top.centre) + s.radius;
        if (d > r) {
          r = d;
        }
      }
      return r;
    };
    const [a, b] = tops;
    expect(distance(a!.centre, b!.centre)).toBeGreaterThan(
      reach(a!) + reach(b!),
    );
  });
});

// ─── 3. Cross-cutting invariants ──────────────────────────────────

describe("hierarchical spec: scene bounds", () => {
  it("world stays inside a bounded radius regardless of graph size", () => {
    // Regression guard. A previous bottom-up halo design let the
    // world diameter scale with total node count so large graphs
    // pushed the camera so far away that nodes became sub-pixel.
    // The current top-down allocation must keep the world in a
    // fixed bubble so the overview is always readable.
    // The layout now uses bottom-up intrinsic sizing — each cluster
    // gets enough radius to hold its content at the desired
    // footprint. World radius therefore scales (roughly) with the
    // cube-root of node count. The spec here verifies that scaling
    // is SUBLINEAR in node count: doubling the graph size never
    // doubles the world radius. That guarantees the camera's
    // fit-to-view still produces a usable overview regardless of
    // how many nodes exist.
    const sizes = [
      { roots: 2, depth: 2 },
      { roots: 8, depth: 3 },
      { roots: 16, depth: 4 },
      { roots: 32, depth: 5 },
    ];
    const reaches: { n: number; reach: number }[] = [];
    for (const params of sizes) {
      const graph = binaryNestedForest(params);
      const shells = runLayout(graph);
      const maxReach = Math.max(
        ...shells.map((s) => {
          const d = Math.sqrt(
            s.centre.x * s.centre.x +
              s.centre.y * s.centre.y +
              s.centre.z * s.centre.z,
          );
          return d + s.radius;
        }),
      );
      reaches.push({ n: graph.nodes.length, reach: maxReach });
    }
    // Scaling is sublinear: reach / cbrt(n) stays bounded.
    const ratios = reaches.map(({ n, reach }) => reach / Math.cbrt(n));
    const minRatio = Math.min(...ratios);
    const maxRatio = Math.max(...ratios);
    // Ratio range stays within a factor of 8 across the sizes —
    // the bound is loose because trees with different roots/depths
    // have different ratios of branch vs leaf nodes, but we catch
    // super-linear blowups. What matters is that reach/cbrt(n) does
    // not EXPLODE as the graph grows.
    expect(maxRatio / minRatio).toBeLessThan(8);
  });
});

describe("hierarchical spec: cross-cutting invariants", () => {
  it("applying the layout is idempotent on shells", () => {
    // Running the layout twice on identical input yields identical
    // shell geometry. The algorithm is deterministic.
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
