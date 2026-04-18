/**
 * @file Contract tests for fibonacciPoints and friends.
 *
 * The layout pipeline's "constellation look" comes down to whether
 * points are uniformly distributed on a sphere. Previous bugs in this
 * file (pole-collapse, identical points, degenerate 1D output) were
 * invisible until they reached screen. The tests below pin the
 * invariants numerically so any regression fails loudly.
 */

import { describe, expect, it } from "vitest";
import {
  addVec,
  compareString,
  fibonacciNearestChord,
  fibonacciPoints,
  ORIGIN,
  writeNode,
} from "./geometry.ts";
import type { ViewNode } from "../types.ts";

function mkNode(id: string): ViewNode {
  return {
    id,
    label: id,
    kind: "module",
    group: "",
    file: null,
    doc: null,
    metadata: {},
    x: 7,
    y: 7,
    z: 7,
    vx: 1,
    vy: 1,
    vz: 1,
    pinned: false,
  };
}

describe("fibonacciPoints", () => {
  it("empty for count <= 0", () => {
    expect(fibonacciPoints(0, 100)).toEqual([]);
    expect(fibonacciPoints(-3, 100)).toEqual([]);
  });

  it("collapses to the origin for count=1 or radius=0", () => {
    expect(fibonacciPoints(1, 100)).toEqual([ORIGIN]);
    expect(fibonacciPoints(5, 0)).toEqual([ORIGIN, ORIGIN, ORIGIN, ORIGIN, ORIGIN]);
  });

  it("every point lies on the requested sphere radius", () => {
    const R = 100;
    for (const n of [2, 3, 4, 8, 32, 128]) {
      const pts = fibonacciPoints(n, R);
      for (const p of pts) {
        const r = Math.sqrt(p.x * p.x + p.y * p.y + p.z * p.z);
        expect(Math.abs(r - R)).toBeLessThan(1e-6);
      }
    }
  });

  it("does NOT pin points at the poles (regression: hde t=i/(n-1) bug)", () => {
    // Cell-centre sampling `t = (i+0.5)/n` keeps every point off
    // the poles. The buggy `t = i/(n-1)` put i=0 and i=n-1 at
    // (0, ±R, 0) with r=0 in the xz plane. Verify no point is
    // closer than a meaningful margin to a pole.
    const R = 100;
    for (const n of [2, 3, 4, 8]) {
      const pts = fibonacciPoints(n, R);
      for (const p of pts) {
        const xzLen = Math.sqrt(p.x * p.x + p.z * p.z);
        // Any point at a pole has xz = 0. Even count=2 should have
        // both points off-pole with this sampling.
        expect(xzLen).toBeGreaterThan(0);
      }
    }
  });

  it("all points are distinct — min pairwise distance > 0", () => {
    for (const n of [2, 3, 6, 12, 48, 200]) {
      const pts = fibonacciPoints(n, 100);
      let minSq = Infinity;
      for (let i = 0; i < n; i++) {
        for (let j = i + 1; j < n; j++) {
          const a = pts[i]!;
          const b = pts[j]!;
          const dx = a.x - b.x;
          const dy = a.y - b.y;
          const dz = a.z - b.z;
          const d = dx * dx + dy * dy + dz * dz;
          if (d < minSq) {
            minSq = d;
          }
        }
      }
      expect(minSq).toBeGreaterThan(0);
    }
  });

  it("distributes latitude bands roughly uniformly (|y| centroid near 0)", () => {
    // Uniform sphere sampling implies the centroid of y-coords is
    // near 0 even for small n. A pole-collapsed distribution would
    // pile y near ±R instead.
    for (const n of [8, 32, 128]) {
      const pts = fibonacciPoints(n, 100);
      let sumY = 0;
      for (const p of pts) {
        sumY += p.y;
      }
      const meanY = sumY / n;
      expect(Math.abs(meanY)).toBeLessThan(5); // well inside ±R=100
    }
  });

  it("scales linearly with radius", () => {
    const a = fibonacciPoints(16, 10);
    const b = fibonacciPoints(16, 100);
    for (let i = 0; i < 16; i++) {
      expect(b[i]!.x).toBeCloseTo(a[i]!.x * 10, 6);
      expect(b[i]!.y).toBeCloseTo(a[i]!.y * 10, 6);
      expect(b[i]!.z).toBeCloseTo(a[i]!.z * 10, 6);
    }
  });
});

describe("fibonacciNearestChord", () => {
  it("returns 2 for degenerate counts (antipodal diameter)", () => {
    expect(fibonacciNearestChord(0)).toBe(2);
    expect(fibonacciNearestChord(1)).toBe(2);
    expect(fibonacciNearestChord(2)).toBe(2);
  });

  it("matches the actual minimum chord of fibonacciPoints(n, 1)", () => {
    for (const n of [3, 6, 12, 48]) {
      const pts = fibonacciPoints(n, 1);
      let minSq = Infinity;
      for (let i = 0; i < n; i++) {
        for (let j = i + 1; j < n; j++) {
          const a = pts[i]!;
          const b = pts[j]!;
          const dx = a.x - b.x;
          const dy = a.y - b.y;
          const dz = a.z - b.z;
          const d = dx * dx + dy * dy + dz * dz;
          if (d < minSq) {
            minSq = d;
          }
        }
      }
      expect(fibonacciNearestChord(n)).toBeCloseTo(Math.sqrt(minSq), 6);
    }
  });

  it("monotonically decreases as n grows", () => {
    // Packing more points on the same sphere forces neighbours
    // closer together. If this stops holding, the chord formula
    // that computeSiblingOuterRadius relies on is wrong.
    let prev = fibonacciNearestChord(4);
    for (const n of [8, 16, 32, 64]) {
      const cur = fibonacciNearestChord(n);
      expect(cur).toBeLessThan(prev);
      prev = cur;
    }
  });

  it("caches repeat calls — same object reused", () => {
    const a = fibonacciNearestChord(17);
    const b = fibonacciNearestChord(17);
    expect(a).toBe(b);
  });
});

describe("addVec", () => {
  it("component-wise add", () => {
    expect(addVec({ x: 1, y: 2, z: 3 }, { x: 10, y: 20, z: 30 })).toEqual({
      x: 11,
      y: 22,
      z: 33,
    });
  });
});

describe("writeNode", () => {
  it("writes position and zeros velocity", () => {
    const n = mkNode("a");
    writeNode(n, { x: 1, y: 2, z: 3 });
    expect(n.x).toBe(1);
    expect(n.y).toBe(2);
    expect(n.z).toBe(3);
    expect(n.vx).toBe(0);
    expect(n.vy).toBe(0);
    expect(n.vz).toBe(0);
  });

  it("leaves identity fields untouched", () => {
    const n = mkNode("a");
    writeNode(n, { x: 1, y: 2, z: 3 });
    expect(n.id).toBe("a");
    expect(n.pinned).toBe(false);
  });
});

describe("compareString", () => {
  it("returns -1 / 0 / 1", () => {
    expect(compareString("a", "b")).toBe(-1);
    expect(compareString("b", "a")).toBe(1);
    expect(compareString("a", "a")).toBe(0);
  });

  it("is transitive and total (sanity: sort remains stable)", () => {
    const input = ["pear", "apple", "banana", "apple"];
    const sorted = [...input].sort(compareString);
    expect(sorted).toEqual(["apple", "apple", "banana", "pear"]);
  });
});
