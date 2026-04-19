/**
 * @file three.js scene bootstrap shared by every layer.
 *
 * Owns the WebGLRenderer, Scene, PerspectiveCamera, OrbitControls, and
 * the cursor-anchored zoom handler. Layers consume this context but
 * do not construct it; the renderer composes one and hands it down.
 *
 * Also owns theme colours so every layer reads the current foreground/
 * background through the same accessor instead of caching their own
 * copies (which historically drifted on theme toggle).
 */

import {
  Color,
  MOUSE,
  PerspectiveCamera,
  Plane,
  Raycaster,
  Scene,
  Vector2,
  Vector3,
  WebGLRenderer,
} from "three";
import { OrbitControls } from "three/examples/jsm/controls/OrbitControls.js";
import type { CameraSettings, ThemeColors } from "../../types.ts";
import { clamp } from "./projection.ts";

/** Camera operation mode.
 *  - "2d": layout is coplanar (z = 0). Left-drag pans along the
 *    screen, wheel zooms; rotation is disabled because tilting a
 *    flat plane produces a confusing skewed view.
 *  - "3d": layout occupies a real 3D volume. Left-drag orbits,
 *    right-drag pans, wheel zooms — the standard CAD-style
 *    convention. */
export type CameraMode = "2d" | "3d";

export type SceneContextInit = {
  readonly canvas: HTMLCanvasElement;
  readonly width: number;
  readonly height: number;
  readonly dpr: number;
  readonly theme: ThemeColors;
  readonly cameraSettings: CameraSettings;
};

export type ResizeArgs = {
  readonly width: number;
  readonly height: number;
  readonly dpr: number;
};

export class SceneContext {
  readonly renderer: WebGLRenderer;
  readonly scene: Scene;
  readonly camera: PerspectiveCamera;
  readonly controls: OrbitControls;
  readonly raycaster: Raycaster;
  readonly fgColor = new Color();
  readonly bgColor = new Color();
  readonly selectionColor = new Color();
  readonly highlightColor = new Color();
  width: number;
  height: number;
  private readonly cameraSettings: CameraSettings;
  private readonly ndc = new Vector2();

  constructor(init: SceneContextInit) {
    this.width = init.width;
    this.height = init.height;
    this.cameraSettings = init.cameraSettings;

    this.renderer = new WebGLRenderer({
      canvas: init.canvas,
      antialias: true,
      alpha: true,
      powerPreference: "high-performance",
    });
    this.renderer.setPixelRatio(init.dpr);
    this.renderer.setSize(init.width, init.height, false);
    this.renderer.setClearColor(new Color(init.theme.background), 1);

    this.scene = new Scene();
    this.camera = new PerspectiveCamera(
      init.cameraSettings.fov,
      init.width / init.height,
      init.cameraSettings.near,
      init.cameraSettings.far,
    );
    this.camera.position.set(0, 0, 1200);
    this.camera.lookAt(0, 0, 0);

    this.controls = new OrbitControls(this.camera, init.canvas);
    this.controls.enableDamping = true;
    this.controls.dampingFactor = 0.12;
    this.controls.rotateSpeed = 0.8;
    this.controls.panSpeed = 1;
    this.controls.zoomSpeed = 1;
    // screenSpacePanning = true: pan moves the target along the
    // camera's right/up axes regardless of viewing angle. The
    // alternative (false) pans along the world XZ plane, which
    // produces "the scene slides into the floor" when the camera is
    // looking down — confusing for a graph viewer where the
    // "ground" has no semantic meaning.
    this.controls.screenSpacePanning = true;
    this.controls.zoomToCursor = false;
    this.controls.enableZoom = false;
    this.controls.minDistance = init.cameraSettings.minDistance;
    this.controls.maxDistance = init.cameraSettings.maxDistance;

    this.raycaster = new Raycaster();
    this.installCursorZoom(init.canvas);
    this.applyTheme(init.theme);
    // Default to 3D — strategies switch this on apply.
    this.setCameraMode("3d");
  }

  /** Switch the pointer-bind for camera operations to match the
   *  layout's dimensionality. Coplanar layouts (Hierarchy treemap)
   *  get pan-by-default; volumetric layouts (Volume / K-means)
   *  keep the orbit-by-default convention. The same rebind also
   *  resets the camera tilt so a 2D layout reads as flat. */
  setCameraMode(mode: CameraMode): void {
    if (mode === "2d") {
      // Left-drag pans along the screen; rotation is off so the
      // user can't accidentally tilt a flat plane into a skewed
      // perspective view. Right-drag also pans (no other useful
      // operation in 2D), so a misclick on either button still
      // does something predictable.
      this.controls.enableRotate = false;
      this.controls.enablePan = true;
      this.controls.mouseButtons = {
        LEFT: MOUSE.PAN,
        MIDDLE: MOUSE.PAN,
        RIGHT: MOUSE.PAN,
      };
      // Snap the camera straight down the +Z axis through whatever
      // the current orbit target is. This guarantees the 2D layout
      // shows as a top-down view; without it, switching from a
      // tilted 3D layout would leave a 2D layout rendered at an
      // angle — visually wrong for a coplanar diagram.
      const target = this.controls.target;
      const dist = this.camera.position.distanceTo(target);
      this.camera.position.set(target.x, target.y, target.z + dist);
      this.camera.up.set(0, 1, 0);
      this.camera.lookAt(target);
      this.camera.updateProjectionMatrix();
      this.controls.update();
    } else {
      // Standard CAD-style binding: left=orbit, right=pan, middle
      // also pans (matches Figma / Blender muscle memory better
      // than middle=dolly when wheel already handles zoom).
      this.controls.enableRotate = true;
      this.controls.enablePan = true;
      this.controls.mouseButtons = {
        LEFT: MOUSE.ROTATE,
        MIDDLE: MOUSE.PAN,
        RIGHT: MOUSE.PAN,
      };
    }
    // Wake any RAF loop so the rebind is reflected immediately.
    this.controls.dispatchEvent({ type: "change" });
  }

  resize(args: ResizeArgs): void {
    this.width = args.width;
    this.height = args.height;
    this.renderer.setPixelRatio(args.dpr);
    this.renderer.setSize(args.width, args.height, false);
    this.camera.aspect = args.width / args.height;
    this.camera.updateProjectionMatrix();
  }

  applyTheme(theme: ThemeColors): void {
    this.fgColor.set(theme.labelColor);
    this.bgColor.set(theme.background);
    this.selectionColor.set(theme.selectionColor);
    this.highlightColor.set(theme.highlightColor);
    this.renderer.setClearColor(this.bgColor, 1);
  }

  /** Set NDC-space coordinates from CSS pixel coordinates relative to
   *  the canvas's top-left. Reuses the internal Vector2 so callers
   *  don't allocate per pick. */
  setNdc(screenX: number, screenY: number): Vector2 {
    this.ndc.set(
      (screenX / this.width) * 2 - 1,
      -((screenY / this.height) * 2 - 1),
    );
    return this.ndc;
  }

  dispose(): void {
    this.controls.dispose();
    this.renderer.dispose();
  }

  /** Cursor-origin zoom handler. Substitutes OrbitControls' built-in
   *  wheel zoom because that implementation clamps distance in a way
   *  that conflicts with screenSpacePanning and fails to reach the
   *  minimum distance even after many wheel ticks.
   *
   *  Each wheel tick multiplies the camera-to-target distance by a
   *  geometric factor. Zooming *in* also pulls both the camera and
   *  the target toward the point the cursor is currently hovering. */
  private installCursorZoom(canvas: HTMLCanvasElement): void {
    const pointerWorld = new Vector3();
    const plane = new Plane();
    const viewDir = new Vector3();
    const toCursor = new Vector3();
    const camToTarget = new Vector3();
    const { zoomPerTick, targetFollow } = this.cameraSettings;

    canvas.addEventListener(
      "wheel",
      (event: WheelEvent) => {
        event.preventDefault();
        const rect = canvas.getBoundingClientRect();
        const x = event.clientX - rect.left;
        const y = event.clientY - rect.top;
        this.setNdc(x, y);
        this.raycaster.setFromCamera(this.ndc, this.camera);

        this.camera.getWorldDirection(viewDir);
        plane.setFromNormalAndCoplanarPoint(viewDir, this.controls.target);
        const hit = this.raycaster.ray.intersectPlane(plane, pointerWorld);
        const anchor = hit ? pointerWorld : this.controls.target;

        const scale = Math.exp(event.deltaY * 0.01 * zoomPerTick);
        camToTarget.subVectors(this.camera.position, this.controls.target);
        const prevRadius = camToTarget.length();
        const nextRadius = clamp(
          prevRadius * scale,
          this.controls.minDistance,
          this.controls.maxDistance,
        );
        const actualScale = prevRadius > 0 ? nextRadius / prevRadius : 1;

        toCursor.subVectors(anchor, this.camera.position);
        this.camera.position.addScaledVector(toCursor, 1 - actualScale);
        toCursor.subVectors(anchor, this.controls.target);
        this.controls.target.addScaledVector(
          toCursor,
          (1 - actualScale) * targetFollow,
        );
        this.camera.updateMatrixWorld();
        this.controls.dispatchEvent({ type: "change" });
      },
      { passive: false },
    );
  }
}
