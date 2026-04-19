/**
 * @file Contract tests for cluster-overlap resolution.
 *
 * Pins the invariant that after `resolveClusterOverlaps` no pair of
 * clusters overlaps. Also verifies the "re-read centre every inner
 * iteration" fix: if a cluster moves during round i, subsequent
 * comparisons in the same round must see the new position.
 */

import { describe, expect, it } from "vitest";
import type { Vec3, ViewNode } from "../../types.ts";
import { resolveClusterOverlaps, translateCluster } from "./overlaps.ts";

function mkMember(id: string, pos: Vec3): ViewNode {
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
    vx: 0,
    vy: 0,
    vz: 0,
    pinned: false,
  };
}

function singleMemberCluster(
  id: string,
  centre: Vec3,
): {
  clusters: Map<string, ViewNode[]>;
  centres: Map<string, Vec3>;
} {
  const m = mkMember(`${id}/m`, centre);
  return {
    clusters: new Map([[id, [m]]]),
    centres: new Map([[id, centre]]),
  };
}

function mergeFixtures(
  parts: readonly {
    clusters: Map<string, ViewNode[]>;
    centres: Map<string, Vec3>;
  }[],
): { clusters: Map<string, ViewNode[]>; centres: Map<string, Vec3> } {
  const clusters = new Map<string, ViewNode[]>();
  const centres = new Map<string, Vec3>();
  for (const p of parts) {
    for (const [k, v] of p.clusters) {
      clusters.set(k, v);
    }
    for (const [k, v] of p.centres) {
      centres.set(k, v);
    }
  }
  return { clusters, centres };
}

function distance(a: Vec3, b: Vec3): number {
  const dx = a.x - b.x;
  const dy = a.y - b.y;
  const dz = a.z - b.z;
  return Math.sqrt(dx * dx + dy * dy + dz * dz);
}

describe("translateCluster", () => {
  it("applies (to − from) to every member", () => {
    const m1 = mkMember("m1", { x: 0, y: 0, z: 0 });
    const m2 = mkMember("m2", { x: 1, y: 1, z: 1 });
    translateCluster([m1, m2], { x: 0, y: 0, z: 0 }, { x: 10, y: 20, z: 30 });
    expect(m1.x).toBe(10);
    expect(m1.y).toBe(20);
    expect(m1.z).toBe(30);
    expect(m2.x).toBe(11);
    expect(m2.y).toBe(21);
    expect(m2.z).toBe(31);
  });

  it("no-op when from equals to", () => {
    const m = mkMember("m", { x: 5, y: 5, z: 5 });
    translateCluster([m], { x: 10, y: 20, z: 30 }, { x: 10, y: 20, z: 30 });
    expect(m.x).toBe(5);
  });
});

describe("resolveClusterOverlaps — invariants", () => {
  it("is a no-op when fewer than 2 clusters", () => {
    const { clusters, centres } = singleMemberCluster("A", {
      x: 0,
      y: 0,
      z: 0,
    });
    resolveClusterOverlaps({
      clusters,
      centres,
      innerRadii: new Map([["A", 10]]),
    });
    expect(centres.get("A")).toEqual({ x: 0, y: 0, z: 0 });
  });

  it("leaves already-disjoint clusters alone", () => {
    const a = singleMemberCluster("A", { x: 0, y: 0, z: 0 });
    const b = singleMemberCluster("B", { x: 1000, y: 0, z: 0 });
    const { clusters, centres } = mergeFixtures([a, b]);
    const beforeA = { ...centres.get("A")! };
    const beforeB = { ...centres.get("B")! };
    resolveClusterOverlaps({
      clusters,
      centres,
      innerRadii: new Map([
        ["A", 10],
        ["B", 10],
      ]),
    });
    expect(centres.get("A")).toEqual(beforeA);
    expect(centres.get("B")).toEqual(beforeB);
  });

  it("separates an overlapping pair until disjoint", () => {
    // Two clusters sharing a centre. Must be pushed apart so
    // centre-distance exceeds ra+rb (+ padding).
    const a = singleMemberCluster("A", { x: 0, y: 0, z: 0 });
    const b = singleMemberCluster("B", { x: 5, y: 0, z: 0 });
    const { clusters, centres } = mergeFixtures([a, b]);
    resolveClusterOverlaps({
      clusters,
      centres,
      innerRadii: new Map([
        ["A", 30],
        ["B", 30],
      ]),
    });
    const d = distance(centres.get("A")!, centres.get("B")!);
    // After resolution, centre distance ≥ ra + rb.
    // The measured radius is max(member-dist, planned) + padding.
    // For single-member clusters the max-dist is 0, so radius =
    // planned + padding = 30 + 12 = 42 per side.
    expect(d).toBeGreaterThanOrEqual(42 + 42 - 1e-6);
  });

  it("handles triple overlap — all pairs end disjoint", () => {
    // Three clusters at almost the same point. After resolution
    // every pair must be separated.
    const a = singleMemberCluster("A", { x: 0, y: 0, z: 0 });
    const b = singleMemberCluster("B", { x: 2, y: 0, z: 0 });
    const c = singleMemberCluster("C", { x: 0, y: 2, z: 0 });
    const { clusters, centres } = mergeFixtures([a, b, c]);
    resolveClusterOverlaps({
      clusters,
      centres,
      innerRadii: new Map([
        ["A", 20],
        ["B", 20],
        ["C", 20],
      ]),
    });
    const ids = ["A", "B", "C"];
    const minSep = 20 + 20 + 12 + 12 - 1e-6; // ra + rb with paddings
    for (let i = 0; i < ids.length; i++) {
      for (let j = i + 1; j < ids.length; j++) {
        const d = distance(centres.get(ids[i]!)!, centres.get(ids[j]!)!);
        expect(d).toBeGreaterThanOrEqual(minSep);
      }
    }
  });

  it("moves members in lockstep with their cluster centre", () => {
    // Internal structure is preserved: every member is translated
    // by the same delta as the centre.
    const mA = mkMember("A/1", { x: 0, y: 0, z: 0 });
    const mA2 = mkMember("A/2", { x: 5, y: 3, z: 0 }); // 5,3,0 offset
    const mB = mkMember("B/1", { x: 2, y: 0, z: 0 });
    const clusters = new Map([
      ["A", [mA, mA2]],
      ["B", [mB]],
    ]);
    const centres = new Map<string, Vec3>([
      ["A", { x: 0, y: 0, z: 0 }],
      ["B", { x: 2, y: 0, z: 0 }],
    ]);
    resolveClusterOverlaps({
      clusters,
      centres,
      innerRadii: new Map([
        ["A", 30],
        ["B", 30],
      ]),
    });
    // After resolution mA2 should still be at offset (5,3,0) from mA.
    expect(mA2.x - mA.x).toBeCloseTo(5, 6);
    expect(mA2.y - mA.y).toBeCloseTo(3, 6);
    expect(mA2.z - mA.z).toBeCloseTo(0, 6);
  });

  it("handles coincident centres without NaN", () => {
    // The coincident-centre branch picks an arbitrary axis. Just
    // verify no NaN leaks through and the pair is separated.
    const a = singleMemberCluster("A", { x: 0, y: 0, z: 0 });
    const b = singleMemberCluster("B", { x: 0, y: 0, z: 0 });
    const { clusters, centres } = mergeFixtures([a, b]);
    resolveClusterOverlaps({
      clusters,
      centres,
      innerRadii: new Map([
        ["A", 20],
        ["B", 20],
      ]),
    });
    const ca = centres.get("A")!;
    const cb = centres.get("B")!;
    for (const v of [ca.x, ca.y, ca.z, cb.x, cb.y, cb.z]) {
      expect(Number.isFinite(v)).toBe(true);
    }
    expect(distance(ca, cb)).toBeGreaterThan(0);
  });

  it("regression: uses the current centre inside each inner iteration", () => {
    // A→B push could leave A stale if the loop re-used an
    // outer-scope snapshot. Verify: after resolution both pairs
    // (A,B) and (A,C) are disjoint, which requires A's updated
    // position to be seen when comparing against C.
    const a = singleMemberCluster("A", { x: 0, y: 0, z: 0 });
    const b = singleMemberCluster("B", { x: 1, y: 0, z: 0 }); // forces A left
    const c = singleMemberCluster("C", { x: -30, y: 0, z: 0 }); // was on A's left
    const { clusters, centres } = mergeFixtures([a, b, c]);
    resolveClusterOverlaps({
      clusters,
      centres,
      innerRadii: new Map([
        ["A", 25],
        ["B", 25],
        ["C", 25],
      ]),
    });
    const minSep = 25 + 25 + 12 + 12 - 1e-6;
    expect(
      distance(centres.get("A")!, centres.get("B")!),
    ).toBeGreaterThanOrEqual(minSep);
    expect(
      distance(centres.get("A")!, centres.get("C")!),
    ).toBeGreaterThanOrEqual(minSep);
    expect(
      distance(centres.get("B")!, centres.get("C")!),
    ).toBeGreaterThanOrEqual(minSep);
  });
});
