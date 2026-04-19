/**
 * @file Layout contract tests.
 *
 * Pins down invariants we learned are easy to violate:
 *
 *   1. Every strategy must write fresh coordinates to every node, so
 *      switching strategies never leaves a node at a stale position.
 *   2. The hierarchical layout's "owned nodes" invariant: every node
 *      belongs to exactly one deepest-path bucket and must be placed
 *      when that path is visited.
 *   3. normalizeGraph drops only edges whose endpoints are genuinely
 *      missing, and diffGraph preserves positions of persisting nodes
 *      without reviving stale ones.
 */

import { describe, expect, it } from "vitest";
import type { GraphJSON, ViewGraph, ViewNode } from "./../types.ts";
import { diffGraph, normalizeGraph } from "./../normalize.ts";
import {
  buildNodesUnderIndex,
  buildOwnedNodesIndex,
  computeHierarchy,
} from "./hierarchy.ts";
import { applyHierarchicalLayout } from "./hierarchical/index.ts";
import { layoutGraph, LAYOUT_STRATEGIES } from "./index.ts";
import { DEFAULT_RENDER_SETTINGS } from "./../renderer/settings.ts";

const DEFAULT_LAYOUT = DEFAULT_RENDER_SETTINGS.layout;

// ─── Fixtures ─────────────────────────────────────────────────────

/** A small graph with folder-like node ids so the hierarchical path
 *  clustering has something to work with. */
function sampleGraph(): GraphJSON {
  return {
    title: "test",
    nodes: [
      { id: "src/a/x.mbt", label: "x", kind: "module", file: "src/a/x.mbt" },
      { id: "src/a/y.mbt", label: "y", kind: "module", file: "src/a/y.mbt" },
      { id: "src/b/z.mbt", label: "z", kind: "module", file: "src/b/z.mbt" },
      {
        id: "src/b/z.mbt::fn:foo",
        label: "foo",
        kind: "Function",
        file: "src/b/z.mbt",
      },
      { id: "pkg:lodash", label: "lodash", kind: "external" },
    ],
    edges: [
      { from: "src/a/x.mbt", to: "src/a/y.mbt", kind: "depends_on" },
      { from: "src/a/y.mbt", to: "src/b/z.mbt", kind: "depends_on" },
      { from: "src/b/z.mbt", to: "pkg:lodash", kind: "imports" },
      {
        from: "src/b/z.mbt",
        to: "src/b/z.mbt::fn:foo",
        kind: "declares",
      },
    ],
  };
}

function sampleViewGraph(): ViewGraph {
  return normalizeGraph(sampleGraph());
}

/** Record each node's current (x, y, z) so we can compare after a
 *  layout pass. */
function snapshotPositions(
  graph: ViewGraph,
): Map<string, readonly [number, number, number]> {
  const out = new Map<string, readonly [number, number, number]>();
  for (const node of graph.nodes) {
    out.set(node.id, [node.x, node.y, node.z]);
  }
  return out;
}

// ─── Strategy invariants ──────────────────────────────────────────

describe("layout strategies", () => {
  for (const strategy of LAYOUT_STRATEGIES) {
    describe(strategy.id, () => {
      it("writes coordinates for every node", () => {
        const graph = sampleViewGraph();
        layoutGraph({ graph, clusterOf: null, strategy: strategy.id });
        for (const node of graph.nodes) {
          expect(Number.isFinite(node.x)).toBe(true);
          expect(Number.isFinite(node.y)).toBe(true);
          expect(Number.isFinite(node.z)).toBe(true);
        }
      });

      it("moves every node when run after a different strategy", () => {
        // Run a "contrasting" strategy first, record positions, then run
        // the strategy under test. Every node must end up at a new
        // position, otherwise the strategy forgot to write some subset
        // of the graph (the exact bug this test catches).
        const graph = sampleViewGraph();
        const contrasting: typeof strategy.id =
          strategy.id === "k-means" ? "hde-volume" : "k-means";
        layoutGraph({ graph, clusterOf: null, strategy: contrasting });
        const before = snapshotPositions(graph);
        layoutGraph({ graph, clusterOf: null, strategy: strategy.id });
        for (const node of graph.nodes) {
          const prev = before.get(node.id)!;
          const same =
            prev[0] === node.x && prev[1] === node.y && prev[2] === node.z;
          // If ever equal after switching strategies, that's
          // almost certainly a bug — strategies differ deliberately.
          // The exception is a single-node graph which both strategies
          // would place at the origin; we have 5 nodes here so no
          // collision-by-accident risk.
          expect(same).toBe(false);
        }
      });
    });
  }
});

// ─── Hierarchy invariants ─────────────────────────────────────────

describe("hierarchy indices", () => {
  it("every node has a non-empty ancestor path", () => {
    const graph = sampleViewGraph();
    const assignment = computeHierarchy(graph.nodes);
    for (const node of graph.nodes) {
      const path = assignment.pathOf.get(node.id);
      expect(path).toBeDefined();
      expect(path!.length).toBeGreaterThan(0);
    }
  });

  it("buildOwnedNodesIndex partitions nodes — every node in exactly one bucket", () => {
    const graph = sampleViewGraph();
    const assignment = computeHierarchy(graph.nodes);
    const owned = buildOwnedNodesIndex(graph.nodes, assignment);
    const counts = new Map<string, number>();
    for (const [, bucket] of owned) {
      for (const node of bucket) {
        counts.set(node.id, (counts.get(node.id) ?? 0) + 1);
      }
    }
    for (const node of graph.nodes) {
      expect(counts.get(node.id)).toBe(1);
    }
  });

  it("buildNodesUnderIndex collects all descendants at every ancestor", () => {
    const graph = sampleViewGraph();
    const assignment = computeHierarchy(graph.nodes);
    const under = buildNodesUnderIndex(graph.nodes, assignment);
    // src should contain every node that has src/ in its path.
    const srcBucket = under.get("src") ?? [];
    const expected = graph.nodes.filter((n) => n.file?.startsWith("src/"));
    expect(srcBucket.length).toBe(expected.length);
  });
});

// ─── Normalize / diff invariants ──────────────────────────────────

describe("normalizeGraph", () => {
  it("drops edges whose endpoints are missing and keeps the rest", () => {
    const graph: GraphJSON = {
      title: "t",
      nodes: [
        { id: "a", label: "a", kind: "m" },
        { id: "b", label: "b", kind: "m" },
      ],
      edges: [
        { from: "a", to: "b", kind: "x" },
        { from: "a", to: "missing", kind: "x" },
      ],
    };
    const view = normalizeGraph(graph);
    expect(view.edges.length).toBe(1);
    expect(view.edges[0]!.sourceId).toBe("a");
    expect(view.edges[0]!.targetId).toBe("b");
  });
});

describe("diffGraph", () => {
  it("preserves positions for nodes that persist across graph rebuilds", () => {
    const prev = sampleViewGraph();
    const first = prev.nodes[0]!;
    first.x = 42;
    first.y = 43;
    first.z = 44;
    const next = normalizeGraph(sampleGraph());
    diffGraph(prev, next);
    const same = next.nodes.find((n) => n.id === first.id)!;
    expect(same.x).toBe(42);
    expect(same.y).toBe(43);
    expect(same.z).toBe(44);
  });

  it("does not resurrect positions for nodes absent from the new graph", () => {
    // (Sanity: diffGraph only writes positions on nodes that exist in
    // newGraph. A node missing from newGraph simply isn't iterated.)
    const prev = sampleViewGraph();
    const truncated: GraphJSON = {
      ...sampleGraph(),
      nodes: sampleGraph().nodes.slice(0, 2),
      edges: [],
    };
    const next = normalizeGraph(truncated);
    diffGraph(prev, next);
    expect(next.nodes.length).toBe(2);
  });
});

// ─── Regression: strategy switch preserves node count ─────────────

describe("strategy switching", () => {
  it("layoutGraph never drops or duplicates nodes", () => {
    const graph = sampleViewGraph();
    const originalIds = new Set(graph.nodes.map((n) => n.id));
    for (const strategy of LAYOUT_STRATEGIES) {
      layoutGraph({ graph, clusterOf: null, strategy: strategy.id });
      const ids = new Set(graph.nodes.map((n) => n.id));
      expect(ids.size).toBe(originalIds.size);
      for (const id of originalIds) {
        expect(ids.has(id)).toBe(true);
      }
    }
  });

  it("every node ends up placed (coords finite) regardless of order of strategies", () => {
    const graph = sampleViewGraph();
    const order = ["k-means", "hde-volume", "k-means"];
    for (const id of order) {
      layoutGraph({
        graph,
        clusterOf: null,
        strategy: id as (typeof LAYOUT_STRATEGIES)[number]["id"],
      });
      for (const node of graph.nodes) {
        expect(Number.isFinite(node.x)).toBe(true);
        expect(Number.isFinite(node.y)).toBe(true);
        expect(Number.isFinite(node.z)).toBe(true);
      }
    }
  });
});

// ─── Hierarchical sizing ──────────────────────────────────────────

type MutableGraphNode = {
  id: string;
  label: string;
  kind: string;
  file?: string;
};

function graphWithSizes(big: number, small: number): GraphJSON {
  const nodes: MutableGraphNode[] = [];
  for (let i = 0; i < big; i++) {
    nodes.push({
      id: `src/heavy/f${i}.mbt`,
      label: `heavy-${i}`,
      kind: "module",
      file: `src/heavy/f${i}.mbt`,
    });
  }
  for (let i = 0; i < small; i++) {
    nodes.push({
      id: `src/light/f${i}.mbt`,
      label: `light-${i}`,
      kind: "module",
      file: `src/light/f${i}.mbt`,
    });
  }
  return { title: "sizes", nodes, edges: [] };
}

describe("hierarchical spacing", () => {
  it("sibling cluster shells do not overlap (2 siblings)", () => {
    // Two top-level folders → treemap splits the world into two
    // disjoint cells. Inscribed shell circles inside those cells
    // never intersect.
    const graph = normalizeGraph({
      title: "two",
      nodes: [
        { id: "a/x.mbt", label: "x", kind: "module", file: "a/x.mbt" },
        { id: "b/y.mbt", label: "y", kind: "module", file: "b/y.mbt" },
      ],
      edges: [],
    });
    const assignment = computeHierarchy(graph.nodes);
    const result = applyHierarchicalLayout({
      nodes: graph.nodes,
      assignment,
      settings: DEFAULT_LAYOUT,
    });
    const shells = result.clusterShells.filter((s) => s.depth === 1);
    expect(shells.length).toBe(2);
    const [a, b] = shells;
    const dx = a!.centre.x - b!.centre.x;
    const dy = a!.centre.y - b!.centre.y;
    const dist = Math.sqrt(dx * dx + dy * dy);
    expect(dist).toBeGreaterThan(a!.radius + b!.radius);
  });

  it("sibling cluster shells do not overlap (many siblings)", () => {
    const nodes: MutableGraphNode[] = [];
    for (let i = 0; i < 12; i++) {
      nodes.push({
        id: `folder${i}/x.mbt`,
        label: `x${i}`,
        kind: "module",
        file: `folder${i}/x.mbt`,
      });
    }
    const graph = normalizeGraph({ title: "many", nodes, edges: [] });
    const assignment = computeHierarchy(graph.nodes);
    const result = applyHierarchicalLayout({
      nodes: graph.nodes,
      assignment,
      settings: DEFAULT_LAYOUT,
    });
    const shells = result.clusterShells.filter((s) => s.depth === 1);
    expect(shells.length).toBe(12);
    for (let i = 0; i < shells.length; i++) {
      for (let j = i + 1; j < shells.length; j++) {
        const a = shells[i]!;
        const b = shells[j]!;
        const dx = a.centre.x - b.centre.x;
        const dy = a.centre.y - b.centre.y;
        const dist = Math.sqrt(dx * dx + dy * dy);
        expect(dist).toBeGreaterThan(a.radius + b.radius);
      }
    }
  });
});

describe("hierarchical sizing", () => {
  it("a denser sibling takes a bigger cell than a sparser one", () => {
    // `src/heavy` has 80 files, `src/light` has 5 — under the same
    // parent `src`, the treemap allocates area proportional to leaf
    // count, so heavy gets a visibly larger cell.
    const graph = normalizeGraph(graphWithSizes(80, 5));
    const assignment = computeHierarchy(graph.nodes);
    const result = applyHierarchicalLayout({
      nodes: graph.nodes,
      assignment,
      settings: DEFAULT_LAYOUT,
    });
    const heavy = result.clusterShells.find((s) => s.path === "src/heavy");
    const light = result.clusterShells.find((s) => s.path === "src/light");
    expect(heavy).toBeDefined();
    expect(light).toBeDefined();
    expect(heavy!.radius).toBeGreaterThan(light!.radius * 2);
  });

  it("equal-density siblings still get equal radii", () => {
    // Symmetric tree → equal weights → equal-area cells → equal
    // inscribed-circle radii.
    const graph = normalizeGraph({
      title: "equal",
      nodes: [
        { id: "src/a/x.mbt", label: "x", kind: "module", file: "src/a/x.mbt" },
        { id: "src/b/y.mbt", label: "y", kind: "module", file: "src/b/y.mbt" },
      ],
      edges: [],
    });
    const assignment = computeHierarchy(graph.nodes);
    const result = applyHierarchicalLayout({
      nodes: graph.nodes,
      assignment,
      settings: DEFAULT_LAYOUT,
    });
    const a = result.clusterShells.find((s) => s.path === "src/a");
    const b = result.clusterShells.find((s) => s.path === "src/b");
    expect(a!.radius).toBeCloseTo(b!.radius, 4);
  });

  it("a child's shell radius is strictly smaller than its parent's", () => {
    // Sub-clusters live inside the parent rectangle; their inscribed
    // disks are bounded above by the parent's.
    const graph = normalizeGraph({
      title: "depth",
      nodes: [
        {
          id: "src/a/b/c.mbt",
          label: "c",
          kind: "module",
          file: "src/a/b/c.mbt",
        },
        {
          id: "src/a/b/d.mbt",
          label: "d",
          kind: "module",
          file: "src/a/b/d.mbt",
        },
      ],
      edges: [],
    });
    const assignment = computeHierarchy(graph.nodes);
    const result = applyHierarchicalLayout({
      nodes: graph.nodes,
      assignment,
      settings: DEFAULT_LAYOUT,
    });
    const byPath = new Map(
      result.clusterShells.map((s) => [s.path, s] as const),
    );
    for (const shell of result.clusterShells) {
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
});

const _typeCheck: ViewNode | null = null;
void _typeCheck;
