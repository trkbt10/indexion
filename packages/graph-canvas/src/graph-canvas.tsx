/**
 * @file React wrapper around the canvas graph viewer.
 */

import {
  forwardRef,
  useCallback,
  useEffect,
  useImperativeHandle,
  useMemo,
  useRef,
  useState,
  type CSSProperties,
} from "react";
import type {
  Camera,
  ForceConfig,
  GraphCanvasHandle,
  GraphCanvasProps,
  SelectionState,
  ThemeColors,
  ViewGraph,
  ViewNode,
} from "./types.ts";
import { DEFAULT_CAMERA, DEFAULT_FORCE_CONFIG } from "./types.ts";
import { computeFilter } from "./filter.ts";
import { clearSelection, createSelectionState, enterFocusMode, exitFocusMode, toggleSelect } from "./interaction/selection.ts";
import { createSpatialHash, type SpatialHash } from "./interaction/hit-test.ts";
import { createPointerHandler } from "./interaction/pointer.ts";
import { diffGraph, normalizeGraph } from "./normalize.ts";
import { fitToView } from "./renderer/camera.ts";
import { renderFrame, type CanvasSize } from "./renderer/canvas-renderer.ts";
import { DARK_THEME, LIGHT_THEME } from "./renderer/styles.ts";
import { circularLayout } from "./simulation/layout.ts";
import { createSimulation, reheat, tick, type SimulationState } from "./simulation/simulation.ts";

const INITIAL_FIT_TICKS = 50;
const DEFAULT_SIZE: CanvasSize = { width: 640, height: 420 };

export const GraphCanvas = forwardRef<GraphCanvasHandle, GraphCanvasProps>(
  function GraphCanvas(props, ref) {
    const containerRef = useRef<HTMLDivElement>(null);
    const canvasRef = useRef<HTMLCanvasElement>(null);
    const cameraRef = useRef<Camera>({ ...DEFAULT_CAMERA });
    const simulationRef = useRef<SimulationState>(createSimulation());
    const spatialHashRef = useRef<SpatialHash>(createSpatialHash());
    const frameRef = useRef<number | null>(null);
    const graphRef = useRef<ViewGraph>(createInitialGraph(props.graph));
    const filterRef = useRef(computeFilter(graphRef.current));
    const selectionRef = useRef<SelectionState>(createSelectionState());
    const stylesRef = useRef<ThemeColors>(LIGHT_THEME);
    const hoverNodeRef = useRef<ViewNode | null>(null);
    const sizeRef = useRef<CanvasSize>(DEFAULT_SIZE);
    const configRef = useRef<ForceConfig>(mergeForceConfig(props.simulationConfig));
    const dprRef = useRef(getDevicePixelRatio());
    const autoFitDoneRef = useRef(false);
    const simulationTicksRef = useRef(0);

    const [viewGraph, setViewGraph] = useState<ViewGraph>(graphRef.current);
    const [selection, setSelection] = useState<SelectionState>(selectionRef.current);
    const [hoverNode, setHoverNode] = useState<ViewNode | null>(null);
    const [containerSize, setContainerSize] = useState<CanvasSize>(DEFAULT_SIZE);
    const [dpr, setDpr] = useState(dprRef.current);
    const theme = useResolvedTheme(props.theme ?? "auto");

    const forceConfig = useMemo(
      () => mergeForceConfig(props.simulationConfig),
      [props.simulationConfig],
    );
    configRef.current = forceConfig;
    stylesRef.current = theme;
    selectionRef.current = selection;
    hoverNodeRef.current = hoverNode;
    dprRef.current = dpr;

    const size = useMemo(
      () => resolveCanvasSize(props.width, props.height, containerSize),
      [props.width, props.height, containerSize],
    );
    sizeRef.current = size;

    const filter = useMemo(
      () =>
        computeFilter(
          viewGraph,
          props.enabledNodeKinds,
          props.enabledEdgeKinds,
          props.hideDisconnected,
          props.searchQuery,
        ),
      [
        viewGraph,
        props.enabledNodeKinds,
        props.enabledEdgeKinds,
        props.hideDisconnected,
        props.searchQuery,
      ],
    );
    filterRef.current = filter;

    const renderCurrentFrame = useCallback(() => {
      const canvas = canvasRef.current;
      if (!canvas) return;
      const ctx = canvas.getContext("2d");
      if (!ctx) return;
      const currentSize = sizeRef.current;
      if (currentSize.width <= 0 || currentSize.height <= 0) return;
      renderFrame(
        ctx,
        graphRef.current,
        cameraRef.current,
        filterRef.current,
        selectionRef.current,
        stylesRef.current,
        hoverNodeRef.current,
        currentSize,
        dprRef.current,
      );
    }, []);

    const scheduleFrame = useCallback(() => {
      if (frameRef.current !== null) return;
      frameRef.current = requestAnimationFrame(() => {
        frameRef.current = null;
        const simulation = simulationRef.current;
        if (simulation.running) {
          tick(simulation, graphRef.current, configRef.current);
          simulationTicksRef.current += 1;
        }
        spatialHashRef.current.rebuild(visibleNodesForHitTest(graphRef.current, filterRef.current.visibleNodes));
        maybeInitialFit(
          autoFitDoneRef,
          simulationTicksRef,
          cameraRef.current,
          graphRef.current,
          filterRef.current.visibleNodes,
          sizeRef.current,
        );
        renderCurrentFrame();
        if (simulation.running) {
          scheduleFrame();
        }
      });
    }, [renderCurrentFrame]);

    const updateSelection = useCallback(
      (next: SelectionState) => {
        selectionRef.current = next;
        setSelection(next);
        props.onSelectionChange?.(next.selected);
        scheduleFrame();
      },
      [props.onSelectionChange, scheduleFrame],
    );

    useEffect(() => {
      graphRef.current = viewGraph;
      spatialHashRef.current.rebuild(visibleNodesForHitTest(viewGraph, filter.visibleNodes));
      scheduleFrame();
    }, [filter.visibleNodes, scheduleFrame, viewGraph]);

    useEffect(() => {
      const nextGraph = diffGraph(graphRef.current, normalizeGraph(props.graph));
      circularLayout(nextGraph.nodes, nextGraph.edges);
      graphRef.current = nextGraph;
      setViewGraph(nextGraph);
      reheat(simulationRef.current, 0.6);
      scheduleFrame();
    }, [props.graph, scheduleFrame]);

    useEffect(() => {
      const container = containerRef.current;
      if (!container) return;

      const updateSize = () => {
        const rect = container.getBoundingClientRect();
        setContainerSize({
          width: Math.max(1, rect.width),
          height: Math.max(1, rect.height),
        });
        setDpr(getDevicePixelRatio());
      };

      updateSize();
      const observer = new ResizeObserver(updateSize);
      observer.observe(container);
      window.addEventListener("resize", updateSize);
      return () => {
        observer.disconnect();
        window.removeEventListener("resize", updateSize);
      };
    }, []);

    useEffect(() => {
      const canvas = canvasRef.current;
      if (!canvas) return;
      const handler = createPointerHandler(canvas, cameraRef.current, spatialHashRef.current, {
        onNodeClick: (node, shift) => {
          props.onNodeClick?.(node);
          updateSelection(toggleSelect(selectionRef.current, node.id, shift));
        },
        onNodeDoubleClick: (node) => {
          props.onNodeDoubleClick?.(node);
          const next = selectionRef.current.focusCenter === node.id
            ? exitFocusMode(selectionRef.current)
            : enterFocusMode(selectionRef.current, node.id, graphRef.current.edges);
          updateSelection(next);
        },
        onBackgroundClick: (shift) => {
          if (!shift) {
            updateSelection(clearSelection(selectionRef.current));
          }
        },
        onBackgroundDoubleClick: () => {
          updateSelection(exitFocusMode(selectionRef.current));
        },
        onDrag: () => {
          scheduleFrame();
        },
        onHover: (node) => {
          hoverNodeRef.current = node;
          setHoverNode(node);
        },
        onReheat: () => {
          reheat(simulationRef.current, 0.3);
        },
        requestRedraw: scheduleFrame,
      });
      handler.attach();
      return () => {
        handler.detach();
      };
    }, [props.onNodeClick, props.onNodeDoubleClick, scheduleFrame, updateSelection]);

    useEffect(() => {
      scheduleFrame();
    }, [filter, selection, hoverNode, size, theme, dpr, scheduleFrame]);

    useEffect(() => {
      return () => {
        if (frameRef.current !== null) {
          cancelAnimationFrame(frameRef.current);
        }
      };
    }, []);

    useImperativeHandle(
      ref,
      () => ({
        fitToView: (padding: number = 40) => {
          fitToView(
            cameraRef.current,
            visibleNodesForHitTest(graphRef.current, filterRef.current.visibleNodes),
            sizeRef.current.width,
            sizeRef.current.height,
            padding,
          );
          scheduleFrame();
        },
        selectNode: (id: string) => {
          if (!graphRef.current.nodeIndex.has(id)) return;
          updateSelection({
            selected: new Set([id]),
            focusCenter: selectionRef.current.focusCenter,
            focusNeighbors: new Set(selectionRef.current.focusNeighbors),
          });
        },
        clearSelection: () => {
          updateSelection(clearSelection(selectionRef.current));
        },
        resetSimulation: () => {
          resetNodePositions(graphRef.current);
          circularLayout(graphRef.current.nodes, graphRef.current.edges);
          reheat(simulationRef.current, 1);
          simulationTicksRef.current = 0;
          autoFitDoneRef.current = false;
          scheduleFrame();
        },
        getNodePosition: (id: string) => {
          const node = graphRef.current.nodeIndex.get(id);
          if (!node) return null;
          return { x: node.x, y: node.y };
        },
      }),
      [scheduleFrame, updateSelection],
    );

    const canvasWidth = Math.max(1, Math.floor(size.width * dpr));
    const canvasHeight = Math.max(1, Math.floor(size.height * dpr));
    const containerStyle = makeContainerStyle(props.width, props.height);

    return (
      <div ref={containerRef} className={props.className} style={containerStyle}>
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

function createInitialGraph(graph: GraphCanvasProps["graph"]): ViewGraph {
  const normalized = normalizeGraph(graph);
  circularLayout(normalized.nodes, normalized.edges);
  return normalized;
}

function mergeForceConfig(config: Partial<ForceConfig> | undefined): ForceConfig {
  return { ...DEFAULT_FORCE_CONFIG, ...config };
}

function useResolvedTheme(theme: "dark" | "light" | "auto"): ThemeColors {
  const [prefersDark, setPrefersDark] = useState(() => getPrefersDark());

  useEffect(() => {
    if (theme !== "auto") return;
    const media = window.matchMedia("(prefers-color-scheme: dark)");
    const onChange = () => {
      setPrefersDark(media.matches);
    };
    onChange();
    media.addEventListener("change", onChange);
    return () => {
      media.removeEventListener("change", onChange);
    };
  }, [theme]);

  if (theme === "dark") return DARK_THEME;
  if (theme === "light") return LIGHT_THEME;
  return prefersDark ? DARK_THEME : LIGHT_THEME;
}

function getPrefersDark(): boolean {
  if (typeof window === "undefined") return false;
  return window.matchMedia("(prefers-color-scheme: dark)").matches;
}

function resolveCanvasSize(
  width: number | undefined,
  height: number | undefined,
  containerSize: CanvasSize,
): CanvasSize {
  return {
    width: width ?? containerSize.width,
    height: height ?? containerSize.height,
  };
}

function makeContainerStyle(width: number | undefined, height: number | undefined): CSSProperties {
  return {
    position: "relative",
    width: width ?? "100%",
    height: height ?? "100%",
    minHeight: height ? undefined : 320,
    overflow: "hidden",
  };
}

function visibleNodesForHitTest(graph: ViewGraph, visibleNodes: ReadonlySet<string>): ViewNode[] {
  return graph.nodes.filter((node) => visibleNodes.has(node.id));
}

function maybeInitialFit(
  autoFitDoneRef: { current: boolean },
  simulationTicksRef: { current: number },
  camera: Camera,
  graph: ViewGraph,
  visibleNodes: ReadonlySet<string>,
  size: CanvasSize,
): void {
  if (autoFitDoneRef.current) return;
  if (simulationTicksRef.current < INITIAL_FIT_TICKS) return;
  const nodes = visibleNodesForHitTest(graph, visibleNodes);
  fitToView(camera, nodes, size.width, size.height, 48);
  autoFitDoneRef.current = true;
}

function resetNodePositions(graph: ViewGraph): void {
  for (const node of graph.nodes) {
    node.x = 0;
    node.y = 0;
    node.vx = 0;
    node.vy = 0;
    node.pinned = false;
  }
}

function getDevicePixelRatio(): number {
  if (typeof window === "undefined") return 1;
  return Math.max(1, window.devicePixelRatio || 1);
}
