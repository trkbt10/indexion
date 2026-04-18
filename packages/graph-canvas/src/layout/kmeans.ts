/**
 * @file 3D k-means clustering.
 *
 * Takes a set of points in R³ and groups them into K clusters. Uses
 * Lloyd's algorithm with k-means++ seeding for a good initial
 * partition, then iterates until assignments converge (or a step cap
 * is hit).
 *
 * In this codebase the input is an HDE (High-Dimensional Embedding)
 * projection of the graph: connected nodes end up near each other in
 * 3D, so k-means on those coordinates discovers topology-driven
 * clusters without any path / folder assumption.
 */

export type Vec3 = {
  readonly x: number;
  readonly y: number;
  readonly z: number;
};

export type KMeansResult = {
  /** For each input point (in the same order as `points`), the index
   *  of its assigned cluster [0, k). */
  readonly assignment: Int32Array;
  /** Cluster centroids in the same 3D space as the input points. */
  readonly centroids: readonly Vec3[];
  /** How many Lloyd iterations ran before convergence or the cap. */
  readonly iterations: number;
};

export type KMeansArgs = {
  /** Flat `[x0, y0, z0, x1, y1, z1, ...]` array — faster for tight
   *  loops than an array-of-objects. */
  readonly points: Float64Array;
  readonly k: number;
  /** Hard iteration cap. Lloyd usually converges in <20 on graph
   *  data but pathological inputs can stall otherwise. */
  readonly maxIterations?: number;
  /** Seed for the k-means++ sampling so repeated runs on the same
   *  graph are deterministic. */
  readonly seed?: number;
};

/** Mulberry32 — tiny deterministic PRNG. */
function makeRng(seed: number): () => number {
  let s = seed >>> 0;
  return () => {
    s = (s + 0x6d2b79f5) >>> 0;
    let t = s;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

/** Euclidean squared distance between points i and j in the flat
 *  array (i, j are *point* indices, not element offsets). */
function distSq(points: Float64Array, i: number, c: Vec3): number {
  const dx = points[i * 3]! - c.x;
  const dy = points[i * 3 + 1]! - c.y;
  const dz = points[i * 3 + 2]! - c.z;
  return dx * dx + dy * dy + dz * dz;
}

/** k-means++ seeding: first centre is random; subsequent centres are
 *  drawn with probability proportional to their squared distance to
 *  the nearest already-chosen centre. Spreads seeds out. */
function kmeansPlusPlus(
  points: Float64Array,
  k: number,
  rng: () => number,
): Vec3[] {
  const n = points.length / 3;
  const centroids: Vec3[] = [];
  if (n === 0 || k <= 0) {
    return centroids;
  }
  // First centre: uniformly random.
  const first = Math.floor(rng() * n);
  centroids.push({
    x: points[first * 3]!,
    y: points[first * 3 + 1]!,
    z: points[first * 3 + 2]!,
  });
  const minDistSq = new Float64Array(n);
  // Initialise: distance from first centre.
  for (let i = 0; i < n; i++) {
    minDistSq[i] = distSq(points, i, centroids[0]!);
  }
  while (centroids.length < k) {
    let sum = 0;
    for (let i = 0; i < n; i++) {
      sum += minDistSq[i]!;
    }
    if (sum === 0) {
      // All points already coincide with an existing centre.
      break;
    }
    const pick = rng() * sum;
    let acc = 0;
    let chosen = 0;
    for (let i = 0; i < n; i++) {
      acc += minDistSq[i]!;
      if (acc >= pick) {
        chosen = i;
        break;
      }
    }
    const c: Vec3 = {
      x: points[chosen * 3]!,
      y: points[chosen * 3 + 1]!,
      z: points[chosen * 3 + 2]!,
    };
    centroids.push(c);
    for (let i = 0; i < n; i++) {
      const d = distSq(points, i, c);
      if (d < minDistSq[i]!) {
        minDistSq[i] = d;
      }
    }
  }
  return centroids;
}

/** Lloyd's algorithm: alternately assign points to the nearest
 *  centroid, then recompute each centroid as the mean of its
 *  assigned points. Stops when no assignment changes. */
export function kmeans(args: KMeansArgs): KMeansResult {
  const { points, k } = args;
  const maxIterations = args.maxIterations ?? 50;
  const seed = args.seed ?? 1;
  const n = points.length / 3;

  if (n === 0) {
    return { assignment: new Int32Array(0), centroids: [], iterations: 0 };
  }
  if (k <= 1) {
    // Degenerate: everyone goes to cluster 0, centroid is the mean.
    let sx = 0;
    let sy = 0;
    let sz = 0;
    for (let i = 0; i < n; i++) {
      sx += points[i * 3]!;
      sy += points[i * 3 + 1]!;
      sz += points[i * 3 + 2]!;
    }
    return {
      assignment: new Int32Array(n),
      centroids: [{ x: sx / n, y: sy / n, z: sz / n }],
      iterations: 0,
    };
  }

  const rng = makeRng(seed);
  let centroids = kmeansPlusPlus(points, Math.min(k, n), rng);
  const effectiveK = centroids.length;
  const assignment = new Int32Array(n);
  for (let i = 0; i < n; i++) {
    assignment[i] = -1;
  }

  let iterations = 0;
  for (let iter = 0; iter < maxIterations; iter++) {
    iterations = iter + 1;
    // Assign each point to its nearest centroid.
    let changed = 0;
    for (let i = 0; i < n; i++) {
      let best = 0;
      let bestD = Infinity;
      for (let c = 0; c < effectiveK; c++) {
        const d = distSq(points, i, centroids[c]!);
        if (d < bestD) {
          bestD = d;
          best = c;
        }
      }
      if (assignment[i] !== best) {
        assignment[i] = best;
        changed++;
      }
    }
    if (changed === 0) {
      break;
    }
    // Recompute centroids.
    const sumX = new Float64Array(effectiveK);
    const sumY = new Float64Array(effectiveK);
    const sumZ = new Float64Array(effectiveK);
    const counts = new Int32Array(effectiveK);
    for (let i = 0; i < n; i++) {
      const c = assignment[i]!;
      sumX[c] += points[i * 3]!;
      sumY[c] += points[i * 3 + 1]!;
      sumZ[c] += points[i * 3 + 2]!;
      counts[c]!++;
    }
    const next: Vec3[] = [];
    for (let c = 0; c < effectiveK; c++) {
      if (counts[c]! === 0) {
        // Empty cluster — keep old centroid so it can be reassigned
        // next iteration.
        next.push(centroids[c]!);
      } else {
        next.push({
          x: sumX[c]! / counts[c]!,
          y: sumY[c]! / counts[c]!,
          z: sumZ[c]! / counts[c]!,
        });
      }
    }
    centroids = next;
  }

  return { assignment, centroids, iterations };
}
