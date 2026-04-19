/**
 * @file High-Dimensional Embedding (HDE) graph layout.
 *
 * HDE places nodes in 3-space from a purely structural signal:
 *
 *   1. Pick k pivot nodes that cover the graph (farthest-point then
 *      random sampling for diversity).
 *   2. Compute the BFS distance from every pivot to every node. This
 *      gives each node a k-dim feature vector.
 *   3. Centre the feature matrix column-wise.
 *   4. Project onto the top-3 eigenvectors of the covariance matrix.
 *      Each axis is scaled by √λ so minor axes keep their real spread
 *      (without this, long chains collapse to 1D).
 *
 * Computational cost: O(k · (N + E)) BFS + O(k²) eigensolve. Both are
 * effectively independent of graph size for practical k (~50). One-shot
 * — no iteration loop, no per-tick recomputation.
 *
 * Reference: Harel & Koren, "Graph Drawing by High-Dimensional
 * Embedding" (GD 2002).
 */

import type { Vec3, ViewGraph, ViewNode } from "../types.ts";
import { fibonacciPoints, writeNode as writePosition } from "./geometry.ts";

export type HdeOptions = {
  /** Pivot count. Higher = more accurate, slower. 50 is typical. */
  readonly pivots: number;
  /** Target radius of the resulting embedding (largest axis). */
  readonly radius: number;
  /** Fixed seed so repeated layouts are stable. */
  readonly seed: number;
};

export const DEFAULT_HDE_OPTIONS: HdeOptions = {
  pivots: 50,
  radius: 400,
  seed: 1,
};

/**
 * Turn raw per-axis projections into final node positions. The core
 * HDE pipeline (BFS, PCA, projection) is shared; only this last step
 * differs between strategies — "shell" pins nodes onto the outer
 * surface, "volume" fills the interior, etc.
 */
export type Finaliser = (args: FinaliserArgs) => void;

export type FinaliserArgs = {
  /** Nodes in the same order as the rows of `projected`. */
  readonly nodes: readonly ViewNode[];
  /** Row-major (nodeCount × 3) projected coordinates. Mutable — the
   *  finaliser may rewrite it before calling writePositions. */
  readonly projected: Float32Array;
  readonly centre: Vec3;
  readonly radius: number;
};

export type HdeLayoutArgs = {
  readonly graph: ViewGraph;
  readonly options?: Partial<HdeOptions>;
  /** If given, restrict the layout to this subset of nodes. */
  readonly subset?: ReadonlySet<string>;
  /** Centre of the output embedding. */
  readonly centre?: Vec3;
  /** How to turn the raw projection into final positions. Defaults to
   *  the shell finaliser (largest axis fits `radius`). */
  readonly finalise?: Finaliser;
};

/** Pre-built per-cluster subgraph for the hot path used by
 *  nested-hde: avoids walking the global edge list once per cluster.
 *
 *  - `nodes`: members of this cluster (the order defines the local
 *    indices used by `localAdj`).
 *  - `localAdj[i]` is the list of *local* indices adjacent to local
 *    node i. Built once by the caller from the global edge list,
 *    then reused — turning O(K · |E|) into O(|E| + Σ |E_i|). */
export type PrebuiltSubgraph = {
  readonly nodes: readonly ViewNode[];
  readonly localAdj: readonly (readonly number[])[];
};

export type HdeOnSubgraphArgs = {
  readonly subgraph: PrebuiltSubgraph;
  readonly options?: Partial<HdeOptions>;
  readonly centre?: Vec3;
  readonly finalise?: Finaliser;
};

/**
 * Apply HDE to a graph in place, writing x/y/z on every ViewNode in
 * the subset (or all nodes, if no subset is given). Nodes in different
 * connected components are laid out independently and packed.
 */
export function applyHdeLayout(args: HdeLayoutArgs): void {
  const options = { ...DEFAULT_HDE_OPTIONS, ...args.options };
  const centre = args.centre ?? { x: 0, y: 0, z: 0 };
  const subset = args.subset;
  const finalise = args.finalise ?? shellFinaliser;

  const nodes = subset
    ? args.graph.nodes.filter((n) => subset.has(n.id))
    : args.graph.nodes;
  if (nodes.length === 0) {
    return;
  }
  if (nodes.length === 1) {
    writePosition(nodes[0]!, centre);
    return;
  }

  const indexOf = new Map<string, number>();
  nodes.forEach((node, i) => {
    indexOf.set(node.id, i);
  });
  const adjacency = buildAdjacency(args.graph, indexOf);
  const components = connectedComponents(adjacency, nodes.length);

  // Single connected graph → layout directly at centre.
  if (components.length === 1) {
    layoutComponent({
      nodes,
      adjacency,
      indices: components[0]!,
      options,
      centre,
      finalise,
    });
    return;
  }

  // Multiple components → layout each, then pack radially by size.
  layoutMultipleComponents({
    nodes,
    adjacency,
    components,
    options,
    centre,
    finalise,
  });
}

/**
 * Apply HDE to a pre-built subgraph (nodes + local adjacency).
 *
 * This is the fast path for callers — like `applyNestedHdeLayout` —
 * that loop over many clusters: building the global → cluster
 * adjacency map once and then handing each cluster its own
 * pre-computed subgraph avoids the O(K · |E|) cost of having
 * `applyHdeLayout` re-scan the full edge list per cluster.
 *
 * Single-node subgraphs collapse to writing the node at `centre`.
 * Multiple connected components within the subgraph are handled by
 * the same packing logic as `applyHdeLayout`.
 */
export function applyHdeOnSubgraph(args: HdeOnSubgraphArgs): void {
  const options = { ...DEFAULT_HDE_OPTIONS, ...args.options };
  const centre = args.centre ?? { x: 0, y: 0, z: 0 };
  const finalise = args.finalise ?? shellFinaliser;
  const { nodes, localAdj } = args.subgraph;
  if (nodes.length === 0) {
    return;
  }
  if (nodes.length === 1) {
    writePosition(nodes[0]!, centre);
    return;
  }
  const components = connectedComponents(localAdj, nodes.length);
  if (components.length === 1) {
    layoutComponent({
      nodes,
      adjacency: localAdj,
      indices: components[0]!,
      options,
      centre,
      finalise,
    });
    return;
  }
  layoutMultipleComponents({
    nodes,
    adjacency: localAdj,
    components,
    options,
    centre,
    finalise,
  });
}

// ─── Component decomposition ──────────────────────────────────────

type ComponentPayload = {
  readonly nodes: readonly ViewNode[];
  readonly adjacency: Adjacency;
  readonly indices: readonly number[];
  readonly options: HdeOptions;
  readonly centre: Vec3;
  readonly finalise: Finaliser;
};

function layoutComponent(payload: ComponentPayload): void {
  const { nodes, adjacency, indices, options, centre, finalise } = payload;
  if (indices.length === 0) {
    return;
  }
  if (indices.length === 1) {
    writePosition(nodes[indices[0]!]!, centre);
    return;
  }

  // Build a local adjacency restricted to this component so pivot
  // selection and BFS don't waste time on unreachable nodes.
  const localIndexByGlobal = new Map<number, number>();
  indices.forEach((g, local) => {
    localIndexByGlobal.set(g, local);
  });
  const localAdj: number[][] = indices.map((g) =>
    adjacency[g]!.map((n) => localIndexByGlobal.get(n) ?? -1).filter(
      (n) => n >= 0,
    ),
  );

  const localCount = indices.length;
  const k = Math.min(options.pivots, Math.max(2, localCount));
  const pivots = selectPivots({
    adjacency: localAdj,
    count: k,
    seed: options.seed,
    nodeCount: localCount,
  });

  // distances[j][i] = BFS distance from pivot_j to local node i.
  const distances: Int32Array[] = pivots.map((pivot) =>
    bfsDistances(localAdj, pivot, localCount),
  );

  const featureMatrix = centreColumns(distances, localCount);
  const axes = topPrincipalAxes(featureMatrix, 3, localCount);

  // Project onto each axis and scale by √λ so minor axes keep their
  // proper spread (without this, the minor axes collapse to near zero
  // on chain-like graphs).
  const projected = new Float32Array(localCount * 3);
  for (let i = 0; i < localCount; i++) {
    for (let a = 0; a < 3; a++) {
      const entry = axes[a]!;
      let sum = 0;
      for (let j = 0; j < featureMatrix.length; j++) {
        sum += featureMatrix[j]![i]! * entry.axis[j]!;
      }
      projected[i * 3 + a] = sum * Math.sqrt(Math.max(0, entry.lambda));
    }
  }

  // Clamp axis imbalance: chains naturally have λ1 ≫ λ2 which squashes
  // the layout. Lift the minor axes so all axes contribute visibly.
  balanceAxes(projected, localCount);

  finalise({
    nodes: indices.map((g) => nodes[g]!),
    projected,
    centre,
    radius: options.radius,
  });
}

type MultiArgs = {
  readonly nodes: readonly ViewNode[];
  readonly adjacency: Adjacency;
  readonly components: readonly (readonly number[])[];
  readonly options: HdeOptions;
  readonly centre: Vec3;
  readonly finalise: Finaliser;
};

function layoutMultipleComponents(args: MultiArgs): void {
  const { nodes, adjacency, components, options, centre, finalise } = args;
  const sorted = [...components].sort((a, b) => b.length - a.length);

  // Separate "real" connected components from orphan/small islands.
  // A component qualifies as "real" if its size is at least a
  // meaningful fraction of the largest component. This keeps the
  // main view focused on the payload — a handful of dominant
  // clusters — while banishing long-tail noise (orphans, tiny
  // 3-node islands) to an outer halo.
  const largest = sorted[0]?.length ?? 0;
  const REAL_FRACTION = 0.05;
  const minRealSize = Math.max(8, Math.floor(largest * REAL_FRACTION));
  const real = sorted.filter((c) => c.length >= minRealSize);
  const singletons = sorted.filter((c) => c.length < minRealSize);

  // Area-proportional radii for real components.
  const biggest = real[0]?.length ?? 1;
  const radii = real.map(
    (c) => options.radius * Math.sqrt(c.length / Math.max(1, biggest)),
  );

  // Biggest real component sits at the scene centre; smaller ones
  // arrange in a ring around it. Without this, the biggest component
  // (which usually dominates visually) gets placed at a Fibonacci
  // slot offset from centre — making fitToView zoom out to an
  // awkward off-centre view.
  if (real.length > 0) {
    layoutComponent({
      nodes,
      adjacency,
      indices: real[0]!,
      options: {
        ...options,
        radius: radii[0]!,
        pivots: Math.min(options.pivots, Math.max(2, real[0]!.length)),
      },
      centre,
      finalise,
    });
  }
  // Remaining real components ring around the biggest, pushed just
  // beyond its radius so they don't overlap its payload. The 1.15
  // factor (was 1.6) keeps the ring close to the main payload so
  // edges between the largest component and its satellites don't
  // span half the world — verified visually that 1.6 produced
  // long stretched edges that dominated the canvas.
  if (real.length > 1) {
    const outerRadius = (radii[0] ?? options.radius) * 1.15;
    const ringCentres = fibonacciPoints(real.length - 1, outerRadius);
    for (let i = 1; i < real.length; i++) {
      const c = ringCentres[i - 1] ?? { x: 0, y: 0, z: 0 };
      const subCentre = {
        x: centre.x + c.x,
        y: centre.y + c.y,
        z: centre.z + c.z,
      };
      layoutComponent({
        nodes,
        adjacency,
        indices: real[i]!,
        options: {
          ...options,
          radius: radii[i]!,
          pivots: Math.min(options.pivots, Math.max(2, real[i]!.length)),
        },
        centre: subCentre,
        finalise,
      });
    }
  }

  // Tiny components: spread on an *outer* halo shell so they exist
  // but don't compete with the main constellation. The 1.4 factor
  // (was 2.4) puts the halo just outside the real ring instead of
  // banishing isolated nodes to the far edges of the world — that
  // wide halo turned every cross-cluster edge into a long radial
  // stretch when the user enabled clustering.
  if (singletons.length > 0) {
    const haloRadius = (radii[0] ?? options.radius) * 1.4;
    const haloPoints = fibonacciPoints(singletons.length, haloRadius);
    singletons.forEach((comp, i) => {
      const p = haloPoints[i] ?? { x: 0, y: 0, z: 0 };
      const slotCentre = {
        x: centre.x + p.x,
        y: centre.y + p.y,
        z: centre.z + p.z,
      };
      if (comp.length === 1) {
        const node = nodes[comp[0]!]!;
        node.x = slotCentre.x;
        node.y = slotCentre.y;
        node.z = slotCentre.z;
      } else {
        // Small cluster: place members in a tight ring around the
        // halo slot so 2-3 connected nodes don't stack on the same
        // point.
        const ring = fibonacciPoints(comp.length, 8);
        comp.forEach((nodeIdx, j) => {
          const r = ring[j]!;
          const node = nodes[nodeIdx]!;
          node.x = slotCentre.x + r.x;
          node.y = slotCentre.y + r.y;
          node.z = slotCentre.z + r.z;
        });
      }
    });
  }
}

function connectedComponents(adj: Adjacency, nodeCount: number): number[][] {
  const seen = new Uint8Array(nodeCount);
  const components: number[][] = [];
  for (let start = 0; start < nodeCount; start++) {
    if (seen[start]) {
      continue;
    }
    const queue: number[] = [start];
    seen[start] = 1;
    const comp: number[] = [];
    let head = 0;
    while (head < queue.length) {
      const u = queue[head++]!;
      comp.push(u);
      for (const v of adj[u]!) {
        if (!seen[v]) {
          seen[v] = 1;
          queue.push(v);
        }
      }
    }
    components.push(comp);
  }
  return components;
}

// ─── Adjacency / BFS ──────────────────────────────────────────────

type Adjacency = readonly (readonly number[])[];

function buildAdjacency(
  graph: ViewGraph,
  indexOf: ReadonlyMap<string, number>,
): Adjacency {
  const adj: number[][] = Array.from({ length: indexOf.size }, () => []);
  for (const edge of graph.edges) {
    const s = indexOf.get(edge.sourceId);
    const t = indexOf.get(edge.targetId);
    if (s === undefined || t === undefined || s === t) {
      continue;
    }
    adj[s]!.push(t);
    adj[t]!.push(s);
  }
  return adj;
}

function bfsDistances(
  adj: Adjacency,
  source: number,
  nodeCount: number,
): Int32Array {
  const dist = new Int32Array(nodeCount);
  dist.fill(-1);
  dist[source] = 0;
  const queue: number[] = [source];
  let head = 0;
  while (head < queue.length) {
    const u = queue[head++]!;
    const du = dist[u]!;
    const neighbours = adj[u]!;
    for (const v of neighbours) {
      if (dist[v] !== -1) {
        continue;
      }
      dist[v] = du + 1;
      queue.push(v);
    }
  }
  // Within a single component everything is reachable. If called on a
  // wider adjacency, replace -1 with the component diameter so the
  // unreachable rows don't dominate the feature matrix.
  let diameter = 0;
  for (let i = 0; i < nodeCount; i++) {
    if (dist[i]! > diameter) {
      diameter = dist[i]!;
    }
  }
  const fallback = diameter + 1;
  for (let i = 0; i < nodeCount; i++) {
    if (dist[i] === -1) {
      dist[i] = fallback;
    }
  }
  return dist;
}

// ─── Pivot selection ──────────────────────────────────────────────

type PivotArgs = {
  readonly adjacency: Adjacency;
  readonly count: number;
  readonly seed: number;
  readonly nodeCount: number;
};

/**
 * Pivot selection: first pivot = deterministic seed, second = farthest
 * from it, then alternate farthest-point sampling with weighted random
 * sampling to diversify directions. Pure farthest-point sampling tends
 * to collect endpoints of a chain, which gives HDE a degenerate
 * 1D-looking embedding.
 */
function selectPivots(args: PivotArgs): number[] {
  const { adjacency, count, seed, nodeCount } = args;
  const pivots: number[] = [];
  if (count <= 0 || nodeCount === 0) {
    return pivots;
  }

  const first = ((seed >>> 0) % nodeCount) | 0;
  pivots.push(first);

  const minDist = bfsDistances(adjacency, first, nodeCount);

  let rngState = (seed * 2654435761) >>> 0;
  const nextRand = (): number => {
    rngState = (rngState * 1103515245 + 12345) >>> 0;
    return rngState / 0x100000000;
  };

  for (let p = 1; p < count; p++) {
    // Alternate strategy: even index → farthest, odd → weighted random.
    let chosen: number;
    if (p % 2 === 1) {
      chosen = pickFarthest(minDist);
    } else {
      chosen = pickWeightedRandom(minDist, nextRand);
    }
    if (chosen < 0) {
      break;
    }
    pivots.push(chosen);
    const next = bfsDistances(adjacency, chosen, nodeCount);
    for (let i = 0; i < nodeCount; i++) {
      if (next[i]! < minDist[i]!) {
        minDist[i] = next[i]!;
      }
    }
  }
  return pivots;
}

function pickFarthest(minDist: Int32Array): number {
  let best = -1;
  let bestDist = 0;
  for (let i = 0; i < minDist.length; i++) {
    if (minDist[i]! > bestDist) {
      bestDist = minDist[i]!;
      best = i;
    }
  }
  return best;
}

function pickWeightedRandom(minDist: Int32Array, rand: () => number): number {
  // Probability ∝ minDist[i]², favouring far-but-not-farthest nodes so
  // the next pivot comes from a new direction rather than the opposite
  // extreme of the chain.
  let total = 0;
  for (let i = 0; i < minDist.length; i++) {
    const d = minDist[i]!;
    total += d * d;
  }
  if (total <= 0) {
    return -1;
  }
  let threshold = rand() * total;
  for (let i = 0; i < minDist.length; i++) {
    const d = minDist[i]!;
    threshold -= d * d;
    if (threshold <= 0) {
      return i;
    }
  }
  return minDist.length - 1;
}

// ─── Feature matrix & eigensolve ───────────────────────────────────

function centreColumns(
  distances: readonly Int32Array[],
  nodeCount: number,
): Float32Array[] {
  return distances.map((col) => {
    let sum = 0;
    for (let i = 0; i < nodeCount; i++) {
      sum += col[i]!;
    }
    const mean = sum / nodeCount;
    const centred = new Float32Array(nodeCount);
    for (let i = 0; i < nodeCount; i++) {
      centred[i] = col[i]! - mean;
    }
    return centred;
  });
}

type Axis = {
  readonly axis: Float32Array;
  readonly lambda: number;
};

/**
 * Compute the top `axisCount` principal axes of the k-dimensional
 * feature matrix via power iteration + deflation. Returns each axis
 * paired with its eigenvalue so callers can scale coordinates by √λ.
 */
function topPrincipalAxes(
  columns: Float32Array[],
  axisCount: number,
  nodeCount: number,
): Axis[] {
  const k = columns.length;
  // Gram matrix G = Dᵀ·D / N, k×k symmetric.
  const gram = new Float32Array(k * k);
  for (let a = 0; a < k; a++) {
    const colA = columns[a]!;
    for (let b = a; b < k; b++) {
      const colB = columns[b]!;
      let dot = 0;
      for (let i = 0; i < nodeCount; i++) {
        dot += colA[i]! * colB[i]!;
      }
      const v = dot / nodeCount;
      gram[a * k + b] = v;
      gram[b * k + a] = v;
    }
  }

  const axes: Axis[] = [];
  const work = gram.slice();
  for (let step = 0; step < axisCount; step++) {
    const { axis, lambda } = powerIterate(work, k);
    axes.push({ axis, lambda });
    // Deflate: subtract λ·v·vᵀ so the next iteration lands on the
    // second-largest eigenvector, and so on.
    for (let a = 0; a < k; a++) {
      for (let b = 0; b < k; b++) {
        work[a * k + b] = work[a * k + b]! - lambda * axis[a]! * axis[b]!;
      }
    }
  }
  return axes;
}

function powerIterate(
  matrix: Float32Array,
  k: number,
): { axis: Float32Array; lambda: number } {
  const vec = new Float32Array(k);
  for (let i = 0; i < k; i++) {
    vec[i] = 1 + ((i * 2654435761) % 1024) / 1024;
  }
  normaliseInPlace(vec);

  const next = new Float32Array(k);
  const maxIter = 120;
  const eps = 1e-7;
  let prevLambda = 0;
  let lambda = 0;

  for (let iter = 0; iter < maxIter; iter++) {
    next.fill(0);
    for (let a = 0; a < k; a++) {
      let sum = 0;
      for (let b = 0; b < k; b++) {
        sum += matrix[a * k + b]! * vec[b]!;
      }
      next[a] = sum;
    }
    lambda = 0;
    for (let a = 0; a < k; a++) {
      lambda += next[a]! * vec[a]!;
    }
    normaliseInPlace(next);
    vec.set(next);
    if (iter > 0 && Math.abs(lambda - prevLambda) < eps) {
      break;
    }
    prevLambda = lambda;
  }
  return { axis: vec, lambda };
}

function normaliseInPlace(vec: Float32Array): void {
  let norm = 0;
  for (let i = 0; i < vec.length; i++) {
    norm += vec[i]! * vec[i]!;
  }
  norm = Math.sqrt(norm);
  if (norm < 1e-12) {
    return;
  }
  const inv = 1 / norm;
  for (let i = 0; i < vec.length; i++) {
    vec[i] = vec[i]! * inv;
  }
}

/**
 * When the spectrum is dominated by one axis (chains, cycles) the
 * layout visually collapses to 1D. Compute per-axis RMS and, if the
 * minor axes are less than 35% of the major axis, stretch them up to
 * 45% so the graph occupies meaningful volume.
 */
function balanceAxes(projected: Float32Array, nodeCount: number): void {
  const rms = [0, 0, 0];
  for (let i = 0; i < nodeCount; i++) {
    for (let a = 0; a < 3; a++) {
      const v = projected[i * 3 + a]!;
      rms[a] = rms[a]! + v * v;
    }
  }
  for (let a = 0; a < 3; a++) {
    rms[a] = Math.sqrt(rms[a]! / Math.max(1, nodeCount));
  }
  const major = Math.max(rms[0]!, rms[1]!, rms[2]!);
  if (major < 1e-6) {
    return;
  }
  const targetMinor = major * 0.45;
  const scale = [1, 1, 1];
  for (let a = 0; a < 3; a++) {
    if (rms[a]! < targetMinor && rms[a]! > 1e-6) {
      scale[a] = targetMinor / rms[a]!;
    }
  }
  for (let i = 0; i < nodeCount; i++) {
    for (let a = 0; a < 3; a++) {
      projected[i * 3 + a] = projected[i * 3 + a]! * scale[a]!;
    }
  }
}

// ─── Write back ────────────────────────────────────────────────────

/**
 * Default finaliser. Normalises the projection so the largest axis
 * fits `radius` and shifts the centroid to (0, 0, 0) within that
 * radius, then adds the target centre. HDE projections naturally lie
 * near a sphere shell for connected graphs, so this gives the
 * constellation / "points on a sphere" look.
 */
export const shellFinaliser: Finaliser = (args) => {
  const { nodes, projected, centre, radius } = args;
  const n = nodes.length;

  const mins = [Infinity, Infinity, Infinity];
  const maxs = [-Infinity, -Infinity, -Infinity];
  for (let i = 0; i < n; i++) {
    for (let a = 0; a < 3; a++) {
      const v = projected[i * 3 + a]!;
      if (v < mins[a]!) {
        mins[a] = v;
      }
      if (v > maxs[a]!) {
        maxs[a] = v;
      }
    }
  }
  const spans = [maxs[0]! - mins[0]!, maxs[1]! - mins[1]!, maxs[2]! - mins[2]!];
  // Per-axis normalisation so HDE's dominant eigen-axis doesn't
  // stretch the cluster into an elongated 2-lobe shape. Each axis
  // is scaled so its own span fits `radius * 2`; the result is a
  // roughly cubical spread instead of a pancake. Minor axes get
  // amplified, which is what we want — HDE gives them less range
  // even though they carry real structure.
  const scales = spans.map((s) => (radius * 2) / Math.max(s, 1e-6));
  const cx = (mins[0]! + maxs[0]!) / 2;
  const cy = (mins[1]! + maxs[1]!) / 2;
  const cz = (mins[2]! + maxs[2]!) / 2;

  for (let i = 0; i < n; i++) {
    const node = nodes[i]!;
    node.x = centre.x + (projected[i * 3]! - cx) * scales[0]!;
    node.y = centre.y + (projected[i * 3 + 1]! - cy) * scales[1]!;
    node.z = centre.z + (projected[i * 3 + 2]! - cz) * scales[2]!;
    node.vx = 0;
    node.vy = 0;
    node.vz = 0;
  }
};

/**
 * Volume finaliser. Starts from the shell placement, then remaps the
 * radial distance r ↦ r · (r / r_max)^(1/3) so density is uniform
 * inside the sphere instead of concentrated on its shell. The
 * structural angular arrangement from HDE is preserved; only the
 * radial distribution changes.
 */
export const volumeFinaliser: Finaliser = (args) => {
  const { nodes, centre, radius } = args;
  const n = nodes.length;

  // Start from the shell placement so angular structure is preserved.
  shellFinaliser(args);

  if (n === 0) {
    return;
  }

  // Quantile-based radial remap. The naive cube-root-of-r/rmax
  // approach still clumps when the shell placement already has most
  // points near the outer radius (common for HDE on small clusters),
  // because small differences in r compress into a narrow high-quantile
  // band. Sorting by r and assigning the k-th point to radius
  // R · ((k + 0.5) / N)^(1/3) guarantees uniform-volume density
  // regardless of the input r distribution.
  type Entry = { readonly i: number; readonly r: number };
  const entries: Entry[] = new Array(n);
  for (let i = 0; i < n; i++) {
    const node = nodes[i]!;
    const dx = node.x - centre.x;
    const dy = node.y - centre.y;
    const dz = node.z - centre.z;
    entries[i] = { i, r: Math.sqrt(dx * dx + dy * dy + dz * dz) };
  }
  entries.sort((a, b) => a.r - b.r);

  for (let rank = 0; rank < n; rank++) {
    const { i, r } = entries[rank]!;
    const node = nodes[i]!;
    // (rank + 0.5) / n gives us a quantile in (0, 1); cube root maps
    // the uniform CDF of a 3-ball (density ∝ r²) back onto r in [0, R].
    const newR = radius * Math.cbrt((rank + 0.5) / n);
    if (r < 1e-6) {
      // Node sits on the centre. Nothing to scale — leave in place.
      continue;
    }
    const dx = node.x - centre.x;
    const dy = node.y - centre.y;
    const dz = node.z - centre.z;
    const s = newR / r;
    node.x = centre.x + dx * s;
    node.y = centre.y + dy * s;
    node.z = centre.z + dz * s;
  }
};
