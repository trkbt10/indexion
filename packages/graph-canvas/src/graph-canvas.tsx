/**
 * @file React wrapper around the graph viewer.
 *
 * The layout pipeline is one-shot and deterministic:
 *
 *   graph → (optional) clustering → HDE strategy → positions
 *
 * There is no per-frame simulation loop. Redraws are scheduled only
 * when something changes (graph, filter, theme, selection, hover,
 * drag). Dragging triggers a tiny local neighbour relaxation, never a
 * global re-solve.
 *
 * Rendering uses WebGL via three.js (InstancedMesh for nodes & edges,
 * DOM overlay for labels, Raycaster hit-testing, perspective camera,
 * OrbitControls for rotate / pan / zoom).
 *
 * Environment signals (container size, dpr, system colour scheme) use
 * useSyncExternalStore so they stay in sync without setState-in-effect.
 */

import {
  forwardRef,
  useCallback,
  useEffect,
  useImperativeHandle,
  useMemo,
  useRef,
  useSyncExternalStore,
  type CSSProperties,
} from "react";
import type {
  FilterResult,
  GraphCanvasHandle,
  GraphCanvasProps,
  SelectionState,
  ThemeColors,
  ViewGraph,
  ViewNode,
} from "./types.ts";
import { computeFilter } from "./filter.ts";
import {
  applySelectionIntent,
  createSelectionState,
} from "./interaction/selection.ts";
import { installPointerHandlers } from "./interaction/pointer.ts";
import { startRafLoop } from "./interaction/raf-loop.ts";
import type { SelectionEffect, SelectionIntent } from "./types.ts";
import { resolveRenderSettings } from "./renderer/settings.ts";
import { diffGraph, normalizeGraph } from "./normalize.ts";
import { DARK_THEME, LIGHT_THEME } from "./renderer/styles.ts";
import { WebGlRenderer } from "./renderer/webgl/webgl-renderer.ts";
import { layoutGraph, type StrategyResult } from "./layout/index.ts";
import { computeClustering } from "./clustering/index.ts";

type CanvasSize = { readonly width: number; readonly height: number };
const DEFAULT_SIZE: CanvasSize = { width: 640, height: 420 };

export const GraphCanvas = forwardRef<GraphCanvasHandle, GraphCanvasProps>(
  function GraphCanvas(props, ref) {
    const containerRef = useRef<HTMLDivElement>(null);
    const canvasRef = useRef<HTMLCanvasElement>(null);

    const graphRef = useRef<ViewGraph | null>(null);
    const filterRef = useRef<FilterResult | null>(null);
    const selectionRef = useRef<SelectionState>(createSelectionState());
    const hoverNodeRef = useRef<ViewNode | null>(null);
    const sizeRef = useRef<CanvasSize>(DEFAULT_SIZE);
    const frameRef = useRef<number | null>(null);
    const rendererRef = useRef<WebGlRenderer | null>(null);
    /** The first fit after a renderer is created snaps instantly;
     *  later ones ease. Reset when the renderer is disposed. */
    const hasFittedRef = useRef(false);
    /** Extra metadata from the last layout pass (node depths, cluster
     *  shells). Consumed by the renderer for LOD and outlines. */
    const layoutResultRef = useRef<StrategyResult>({});

    const containerSize = useContainerSize(containerRef);
    const dpr = useDevicePixelRatio();
    const theme = useResolvedTheme(props.theme ?? "auto");

    const size = useMemo<CanvasSize>(
      () => ({
        width: props.width ?? containerSize.width,
        height: props.height ?? containerSize.height,
      }),
      [props.width, props.height, containerSize],
    );
    sizeRef.current = size;

    const renderCurrentFrame = useCallback(() => {
      const renderer = rendererRef.current;
      const graph = graphRef.current;
      const filter = filterRef.current;
      if (!renderer || !graph || !filter) {
        return;
      }
      const layoutResult = layoutResultRef.current;
      renderer.update({
        graph,
        filter,
        selection: selectionRef.current,
        hoverNode: hoverNodeRef.current,
        theme,
        nodeDepth: layoutResult.nodeDepth,
        clusterShells: layoutResult.clusterShells,
        nodeCluster: layoutResult.nodeCluster,
      });
      renderer.render();
    }, [theme]);

    const requestRedraw = useCallback(() => {
      if (frameRef.current !== null) {
        return;
      }
      frameRef.current = requestAnimationFrame(() => {
        frameRef.current = null;
        renderCurrentFrame();
      });
    }, [renderCurrentFrame]);

    const {
      enabledNodeKinds,
      enabledEdgeKinds,
      hideDisconnected,
      searchQuery,
    } = props;
    const recomputeFilter = useCallback(
      (graph: ViewGraph): FilterResult => {
        const next = computeFilter({
          graph,
          enabledNodeKinds,
          enabledEdgeKinds,
          hideDisconnected,
          searchQuery,
        });
        filterRef.current = next;
        return next;
      },
      [enabledNodeKinds, enabledEdgeKinds, hideDisconnected, searchQuery],
    );

    const { onSelectionChange } = props;
    const updateSelection = useCallback(
      (next: SelectionState) => {
        selectionRef.current = next;
        onSelectionChange?.(next.selected);
        requestRedraw();
      },
      [onSelectionChange, requestRedraw],
    );

    const clustering = props.clustering ?? "none";
    const layoutStrategy = props.layoutStrategy ?? "hierarchy";
    const renderSettings = useMemo(
      () => resolveRenderSettings(props.renderSettings),
      [props.renderSettings],
    );

    /** Recompute clustering + layout + filter from scratch. */
    const rebuild = useCallback(
      (graph: ViewGraph) => {
        const assignment = computeClustering(graph, clustering);
        const clusterOf = clustering === "none" ? null : assignment.clusterOf;
        const result = layoutGraph({
          graph,
          clusterOf,
          strategy: layoutStrategy,
          settings: renderSettings.layout,
        });
        layoutResultRef.current = result;
        const filter = recomputeFilter(graph);
        const visibleNodes = graph.nodes.filter((n) =>
          filter.visibleNodes.has(n.id),
        );
        const renderer = rendererRef.current;
        if (renderer) {
          // Switch the pointer-bind for the camera to match the
          // layout's dimensionality. This must happen before
          // fitToView so the (potentially-snapped-to-top-down) view
          // is what gets fit, not the previous tilted angle.
          renderer.setCameraMode(result.dimensionality ?? "3d");
          if (hasFittedRef.current) {
            renderer.fitToView(visibleNodes, 48);
          } else {
            renderer.fitToViewInstant(visibleNodes, 48);
            hasFittedRef.current = true;
          }
        }
      },
      [clustering, layoutStrategy, recomputeFilter, renderSettings.layout],
    );

    // --- Graph input → ViewGraph (+ layout, filter, fit) ---
    useEffect(() => {
      const incoming = normalizeGraph(props.graph);
      const previous = graphRef.current;
      const nextGraph = previous ? diffGraph(previous, incoming) : incoming;
      graphRef.current = nextGraph;
      rebuild(nextGraph);
      requestRedraw();
    }, [props.graph, rebuild, requestRedraw]);

    // --- Filter inputs change → recompute + redraw ---
    useEffect(() => {
      const graph = graphRef.current;
      if (!graph) {
        return;
      }
      recomputeFilter(graph);
      requestRedraw();
    }, [recomputeFilter, requestRedraw]);

    // --- Size / dpr / theme change → redraw ---
    useEffect(() => {
      requestRedraw();
    }, [size, theme, dpr, requestRedraw]);

    // --- Renderer lifecycle ---
    useEffect(() => {
      const canvas = canvasRef.current;
      const container = containerRef.current;
      if (!canvas || !container) {
        return;
      }
      const renderer = new WebGlRenderer({
        canvas,
        container,
        dpr,
        width: sizeRef.current.width,
        height: sizeRef.current.height,
        theme,
        settings: renderSettings,
      });
      rendererRef.current = renderer;
      hasFittedRef.current = false;
      // Camera mode must reflect whatever layout already produced
      // positions before this renderer was mounted. Without this,
      // a remount (theme toggle, dpr change, etc.) would reset
      // controls to the default 3D orbit even on a 2D layout —
      // exactly the symptom that made Hierarchy left-drag tilt the
      // treemap into a skewed perspective.
      const layoutResult = layoutResultRef.current;
      renderer.setCameraMode(layoutResult.dimensionality ?? "3d");
      // If the graph was laid out before the renderer existed, fit
      // it now — otherwise the camera stays at the default spawn
      // position (z=1200, looking at origin) while the scene is
      // elsewhere, and the canvas shows a black void.
      const graph = graphRef.current;
      const filter = filterRef.current;
      if (graph && filter) {
        const visible = graph.nodes.filter((n) =>
          filter.visibleNodes.has(n.id),
        );
        if (visible.length > 0) {
          renderer.fitToViewInstant(visible, 48);
          hasFittedRef.current = true;
        }
      }
      requestRedraw();
      return () => {
        rendererRef.current = null;
        hasFittedRef.current = false;
        renderer.dispose();
      };
    }, [dpr, theme, renderSettings, requestRedraw]);

    // --- Resize ---
    useEffect(() => {
      const renderer = rendererRef.current;
      if (!renderer) {
        return;
      }
      renderer.resize({ width: size.width, height: size.height, dpr });
      requestRedraw();
    }, [size, dpr, requestRedraw]);

    // --- Pointer interaction + camera damping tick loop ---
    const { onNodeClick, onNodeDoubleClick } = props;
    useEffect(() => {
      const canvas = canvasRef.current;
      if (!canvas) {
        return;
      }

      // ── RAF loop ─────────────────────────────────────────────
      // Runs only while there's actual motion to draw. Triggered
      // by pointer / wheel / OrbitControls change events; as soon
      // as the camera is stationary we stop requesting frames.
      // Idle CPU/GPU usage stays at zero.
      const raf = startRafLoop(rendererRef);

      // Wake the RAF loop whenever OrbitControls reports a user
      // action (drag-orbit, wheel-zoom, pinch, etc) so the camera
      // damping plays out visibly.
      const unsubCameraChange =
        rendererRef.current?.onCameraChange(() => raf.kick()) ?? (() => {});

      const runSelectionEffect = (effect: SelectionEffect) => {
        if (effect.type === "none") {
          return;
        }
        const renderer = rendererRef.current;
        const graph = graphRef.current;
        const filter = filterRef.current;
        if (!renderer || !graph || !filter) {
          return;
        }
        if (effect.type === "fit-to-view") {
          renderer.fitToView(
            graph.nodes.filter((n) => filter.visibleNodes.has(n.id)),
            48,
          );
          return;
        }
        const node = graph.nodeIndex.get(effect.nodeId);
        if (node) {
          renderer.focusOn(node);
        }
      };

      const applyIntent = (intent: SelectionIntent) => {
        const graph = graphRef.current;
        if (!graph) {
          return;
        }
        const transition = applySelectionIntent({
          state: selectionRef.current,
          intent,
          edges: graph.edges,
        });
        if (transition.state !== selectionRef.current) {
          updateSelection(transition.state);
        }
        runSelectionEffect(transition.effect);
      };

      // ── Pointer state machine ────────────────────────────────
      const pointer = installPointerHandlers({
        canvas,
        rendererRef,
        graphRef,
        hoverNodeRef,
        onHoverChange: () => requestRedraw(),
        onDragMove: () => {
          requestRedraw();
          raf.kick();
        },
        onClick: (node, shift) => {
          if (node) {
            onNodeClick?.(node);
          }
          applyIntent({ type: "click", node, shift });
          requestRedraw();
        },
        onDoubleClick: (node) => {
          if (node) {
            onNodeDoubleClick?.(node);
          }
          applyIntent({ type: "double-click", node });
          requestRedraw();
        },
      });

      return () => {
        raf.stop();
        unsubCameraChange();
        pointer.dispose();
      };
    }, [onNodeClick, onNodeDoubleClick, requestRedraw, updateSelection]);

    // --- Cancel pending RAF on unmount ---
    useEffect(() => {
      return () => {
        if (frameRef.current !== null) {
          cancelAnimationFrame(frameRef.current);
          frameRef.current = null;
        }
      };
    }, []);

    useImperativeHandle(
      ref,
      () => ({
        fitToView: (padding: number = 40) => {
          const graph = graphRef.current;
          const filter = filterRef.current;
          const renderer = rendererRef.current;
          if (!graph || !filter || !renderer) {
            return;
          }
          const visible = graph.nodes.filter((n) =>
            filter.visibleNodes.has(n.id),
          );
          renderer.fitToView(visible, padding);
          requestRedraw();
        },
        selectNode: (id: string) => {
          const graph = graphRef.current;
          if (!graph || !graph.nodeIndex.has(id)) {
            return;
          }
          const current = selectionRef.current;
          updateSelection({
            selected: new Set([id]),
            focusCenter: current.focusCenter,
            focusNeighbors: new Set(current.focusNeighbors),
          });
        },
        clearSelection: () => {
          const graph = graphRef.current;
          const transition = applySelectionIntent({
            state: selectionRef.current,
            intent: { type: "clear" },
            edges: graph?.edges ?? [],
          });
          if (transition.state !== selectionRef.current) {
            updateSelection(transition.state);
          }
        },
        relayout: () => {
          const graph = graphRef.current;
          if (!graph) {
            return;
          }
          for (const node of graph.nodes) {
            node.pinned = false;
          }
          rebuild(graph);
          requestRedraw();
        },
        getNodePosition: (id: string) => {
          const node = graphRef.current?.nodeIndex.get(id);
          if (!node) {
            return null;
          }
          return { x: node.x, y: node.y };
        },
      }),
      [rebuild, requestRedraw, updateSelection],
    );

    const canvasWidth = Math.max(1, Math.floor(size.width * dpr));
    const canvasHeight = Math.max(1, Math.floor(size.height * dpr));
    const containerStyle = makeContainerStyle(props.width, props.height);

    return (
      <div
        ref={containerRef}
        className={props.className}
        style={containerStyle}
      >
        <canvas
          ref={canvasRef}
          width={canvasWidth}
          height={canvasHeight}
          style={{
            display: "block",
            width: `${size.width}px`,
            height: `${size.height}px`,
            touchAction: "none",
          }}
        />
      </div>
    );
  },
);

// --- External-store hooks ---

function useContainerSize(
  ref: React.RefObject<HTMLElement | null>,
): CanvasSize {
  const sizeSnapshotRef = useRef<CanvasSize>(DEFAULT_SIZE);

  const subscribe = useCallback(
    (onChange: () => void) => {
      const element = ref.current;
      if (!element) {
        return () => {};
      }
      const measure = () => {
        const rect = element.getBoundingClientRect();
        const next: CanvasSize = {
          width: Math.max(1, rect.width),
          height: Math.max(1, rect.height),
        };
        const previous = sizeSnapshotRef.current;
        if (previous.width === next.width && previous.height === next.height) {
          return;
        }
        sizeSnapshotRef.current = next;
        onChange();
      };
      measure();
      const observer = new ResizeObserver(measure);
      observer.observe(element);
      window.addEventListener("resize", measure);
      return () => {
        observer.disconnect();
        window.removeEventListener("resize", measure);
      };
    },
    [ref],
  );

  return useSyncExternalStore(
    subscribe,
    () => sizeSnapshotRef.current,
    () => DEFAULT_SIZE,
  );
}

function useDevicePixelRatio(): number {
  const subscribe = useCallback((onChange: () => void) => {
    if (typeof window === "undefined") {
      return () => {};
    }
    let media: MediaQueryList | null = null;
    const attach = () => {
      media = window.matchMedia(`(resolution: ${window.devicePixelRatio}dppx)`);
      media.addEventListener("change", handler);
    };
    const handler = () => {
      if (media) {
        media.removeEventListener("change", handler);
      }
      onChange();
      attach();
    };
    attach();
    return () => {
      if (media) {
        media.removeEventListener("change", handler);
      }
    };
  }, []);

  return useSyncExternalStore(
    subscribe,
    () =>
      typeof window === "undefined"
        ? 1
        : Math.max(1, window.devicePixelRatio || 1),
    () => 1,
  );
}

function usePrefersDark(): boolean {
  const subscribe = useCallback((onChange: () => void) => {
    if (typeof window === "undefined") {
      return () => {};
    }
    const media = window.matchMedia("(prefers-color-scheme: dark)");
    media.addEventListener("change", onChange);
    return () => {
      media.removeEventListener("change", onChange);
    };
  }, []);
  return useSyncExternalStore(
    subscribe,
    () =>
      typeof window !== "undefined" &&
      window.matchMedia("(prefers-color-scheme: dark)").matches,
    () => false,
  );
}

function useResolvedTheme(theme: "dark" | "light" | "auto"): ThemeColors {
  const prefersDark = usePrefersDark();
  if (theme === "dark") {
    return DARK_THEME;
  }
  if (theme === "light") {
    return LIGHT_THEME;
  }
  return prefersDark ? DARK_THEME : LIGHT_THEME;
}

function makeContainerStyle(
  width: number | undefined,
  height: number | undefined,
): CSSProperties {
  return {
    position: "relative",
    width: width ?? "100%",
    height: height ?? "100%",
    minHeight: height ? undefined : 320,
    overflow: "hidden",
  };
}
