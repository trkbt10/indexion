/**
 * @file Contract tests for the intra-cluster force relaxation.
 *
 * The relaxation is what turns a kind-band initial placement into a
 * readable internal structure — connected symbols pull together,
 * unconnected symbols spread apart, and every leaf stays inside the
 * cluster bubble. Silent failure modes to catch:
 *
 *   - positions drift outside the bubble (hard clamp not holding)
 *   - NaN if a denominator becomes 0
 *   - velocities leaking past the simulation (must reset)
 *   - connected pairs *farther* apart than unconnected after relax
 */

import { describe, expect, it } from "vitest";
import type { IntraRelaxSettings, ViewNode } from "../../types.ts";
import { relaxInCluster, clampAbs } from "./relax.ts";

const SETTINGS: IntraRelaxSettings = {
  iterations: 12,
  attraction: 0.08,
  repulsion: 30,
  damping: 0.65,
  maxStep: 0.04,
};

function mkNode(id: string, pos: { x: number; y: number; z: number }): ViewNode {
  return {
    id,
    label: id,
    kind: "module",
    group: "",
    file: null,
    doc: null,
    metadata: {},
    x: pos.x,
    y: pos.y,
    z: pos.z,
    vx: 999,
    vy: 999,
    vz: 999,
    pinned: false,
  };
}

function ringNodes(ids: readonly string[], radius: number): ViewNode[] {
  const n = ids.length;
  return ids.map((id, i) => {
    const theta = (i / n) * Math.PI * 2;
    return mkNode(id, {
      x: Math.cos(theta) * radius,
      y: Math.sin(theta) * radius,
      z: 0,
    });
  });
}

function distance(a: ViewNode, b: ViewNode): number {
  const dx = a.x - b.x;
  const dy = a.y - b.y;
  const dz = a.z - b.z;
  return Math.sqrt(dx * dx + dy * dy + dz * dz);
}

function radialDist(
  n: ViewNode,
  centre: { x: number; y: number; z: number },
): number {
  const dx = n.x - centre.x;
  const dy = n.y - centre.y;
  const dz = n.z - centre.z;
  return Math.sqrt(dx * dx + dy * dy + dz * dz);
}

describe("clampAbs", () => {
  it("passes values in range", () => {
    expect(clampAbs(0.5, 1)).toBe(0.5);
    expect(clampAbs(-0.5, 1)).toBe(-0.5);
  });

  it("clamps both signs at the given magnitude", () => {
    expect(clampAbs(5, 1)).toBe(1);
    expect(clampAbs(-5, 1)).toBe(-1);
  });
});

describe("relaxInCluster — invariants", () => {
  const CENTRE = { x: 0, y: 0, z: 0 };
  const RADIUS = 100;

  it("no-op for n < 2", () => {
    const nodes = [mkNode("a", { x: 50, y: 0, z: 0 })];
    const beforeX = nodes[0]!.x;
    relaxInCluster({
      nodes,
      centre: CENTRE,
      radius: RADIUS,
      edges: new Map(),
      settings: SETTINGS,
    });
    expect(nodes[0]!.x).toBe(beforeX);
  });

  it("all nodes stay inside the cluster radius after relax", () => {
    const nodes = ringNodes(["a", "b", "c", "d", "e", "f"], 90);
    const edges = new Map<string, readonly string[]>([
      ["a", ["b"]],
      ["b", ["a", "c"]],
      ["c", ["b", "d"]],
      ["d", ["c"]],
    ]);
    relaxInCluster({
      nodes,
      centre: CENTRE,
      radius: RADIUS,
      edges,
      settings: SETTINGS,
    });
    for (const n of nodes) {
      expect(radialDist(n, CENTRE)).toBeLessThanOrEqual(RADIUS + 1e-6);
    }
  });

  it("all final coordinates are finite (no NaN / ∞)", () => {
    const nodes = ringNodes(["a", "b", "c", "d"], 50);
    relaxInCluster({
      nodes,
      centre: CENTRE,
      radius: RADIUS,
      edges: new Map([["a", ["b"]]]),
      settings: SETTINGS,
    });
    for (const n of nodes) {
      expect(Number.isFinite(n.x)).toBe(true);
      expect(Number.isFinite(n.y)).toBe(true);
      expect(Number.isFinite(n.z)).toBe(true);
    }
  });

  it("velocities are zero at the end of simulation", () => {
    const nodes = ringNodes(["a", "b", "c"], 50);
    relaxInCluster({
      nodes,
      centre: CENTRE,
      radius: RADIUS,
      edges: new Map([["a", ["b"]]]),
      settings: SETTINGS,
    });
    for (const n of nodes) {
      expect(n.vx).toBe(0);
      expect(n.vy).toBe(0);
      expect(n.vz).toBe(0);
    }
  });

  it("connected pairs end up closer than unconnected pairs", () => {
    // Layout: 6 nodes in a ring. Spring connections form a 3-node
    // chain a-b-c; d, e, f are unconnected. After relaxation the
    // a-b / b-c spring neighbours should be closer than any
    // arbitrary non-spring pair.
    const nodes = ringNodes(["a", "b", "c", "d", "e", "f"], 70);
    const edges = new Map<string, readonly string[]>([
      ["a", ["b"]],
      ["b", ["a", "c"]],
      ["c", ["b"]],
    ]);
    relaxInCluster({
      nodes,
      centre: CENTRE,
      radius: RADIUS,
      edges,
      settings: SETTINGS,
    });
    const byId = new Map(nodes.map((n) => [n.id, n]));
    const springDist =
      (distance(byId.get("a")!, byId.get("b")!) +
        distance(byId.get("b")!, byId.get("c")!)) /
      2;
    // Any non-spring pair average as a control.
    const controlDist =
      (distance(byId.get("d")!, byId.get("e")!) +
        distance(byId.get("e")!, byId.get("f")!)) /
      2;
    expect(springDist).toBeLessThan(controlDist);
  });

  it("survives coincident initial positions without NaN", () => {
    // All nodes at the same point — repulsion denominator is
    // smallest here. The +1 epsilon in dsq should keep it finite.
    const nodes = [
      mkNode("a", { x: 0, y: 0, z: 0 }),
      mkNode("b", { x: 0, y: 0, z: 0 }),
      mkNode("c", { x: 0, y: 0, z: 0 }),
    ];
    relaxInCluster({
      nodes,
      centre: CENTRE,
      radius: RADIUS,
      edges: new Map(),
      settings: SETTINGS,
    });
    for (const n of nodes) {
      expect(Number.isFinite(n.x)).toBe(true);
      expect(Number.isFinite(n.y)).toBe(true);
      expect(Number.isFinite(n.z)).toBe(true);
    }
  });

  it("external-to-cluster edges are ignored", () => {
    // Edge 'a' → 'outside' lists a non-member. Relaxation should
    // drop it silently; if it looked up `outside` in indexById
    // without the existence check, this would crash or inject a
    // bogus spring force.
    const nodes = ringNodes(["a", "b"], 50);
    const edges = new Map<string, readonly string[]>([
      ["a", ["outside", "b"]],
      ["b", ["a"]],
    ]);
    expect(() =>
      relaxInCluster({
        nodes,
        centre: CENTRE,
        radius: RADIUS,
        edges,
        settings: SETTINGS,
      }),
    ).not.toThrow();
  });

  it("respects maxStep: single-iteration move cannot exceed radius * maxStep", () => {
    // One iteration with strong repulsion should still not move a
    // node more than `maxStep × radius`. Easy to verify with a
    // starts-at-origin pair that repels to opposite ends.
    const nodes = [
      mkNode("a", { x: 0, y: 0, z: 0 }),
      mkNode("b", { x: 0.01, y: 0, z: 0 }),
    ];
    const oneStep: IntraRelaxSettings = { ...SETTINGS, iterations: 1 };
    relaxInCluster({
      nodes,
      centre: CENTRE,
      radius: 100,
      edges: new Map(),
      settings: oneStep,
    });
    // Max travel per axis after one step must be ≤ radius × maxStep = 4.
    for (const n of nodes) {
      expect(Math.abs(n.x)).toBeLessThanOrEqual(100 * SETTINGS.maxStep + 1e-6);
      expect(Math.abs(n.y)).toBeLessThanOrEqual(100 * SETTINGS.maxStep + 1e-6);
      expect(Math.abs(n.z)).toBeLessThanOrEqual(100 * SETTINGS.maxStep + 1e-6);
    }
  });
});
