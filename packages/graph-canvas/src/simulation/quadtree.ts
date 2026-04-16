/**
 * @file Barnes-Hut quadtree for O(N log N) repulsion force approximation.
 *
 * Each internal node stores the total mass (node count) and center of mass
 * of all bodies within its bounding box. When computing repulsion on a body,
 * distant groups are treated as single point masses.
 */

import type { ViewNode } from "../types.ts";

type Bounds = { x0: number; y0: number; x1: number; y1: number };

type QuadNode = {
  // Bounding box
  bounds: Bounds;
  // Center of mass
  cx: number;
  cy: number;
  mass: number;
  // Body (leaf only — null for internal nodes with multiple children)
  body: ViewNode | null;
  // Children (null until subdivided)
  nw: QuadNode | null;
  ne: QuadNode | null;
  sw: QuadNode | null;
  se: QuadNode | null;
};

function createQuadNode(bounds: Bounds): QuadNode {
  return { bounds, cx: 0, cy: 0, mass: 0, body: null, nw: null, ne: null, sw: null, se: null };
}

function isLeaf(node: QuadNode): boolean {
  return node.nw === null;
}

function subdivide(node: QuadNode): void {
  const { x0, y0, x1, y1 } = node.bounds;
  const mx = (x0 + x1) / 2;
  const my = (y0 + y1) / 2;
  node.nw = createQuadNode({ x0, y0, x1: mx, y1: my });
  node.ne = createQuadNode({ x0: mx, y0, x1, y1: my });
  node.sw = createQuadNode({ x0, y0: my, x1: mx, y1 });
  node.se = createQuadNode({ x0: mx, y0: my, x1, y1 });
}

function quadrantFor(node: QuadNode, x: number, y: number): QuadNode {
  const mx = (node.bounds.x0 + node.bounds.x1) / 2;
  const my = (node.bounds.y0 + node.bounds.y1) / 2;
  if (x < mx) {
    return y < my ? node.nw! : node.sw!;
  }
  return y < my ? node.ne! : node.se!;
}

function insertBody(root: QuadNode, body: ViewNode): void {
  if (root.mass === 0) {
    // Empty node — place body here
    root.body = body;
    root.cx = body.x;
    root.cy = body.y;
    root.mass = 1;
    return;
  }

  if (isLeaf(root)) {
    // This is a leaf with one body — subdivide and re-insert the existing body
    const existing = root.body!;
    root.body = null;
    subdivide(root);
    // Re-insert existing body
    insertBody(quadrantFor(root, existing.x, existing.y), existing);
  }

  // Insert new body into appropriate quadrant
  insertBody(quadrantFor(root, body.x, body.y), body);

  // Update mass and center of mass
  const totalMass = root.mass + 1;
  root.cx = (root.cx * root.mass + body.x) / totalMass;
  root.cy = (root.cy * root.mass + body.y) / totalMass;
  root.mass = totalMass;
}

/**
 * Apply Barnes-Hut repulsion force to a single body.
 * Traverses the tree, approximating distant groups.
 */
function applyRepulsionToBody(
  node: QuadNode,
  body: ViewNode,
  theta: number,
  strength: number,
  alpha: number,
): void {
  if (node.mass === 0) return;

  const dx = node.cx - body.x;
  const dy = node.cy - body.y;
  const distSq = dx * dx + dy * dy;

  // Skip self
  if (node.mass === 1 && node.body === body) return;

  if (isLeaf(node) || canApproximate(node, distSq, theta)) {
    // Treat as single body at center of mass
    if (distSq < 1) return; // Avoid division by zero for coincident nodes
    const force = (-strength * alpha * node.mass) / distSq;
    const dist = Math.sqrt(distSq);
    body.vx += (dx / dist) * force;
    body.vy += (dy / dist) * force;
    return;
  }

  // Recurse into children
  if (node.nw) applyRepulsionToBody(node.nw, body, theta, strength, alpha);
  if (node.ne) applyRepulsionToBody(node.ne, body, theta, strength, alpha);
  if (node.sw) applyRepulsionToBody(node.sw, body, theta, strength, alpha);
  if (node.se) applyRepulsionToBody(node.se, body, theta, strength, alpha);
}

function canApproximate(node: QuadNode, distSq: number, theta: number): boolean {
  const width = node.bounds.x1 - node.bounds.x0;
  // Barnes-Hut criterion: width / distance < theta
  return (width * width) / distSq < theta * theta;
}

/** Build a quadtree from the given nodes. */
export function buildQuadTree(nodes: readonly ViewNode[]): QuadNode {
  if (nodes.length === 0) {
    return createQuadNode({ x0: 0, y0: 0, x1: 1, y1: 1 });
  }

  // Compute bounding box with margin
  let x0 = Infinity;
  let y0 = Infinity;
  let x1 = -Infinity;
  let y1 = -Infinity;
  for (const n of nodes) {
    if (n.x < x0) x0 = n.x;
    if (n.y < y0) y0 = n.y;
    if (n.x > x1) x1 = n.x;
    if (n.y > y1) y1 = n.y;
  }
  // Expand slightly to avoid boundary issues
  const margin = Math.max(x1 - x0, y1 - y0) * 0.1 + 1;
  x0 -= margin;
  y0 -= margin;
  x1 += margin;
  y1 += margin;

  // Make square (quadtree requires it)
  const size = Math.max(x1 - x0, y1 - y0);
  x1 = x0 + size;
  y1 = y0 + size;

  const root = createQuadNode({ x0, y0, x1, y1 });
  for (const n of nodes) {
    insertBody(root, n);
  }
  return root;
}

/**
 * Apply Barnes-Hut repulsion to all nodes using the given quadtree.
 */
export function applyBarnesHutRepulsion(
  root: QuadNode,
  nodes: readonly ViewNode[],
  theta: number,
  strength: number,
  alpha: number,
): void {
  for (const body of nodes) {
    if (body.pinned) continue;
    applyRepulsionToBody(root, body, theta, strength, alpha);
  }
}
