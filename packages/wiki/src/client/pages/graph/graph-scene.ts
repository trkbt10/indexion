import * as THREE from "three";
import { OrbitControls } from "three/examples/jsm/controls/OrbitControls.js";
import type { FolderNode, Box3D, GraphTree } from "./graph-types.ts";
import { computeLayout, FLOOR_H, LABEL_ZONE } from "./graph-layout.ts";
import { kindHex } from "../../lib/kind-colors.ts";

// ── Constants ──

const PAD = 0.4;
const WALL = 0.08;

// Camera animation
const FLY_DURATION_MS = 600;
const INITIAL_HEIGHT_FACTOR = 1.2;
const DEFAULT_DISTANCE_FACTOR = 0.85;
const CLICK_DRAG_THRESHOLD_SQ = 25;
const DRAG_CANCEL_THRESHOLD_SQ = 9;

// Focus camera
const FOCUS_MIN_DIST = 4;
const FOCUS_SPAN_FACTOR = 1.5;

// Hover highlight
const HOVER_EMISSIVE = 0x1a3a5c;

const GRAPH_COLORS = [
  0x58a6ff, 0x3fb950, 0xd29922, 0xf85149, 0xbc8cff, 0x79c0ff, 0x56d364,
  0xe3b341,
];

// ── Graph coloring ──

const greedyColor = (
  nodeIds: string[],
  adjacency: Map<string, Set<string>>,
): Map<string, number> => {
  const colors = new Map<string, number>();
  for (const id of nodeIds) {
    const used = new Set<number>();
    const adj = adjacency.get(id);
    if (adj) {
      for (const nb of adj) {
        const c = colors.get(nb);
        if (c !== undefined) {
          used.add(c);
        }
      }
    }
    let c = 0;
    while (used.has(c)) {
      c++;
    }
    colors.set(id, c);
  }
  return colors;
};

// ── Smooth camera animation via spherical coordinates ──

type SphericalCoord = { radius: number; polar: number; azimuth: number };

const toSpherical = (
  pos: THREE.Vector3,
  target: THREE.Vector3,
): SphericalCoord => {
  const dx = pos.x - target.x,
    dy = pos.y - target.y,
    dz = pos.z - target.z;
  const radius = Math.sqrt(dx * dx + dy * dy + dz * dz);
  return {
    radius,
    polar: radius > 0 ? Math.acos(Math.min(1, Math.max(-1, dy / radius))) : 0,
    azimuth: Math.atan2(dx, dz),
  };
};

const fromSpherical = (
  s: SphericalCoord,
  target: THREE.Vector3,
): THREE.Vector3 =>
  new THREE.Vector3(
    target.x + s.radius * Math.sin(s.polar) * Math.sin(s.azimuth),
    target.y + s.radius * Math.cos(s.polar),
    target.z + s.radius * Math.sin(s.polar) * Math.cos(s.azimuth),
  );

const lerpAngle = (a: number, b: number, t: number): number => {
  let d = b - a;
  if (d > Math.PI) {
    d -= 2 * Math.PI;
  }
  if (d < -Math.PI) {
    d += 2 * Math.PI;
  }
  return a + d * t;
};

type CameraAnimation = {
  fromSph: SphericalCoord;
  toSph: SphericalCoord;
  fromTarget: THREE.Vector3;
  toTarget: THREE.Vector3;
  startTime: number;
  duration: number;
};

// Smooth ease-out for distance (no overshoot)
const easeOutCubic = (t: number): number => 1 - (1 - t) ** 3;

// Gentle elastic for angles: single subtle bounce then settle
const easeOutElasticGentle = (t: number): number => {
  if (t === 0 || t === 1) {
    return t;
  }
  return 2 ** (-12 * t) * Math.sin(((t - 0.075) * (2 * Math.PI)) / 0.6) + 1;
};

const applyCameraAnim = (
  anim: CameraAnimation,
  t: number,
  cam: { camera: THREE.PerspectiveCamera; controls: OrbitControls },
) => {
  const eAngle = easeOutElasticGentle(t);
  const eDist = easeOutCubic(t);
  const sph: SphericalCoord = {
    radius:
      anim.fromSph.radius + (anim.toSph.radius - anim.fromSph.radius) * eDist,
    polar:
      anim.fromSph.polar + (anim.toSph.polar - anim.fromSph.polar) * eAngle,
    azimuth: lerpAngle(anim.fromSph.azimuth, anim.toSph.azimuth, eAngle),
  };
  const target = new THREE.Vector3().lerpVectors(
    anim.fromTarget,
    anim.toTarget,
    eDist,
  );
  cam.controls.target.copy(target);
  cam.camera.position.copy(fromSpherical(sph, target));
};

export const buildScene = (opts: {
  container: HTMLDivElement;
  tree: GraphTree;
  onHover: (node: FolderNode | null) => void;
  onClick?: (node: FolderNode | null) => void;
}): (() => void) => {
  const { container, tree, onHover, onClick } = opts;
  const { nodes, edges, roots } = tree;
  const w0 = container.clientWidth,
    h0 = container.clientHeight;
  const boxes = computeLayout(nodes, roots);

  // Graph coloring
  const adjacency = new Map<string, Set<string>>();
  const ensureAdj = (id: string) => {
    if (!adjacency.has(id)) {
      adjacency.set(id, new Set());
    }
  };
  for (const [id, node] of nodes) {
    ensureAdj(id);
    for (const child of node.children) {
      ensureAdj(child);
      adjacency.get(id)!.add(child);
      adjacency.get(child)!.add(id);
    }
  }
  for (const edge of edges) {
    ensureAdj(edge.from);
    ensureAdj(edge.to);
    adjacency.get(edge.from)!.add(edge.to);
    adjacency.get(edge.to)!.add(edge.from);
  }
  const nodeColorMap = greedyColor([...nodes.keys()], adjacency);
  const getNodeColor = (id: string): number =>
    GRAPH_COLORS[(nodeColorMap.get(id) ?? 0) % GRAPH_COLORS.length];

  // Center offset
  const all = [...boxes.values()];
  const cx = all.reduce((s, b) => s + b.x + b.w / 2, 0) / all.length;
  const cz = all.reduce((s, b) => s + b.z + b.d / 2, 0) / all.length;

  // Scene setup
  const scene = new THREE.Scene();
  scene.background = new THREE.Color(0x0d1117);

  const maxSpan = Math.max(
    Math.max(...all.map((b) => b.x + b.w)) - Math.min(...all.map((b) => b.x)),
    Math.max(...all.map((b) => b.z + b.d)) - Math.min(...all.map((b) => b.z)),
  );
  const camera = new THREE.PerspectiveCamera(50, w0 / h0, 0.1, 2000);
  // Start from top-down bird's-eye view
  camera.position.set(0, maxSpan * INITIAL_HEIGHT_FACTOR, 0.01);
  const renderer = new THREE.WebGLRenderer({ antialias: true });
  renderer.setSize(w0, h0);
  renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
  container.appendChild(renderer.domElement);
  const controls = new OrbitControls(camera, renderer.domElement);
  controls.enableDamping = true;
  controls.dampingFactor = 0.08;
  controls.target.set(0, 0, 0);

  const defaultTarget = new THREE.Vector3(0, 0, 0);
  const defaultDist = maxSpan * DEFAULT_DISTANCE_FACTOR;

  // No intro animation — start with top-down view and let the user explore
  let cameraAnim: CameraAnimation | null = null;
  scene.add(new THREE.AmbientLight(0xffffff, 0.65));
  const dLight = new THREE.DirectionalLight(0xffffff, 0.55);
  dLight.position.set(20, 40, 30);
  scene.add(dLight);

  const cardMeshes: THREE.Mesh[] = [];
  const meshToNode = new Map<THREE.Mesh, FolderNode>();

  // Label texture helper
  const texCvs = document.createElement("canvas");
  texCvs.width = 512;
  texCvs.height = 64;
  const texCtx = texCvs.getContext("2d")!;

  const makeLabel = (node: FolderNode, color: number): THREE.CanvasTexture => {
    const r = (color >> 16) & 0xff,
      g = (color >> 8) & 0xff,
      b = color & 0xff;
    texCtx.clearRect(0, 0, 512, 64);
    texCtx.fillStyle = `rgba(${r},${g},${b},0.25)`;
    texCtx.roundRect(0, 0, 512, 64, 4);
    texCtx.fill();
    texCtx.fillStyle = "#e6edf3";
    texCtx.font =
      node.children.length > 0 ? "bold 18px monospace" : "14px monospace";
    texCtx.fillText(node.name, 10, 26);
    texCtx.fillStyle = "#6e7681";
    texCtx.font = "11px sans-serif";
    const info: string[] = [];
    if (node.fileCount > 0) {
      info.push(`${node.fileCount} files`);
    }
    if (node.functionCount > 0) {
      info.push(`${node.functionCount} fn`);
    }
    if (node.children.length > 0) {
      info.push(`${node.children.length} sub`);
    }
    texCtx.fillText(info.join("  "), 10, 46);
    const clone = document.createElement("canvas");
    clone.width = 512;
    clone.height = 64;
    clone.getContext("2d")!.drawImage(texCvs, 0, 0);
    const tex = new THREE.CanvasTexture(clone);
    tex.needsUpdate = true;
    return tex;
  };

  // ── Create nodes ──
  for (const [id, node] of nodes) {
    const box = boxes.get(id);
    if (!box) {
      continue;
    }
    const color = getNodeColor(id);
    const r = (color >> 16) & 0xff,
      g = (color >> 8) & 0xff,
      b = color & 0xff;
    const bx = box.x + box.w / 2 - cx;
    const bz = box.z + box.d / 2 - cz;

    if (node.children.length > 0) {
      // Container node
      const floorGeo = new THREE.BoxGeometry(box.w, FLOOR_H, box.d);
      const floorMat = new THREE.MeshStandardMaterial({
        color: new THREE.Color(
          `rgb(${Math.floor(r * 0.2)},${Math.floor(g * 0.2)},${Math.floor(b * 0.2)})`,
        ),
        transparent: true,
        opacity: 0.6,
        roughness: 0.9,
      });
      const floor = new THREE.Mesh(floorGeo, floorMat);
      floor.position.set(bx, box.y + FLOOR_H / 2, bz);
      floor.name = id;
      scene.add(floor);
      cardMeshes.push(floor);
      meshToNode.set(floor, node);
      const wallH = box.h;
      const wallMat = new THREE.MeshStandardMaterial({
        color: new THREE.Color(`rgb(${r},${g},${b})`),
        transparent: true,
        opacity: 0.08,
        roughness: 0.9,
        side: THREE.DoubleSide,
      });
      const lw = new THREE.Mesh(
        new THREE.BoxGeometry(WALL, wallH, box.d),
        wallMat,
      );
      lw.position.set(box.x - cx, box.y + wallH / 2, bz);
      scene.add(lw);
      const rw = new THREE.Mesh(
        new THREE.BoxGeometry(WALL, wallH, box.d),
        wallMat.clone(),
      );
      rw.position.set(box.x + box.w - cx, box.y + wallH / 2, bz);
      scene.add(rw);
      const fw = new THREE.Mesh(
        new THREE.BoxGeometry(box.w, wallH, WALL),
        wallMat.clone(),
      );
      fw.position.set(bx, box.y + wallH / 2, box.z - cz);
      scene.add(fw);
      const bw = new THREE.Mesh(
        new THREE.BoxGeometry(box.w, wallH, WALL),
        wallMat.clone(),
      );
      bw.position.set(bx, box.y + wallH / 2, box.z + box.d - cz);
      scene.add(bw);
      const wireGeo = new THREE.BoxGeometry(box.w, wallH, box.d);
      const wireEdges = new THREE.EdgesGeometry(wireGeo);
      const wireMat = new THREE.LineBasicMaterial({
        color: new THREE.Color(`rgb(${r},${g},${b})`),
        transparent: true,
        opacity: 0.15,
      });
      const wire = new THREE.LineSegments(wireEdges, wireMat);
      wire.position.set(bx, box.y + wallH / 2, bz);
      scene.add(wire);
      const labelTex = makeLabel(node, color);
      const labelW = Math.min(box.w * 0.9, 5);
      const labelGeo = new THREE.PlaneGeometry(labelW, LABEL_ZONE * 0.7);
      const labelMat = new THREE.MeshBasicMaterial({
        map: labelTex,
        transparent: true,
        opacity: 0.9,
        side: THREE.DoubleSide,
      });
      const label = new THREE.Mesh(labelGeo, labelMat);
      label.position.set(
        box.x + labelW / 2 + PAD - cx,
        box.y + wallH - 0.1,
        box.z + LABEL_ZONE * 0.4 - cz,
      );
      label.rotation.x = -Math.PI / 4;
      scene.add(label);
    } else {
      // Leaf node with LOD
      const farLeaf = new THREE.Group();
      const farGeo = new THREE.BoxGeometry(box.w, box.h, box.d);
      const farTex = makeLabel(node, color);
      const farMat = new THREE.MeshStandardMaterial({
        map: farTex,
        transparent: true,
        opacity: 0.95,
        roughness: 0.7,
        metalness: 0.1,
      });
      const farMesh = new THREE.Mesh(farGeo, farMat);
      farMesh.name = id;
      farMesh.position.set(0, box.h / 2, 0);
      farLeaf.add(farMesh);
      cardMeshes.push(farMesh);
      meshToNode.set(farMesh, node);

      const nearLeaf = new THREE.Group();
      const floorGeo = new THREE.BoxGeometry(box.w, FLOOR_H, box.d);
      const floorMat = new THREE.MeshStandardMaterial({
        color: new THREE.Color(
          `rgb(${Math.floor(r * 0.15)},${Math.floor(g * 0.15)},${Math.floor(b * 0.15)})`,
        ),
        transparent: true,
        opacity: 0.4,
        roughness: 0.9,
      });
      const floor = new THREE.Mesh(floorGeo, floorMat);
      floor.name = id;
      nearLeaf.add(floor);
      cardMeshes.push(floor);
      meshToNode.set(floor, node);

      // File pages
      const PAGE_W = 1.6;
      const PAGE_H = 2.0;
      const PAGE_THICK = 0.02;
      const PAGE_MARGIN = 0.2;
      const files = node.files;
      const pageCols = Math.max(1, Math.ceil(Math.sqrt(files.length)));
      const pageStepX = PAGE_W + PAGE_MARGIN;
      const pageStepZ = PAGE_H * 0.6 + PAGE_MARGIN;
      const pageCvs = document.createElement("canvas");
      pageCvs.width = 256;
      pageCvs.height = 320;
      const pageCtx = pageCvs.getContext("2d")!;

      for (let fi = 0; fi < files.length; fi++) {
        const file = files[fi];
        pageCtx.clearRect(0, 0, 256, 320);
        pageCtx.fillStyle = "#161b22";
        pageCtx.fillRect(0, 0, 256, 320);
        pageCtx.strokeStyle = "#30363d";
        pageCtx.lineWidth = 1;
        pageCtx.beginPath();
        pageCtx.moveTo(28, 0);
        pageCtx.lineTo(28, 320);
        pageCtx.stroke();

        pageCtx.fillStyle = `rgba(${r},${g},${b},0.15)`;
        pageCtx.fillRect(0, 0, 256, 24);
        pageCtx.fillStyle = "#e6edf3";
        pageCtx.font = "bold 11px monospace";
        pageCtx.fillText(file.name, 4, 16);

        let lineY = 36;
        const lineH = 13;
        for (let si = 0; si < file.symbols.length && lineY < 310; si++) {
          const sym = file.symbols[si];
          pageCtx.fillStyle = "#30363d";
          pageCtx.font = "9px monospace";
          pageCtx.fillText(String(si + 1).padStart(3), 4, lineY);
          pageCtx.fillStyle = kindHex(sym.kind);
          pageCtx.font = "10px monospace";
          const kw = sym.kind.toLowerCase().slice(0, 3);
          pageCtx.fillText(kw, 32, lineY);
          pageCtx.fillStyle = "#e6edf3";
          pageCtx.fillText(sym.name, 56, lineY);
          lineY += lineH;
        }
        if (file.symbols.length === 0) {
          pageCtx.fillStyle = "#30363d";
          pageCtx.font = "10px monospace";
          pageCtx.fillText("(no symbols)", 32, lineY);
        }

        const pageClone = document.createElement("canvas");
        pageClone.width = 256;
        pageClone.height = 320;
        pageClone.getContext("2d")!.drawImage(pageCvs, 0, 0);
        const pageTex = new THREE.CanvasTexture(pageClone);
        pageTex.needsUpdate = true;

        const col = fi % pageCols;
        const row = Math.floor(fi / pageCols);
        const totalCols = Math.min(files.length, pageCols);
        const totalRows = Math.ceil(files.length / pageCols);
        const px = (col - (totalCols - 1) / 2) * pageStepX;
        const pz = (row - (totalRows - 1) / 2) * pageStepZ;
        const py = FLOOR_H + PAGE_THICK / 2 + 0.01;

        const pageGroup = new THREE.Group();
        pageGroup.position.set(px, py, pz);
        pageGroup.rotation.x = -Math.PI * 0.35;

        const pageFront = new THREE.Mesh(
          new THREE.PlaneGeometry(PAGE_W, PAGE_H),
          new THREE.MeshBasicMaterial({
            map: pageTex,
            transparent: true,
            opacity: 0.95,
            side: THREE.DoubleSide,
          }),
        );
        pageGroup.add(pageFront);

        const pageEdge = new THREE.Mesh(
          new THREE.BoxGeometry(PAGE_W, PAGE_H, PAGE_THICK),
          new THREE.MeshStandardMaterial({
            color: 0x21262d,
            transparent: true,
            opacity: 0.5,
            roughness: 0.9,
          }),
        );
        pageGroup.add(pageEdge);

        nearLeaf.add(pageGroup);
      }

      const leafLod = new THREE.LOD();
      leafLod.addLevel(nearLeaf, 0);
      leafLod.addLevel(farLeaf, maxSpan * 0.35);
      leafLod.position.set(bx, box.y, bz);
      scene.add(leafLod);
    }
  }

  // ── Dependency wiring ──
  const edgesBySource = new Map<string, string[]>();
  for (const edge of edges) {
    if (!boxes.has(edge.from) || !boxes.has(edge.to)) {
      continue;
    }
    const arr = edgesBySource.get(edge.from) ?? [];
    arr.push(edge.to);
    edgesBySource.set(edge.from, arr);
  }

  const addWire = (
    group: THREE.Group,
    path: THREE.Curve<THREE.Vector3>,
    style: { radius: number; color: number; opacity: number },
  ) => {
    const geo = new THREE.TubeGeometry(path, 20, style.radius, 8, false);
    group.add(
      new THREE.Mesh(
        geo,
        new THREE.MeshStandardMaterial({
          color: style.color,
          transparent: true,
          opacity: style.opacity,
          roughness: 0.35,
          metalness: 0.5,
          emissive: style.color,
          emissiveIntensity: 0.2,
        }),
      ),
    );
  };

  const addArrow = (
    group: THREE.Group,
    target: THREE.Vector3,
    opts: { curve: THREE.Curve<THREE.Vector3>; color: number },
  ) => {
    const { curve, color } = opts;
    const tangent = curve.getTangentAt(1.0).normalize();
    const cone = new THREE.Mesh(
      new THREE.ConeGeometry(0.2, 0.55, 8),
      new THREE.MeshStandardMaterial({
        color,
        transparent: true,
        opacity: 0.9,
        roughness: 0.3,
        metalness: 0.4,
        emissive: color,
        emissiveIntensity: 0.25,
      }),
    );
    cone.position.copy(target);
    cone.quaternion.setFromUnitVectors(new THREE.Vector3(0, 1, 0), tangent);
    group.add(cone);
  };

  const makeArc = (
    from: THREE.Vector3,
    to: THREE.Vector3,
    heightFactor: number,
  ): THREE.QuadraticBezierCurve3 => {
    const dist = from.distanceTo(to);
    const h = Math.min(dist * heightFactor, 6) + 0.8;
    const mid = new THREE.Vector3(
      (from.x + to.x) / 2,
      Math.max(from.y, to.y) + h,
      (from.z + to.z) / 2,
    );
    return new THREE.QuadraticBezierCurve3(from.clone(), mid, to.clone());
  };

  const LOD_NEAR = maxSpan * 0.15;
  const LOD_MID = maxSpan * 0.4;

  for (const [fromId, targets] of edgesBySource) {
    const fb = boxes.get(fromId)!;
    const fromColor = getNodeColor(fromId);
    const anchorY = (b: Box3D, id: string): number => {
      const n = nodes.get(id);
      return n && n.children.length > 0 ? b.y + FLOOR_H : b.y + b.h;
    };
    const origin = new THREE.Vector3(
      fb.x + fb.w / 2 - cx,
      anchorY(fb, fromId),
      fb.z + fb.d / 2 - cz,
    );
    const rel = (world: THREE.Vector3) => world.clone().sub(origin);
    const srcLocal = new THREE.Vector3(0, 0, 0);

    const targetLocals: { toId: string; pt: THREE.Vector3 }[] = [];
    let centX = 0,
      centY = 0,
      centZ = 0;
    for (const toId of targets) {
      const tb = boxes.get(toId)!;
      const local = rel(
        new THREE.Vector3(
          tb.x + tb.w / 2 - cx,
          anchorY(tb, toId),
          tb.z + tb.d / 2 - cz,
        ),
      );
      targetLocals.push({ toId, pt: local });
      centX += local.x;
      centY += local.y;
      centZ += local.z;
    }
    centX /= targets.length;
    centY /= targets.length;
    centZ /= targets.length;
    const centroidLocal = new THREE.Vector3(centX, centY, centZ);

    const nearGroup = new THREE.Group();
    for (const { toId, pt } of targetLocals) {
      const toColor = getNodeColor(toId);
      const curve = makeArc(srcLocal, pt, 0.3);
      addWire(nearGroup, curve, {
        radius: 0.025,
        color: fromColor,
        opacity: 0.7,
      });
      addArrow(nearGroup, pt, { curve, color: toColor });
    }

    const midGroup = new THREE.Group();
    for (const { pt } of targetLocals) {
      const curve = makeArc(srcLocal, pt, 0.3);
      addWire(midGroup, curve, {
        radius: 0.015,
        color: fromColor,
        opacity: 0.45,
      });
    }

    const farGroup = new THREE.Group();
    const farCurve = makeArc(srcLocal, centroidLocal, 0.25);
    addWire(farGroup, farCurve, {
      radius: 0.04,
      color: fromColor,
      opacity: 0.55,
    });

    const lod = new THREE.LOD();
    lod.addLevel(nearGroup, 0);
    lod.addLevel(midGroup, LOD_NEAR);
    lod.addLevel(farGroup, LOD_MID);
    lod.position.copy(origin);
    scene.add(lod);
  }

  // ── Grid ──
  const gridSize = Math.max(maxSpan, 20) * 1.5;
  const grid = new THREE.GridHelper(
    gridSize,
    Math.floor(gridSize / 4),
    0x1a1f26,
    0x13171e,
  );
  grid.position.y = -0.1;
  scene.add(grid);

  // ── Raycaster + pointer interaction (PointerEvent for touch + mouse) ──
  const ac = new AbortController();
  const { signal } = ac;
  const raycaster = new THREE.Raycaster();
  const pointer = new THREE.Vector2(9999, 9999);
  let hoverMesh: THREE.Mesh | null = null;
  let pointerDownPos = { x: 0, y: 0 };

  const updatePointer = (ev: PointerEvent) => {
    const rect = renderer.domElement.getBoundingClientRect();
    pointer.x = ((ev.clientX - rect.left) / rect.width) * 2 - 1;
    pointer.y = -((ev.clientY - rect.top) / rect.height) * 2 + 1;
  };

  const flyTo = (toSph: SphericalCoord, toTarget: THREE.Vector3) => {
    cameraAnim = {
      fromSph: toSpherical(camera.position, controls.target),
      toSph,
      fromTarget: controls.target.clone(),
      toTarget,
      startTime: performance.now(),
      duration: FLY_DURATION_MS,
    };
  };

  const el = renderer.domElement;
  el.style.touchAction = "none";

  el.addEventListener(
    "pointermove",
    (ev) => {
      updatePointer(ev);
      const dx = ev.clientX - pointerDownPos.x,
        dy = ev.clientY - pointerDownPos.y;
      if (ev.buttons > 0 && dx * dx + dy * dy > DRAG_CANCEL_THRESHOLD_SQ) {
        cameraAnim = null;
      }
    },
    { signal },
  );

  el.addEventListener(
    "pointerdown",
    (ev) => {
      pointerDownPos = { x: ev.clientX, y: ev.clientY };
      updatePointer(ev);
    },
    { signal },
  );

  el.addEventListener(
    "pointerup",
    (ev) => {
      const dx = ev.clientX - pointerDownPos.x,
        dy = ev.clientY - pointerDownPos.y;
      if (dx * dx + dy * dy > CLICK_DRAG_THRESHOLD_SQ) {
        return;
      }
      updatePointer(ev);
      raycaster.setFromCamera(pointer, camera);
      const hits = raycaster.intersectObjects(cardMeshes);
      const hit =
        hits.length > 0
          ? (meshToNode.get(hits[0].object as THREE.Mesh) ?? null)
          : null;
      if (hit) {
        const hitObj = hits[0].object as THREE.Mesh;
        const worldPos = new THREE.Vector3();
        hitObj.getWorldPosition(worldPos);
        const nodeBox = boxes.get(hitObj.name);
        const span = nodeBox ? Math.max(nodeBox.w, nodeBox.d) : 3;
        const viewDist = Math.max(span * FOCUS_SPAN_FACTOR, FOCUS_MIN_DIST);
        const currentSph = toSpherical(camera.position, controls.target);
        flyTo(
          {
            radius: viewDist,
            polar: currentSph.polar,
            azimuth: currentSph.azimuth,
          },
          worldPos,
        );
        onClick?.(hit);
      } else {
        const currentSph = toSpherical(camera.position, controls.target);
        flyTo(
          {
            radius: defaultDist,
            polar: currentSph.polar,
            azimuth: currentSph.azimuth,
          },
          defaultTarget.clone(),
        );
        onClick?.(null);
      }
    },
    { signal },
  );

  el.addEventListener(
    "wheel",
    () => {
      cameraAnim = null;
    },
    { signal, passive: true },
  );

  let animId = 0;
  const animate = () => {
    animId = requestAnimationFrame(animate);

    if (cameraAnim) {
      const elapsed = performance.now() - cameraAnim.startTime;
      if (elapsed >= 0) {
        const done = elapsed >= cameraAnim.duration;
        const t = done ? 1 : elapsed / cameraAnim.duration;
        applyCameraAnim(cameraAnim, t, { camera, controls });
        if (done) {
          cameraAnim = null;
        }
      }
    }

    controls.update();

    raycaster.setFromCamera(pointer, camera);
    const hits = raycaster.intersectObjects(cardMeshes);
    const hit = hits.length > 0 ? (hits[0].object as THREE.Mesh) : null;
    el.style.cursor = hit ? "pointer" : "grab";
    if (hit !== hoverMesh) {
      if (hoverMesh) {
        const mat = hoverMesh.material as THREE.MeshStandardMaterial;
        if (mat.emissive) {
          mat.emissive.setHex(0);
        }
      }
      hoverMesh = hit;
      if (hoverMesh) {
        const mat = hoverMesh.material as THREE.MeshStandardMaterial;
        if (mat.emissive) {
          mat.emissive.setHex(HOVER_EMISSIVE);
        }
        onHover(meshToNode.get(hoverMesh) ?? null);
      } else {
        onHover(null);
      }
    }
    renderer.render(scene, camera);
  };
  animate();

  const obs = new ResizeObserver(() => {
    const w = container.clientWidth,
      h = container.clientHeight;
    camera.aspect = w / h;
    camera.updateProjectionMatrix();
    renderer.setSize(w, h);
  });
  obs.observe(container);

  return () => {
    cancelAnimationFrame(animId);
    obs.disconnect();
    ac.abort();
    renderer.dispose();
    if (el.parentNode) {
      container.removeChild(el);
    }
  };
};
