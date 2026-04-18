import { StrictMode, useEffect, useMemo, useRef, useState } from "react";
import type { CSSProperties } from "react";
import { createRoot } from "react-dom/client";
import { GraphCanvas } from "./graph-canvas.tsx";

// Build-time timestamp — injected by Vite's HTML transform (see
// vite.config.ts). Shown in the dev hint bar so we can tell at a
// glance whether the browser is showing a stale bundle vs. the
// freshly-compiled one.
const BUILD_STAMP = new Date().toISOString().slice(11, 19);
import type {
  ClusteringStrategy,
  GraphCanvasHandle,
  GraphInput,
  LayoutStrategyId,
} from "./types.ts";
import { CLUSTERINGS } from "./clustering/index.ts";
import { LAYOUT_STRATEGIES } from "./layout/index.ts";
import "./dev.css";

// Path is relative to Vite's publicDir (./fixtures/) and bundled with
// the dev server. Generated via: `indexion doc graph --format=codegraph`.
const STUB_URL = "/indexion-self.json";

type Theme = "dark" | "light";

type LoadState =
  | { readonly status: "loading" }
  | { readonly status: "ready"; readonly graph: GraphInput }
  | { readonly status: "error"; readonly message: string };

function DevApp() {
  const graphRef = useRef<GraphCanvasHandle>(null);
  const [theme, setTheme] = useState<Theme>("dark");
  const [searchQuery, setSearchQuery] = useState("");
  const [hideDisconnected, setHideDisconnected] = useState(true);
  const [clustering, setClustering] = useState<ClusteringStrategy>("directory");
  const [layoutStrategy, setLayoutStrategy] =
    useState<LayoutStrategyId>("hierarchy");
  const [enabledEdgeKinds, setEnabledEdgeKinds] = useState<Set<string> | null>(
    null,
  );
  const [enabledNodeKinds, setEnabledNodeKinds] = useState<Set<string> | null>(
    null,
  );
  const load = useGraphStub(STUB_URL);

  // Derive kind lists from the loaded graph so the filter UI reflects
  // the real data, not a hardcoded fixture.
  const kindStats = useMemo(
    () => (load.status === "ready" ? summarizeKinds(load.graph) : null),
    [load],
  );

  // Enable every kind by default the first time we see the graph.
  useEffect(() => {
    if (kindStats) {
      setEnabledEdgeKinds((current) => current ?? new Set(kindStats.edgeKinds));
      setEnabledNodeKinds((current) => current ?? new Set(kindStats.nodeKinds));
    }
  }, [kindStats]);

  const toggle = (
    setter: React.Dispatch<React.SetStateAction<Set<string> | null>>,
    value: string,
  ) => {
    setter((current) => {
      const next = new Set(current ?? []);
      if (next.has(value)) {
        next.delete(value);
      } else {
        next.add(value);
      }
      return next;
    });
  };

  const t = theme === "dark" ? darkTokens : lightTokens;

  return (
    <main style={page(t)}>
      <TopBar
        t={t}
        theme={theme}
        stats={statsLabel(kindStats)}
        onToggleTheme={() =>
          setTheme((current) => (current === "dark" ? "light" : "dark"))
        }
        onFit={() => graphRef.current?.fitToView()}
        onReset={() => graphRef.current?.relayout()}
        search={searchQuery}
        onSearch={setSearchQuery}
      />
      <div style={body(t)}>
        <Sidebar
          t={t}
          clustering={clustering}
          onClustering={setClustering}
          layoutStrategy={layoutStrategy}
          onLayoutStrategy={setLayoutStrategy}
          edgeKinds={kindStats?.edgeKinds ?? []}
          enabledEdgeKinds={enabledEdgeKinds ?? new Set()}
          onToggleEdge={(kind) => toggle(setEnabledEdgeKinds, kind)}
          nodeKinds={kindStats?.nodeKinds ?? []}
          enabledNodeKinds={enabledNodeKinds ?? new Set()}
          onToggleNode={(kind) => toggle(setEnabledNodeKinds, kind)}
          hideDisconnected={hideDisconnected}
          onToggleHideDisconnected={() => setHideDisconnected((x) => !x)}
        />
        <section style={viewer(t)}>
          {load.status === "ready" &&
          enabledEdgeKinds !== null &&
          enabledNodeKinds !== null ? (
            <GraphCanvas
              ref={graphRef}
              graph={load.graph}
              theme={theme}
              enabledEdgeKinds={enabledEdgeKinds}
              enabledNodeKinds={enabledNodeKinds}
              searchQuery={searchQuery}
              hideDisconnected={hideDisconnected}
              clustering={clustering}
              layoutStrategy={layoutStrategy}
            />
          ) : (
            <Placeholder t={t} load={load} />
          )}
          <Hint t={t} />
        </section>
      </div>
    </main>
  );
}

function useGraphStub(url: string): LoadState {
  const [state, setState] = useState<LoadState>({ status: "loading" });
  useEffect(() => {
    let cancelled = false;
    fetch(url)
      .then(async (res) => {
        if (!res.ok) {
          throw new Error(`${res.status} ${res.statusText}`);
        }
        const graph = (await res.json()) as GraphInput;
        if (!cancelled) {
          setState({ status: "ready", graph });
        }
      })
      .catch((err: unknown) => {
        if (!cancelled) {
          const message = err instanceof Error ? err.message : String(err);
          setState({ status: "error", message });
        }
      });
    return () => {
      cancelled = true;
    };
  }, [url]);
  return state;
}

type KindStats = {
  readonly nodeKinds: readonly string[];
  readonly edgeKinds: readonly string[];
  readonly moduleCount: number;
  readonly symbolCount: number;
  readonly edgeCount: number;
};

function summarizeKinds(graph: GraphInput): KindStats {
  const nodeKinds = new Set<string>();
  const edgeKinds = new Set<string>();

  if ("modules" in graph && "symbols" in graph) {
    for (const mod of Object.values(graph.modules)) {
      nodeKinds.add(mod.file ? "module" : "external");
    }
    for (const sym of Object.values(graph.symbols)) {
      nodeKinds.add(sym.kind);
    }
    for (const edge of graph.edges) {
      edgeKinds.add(edge.kind);
    }
    return {
      nodeKinds: [...nodeKinds].sort(),
      edgeKinds: [...edgeKinds].sort(),
      moduleCount: Object.keys(graph.modules).length,
      symbolCount: Object.keys(graph.symbols).length,
      edgeCount: graph.edges.length,
    };
  }

  for (const node of graph.nodes) {
    nodeKinds.add(node.kind);
  }
  for (const edge of graph.edges) {
    edgeKinds.add(edge.kind);
  }
  return {
    nodeKinds: [...nodeKinds].sort(),
    edgeKinds: [...edgeKinds].sort(),
    moduleCount: graph.nodes.length,
    symbolCount: 0,
    edgeCount: graph.edges.length,
  };
}

function statsLabel(stats: KindStats | null): string {
  if (!stats) {
    return "";
  }
  const total = stats.moduleCount + stats.symbolCount;
  return `${total.toLocaleString()} nodes · ${stats.edgeCount.toLocaleString()} edges`;
}

function Placeholder(props: { readonly t: Tokens; readonly load: LoadState }) {
  const { t, load } = props;
  return (
    <div style={placeholderWrap(t)}>
      <span style={placeholderText(t)}>{placeholderMessage(load)}</span>
    </div>
  );
}

function placeholderMessage(load: LoadState): string {
  if (load.status === "loading") {
    return "Loading graph…";
  }
  if (load.status === "error") {
    return `Failed to load graph: ${load.message}`;
  }
  return "";
}

// ────────────────────────────────────────────────────────────
// Components

type TopBarProps = {
  readonly t: Tokens;
  readonly theme: Theme;
  readonly stats: string;
  readonly onToggleTheme: () => void;
  readonly onFit: () => void;
  readonly onReset: () => void;
  readonly search: string;
  readonly onSearch: (value: string) => void;
};

function TopBar(props: TopBarProps) {
  const { t } = props;
  return (
    <header style={topbar(t)}>
      <div style={brand(t)}>
        <span style={logoDot(t)} />
        <span style={brandText(t)}>indexion</span>
        <span style={brandDivider(t)} />
        <span style={brandSub(t)}>graph</span>
        {props.stats ? (
          <>
            <span style={brandDivider(t)} />
            <span style={brandStats(t)}>{props.stats}</span>
          </>
        ) : null}
      </div>

      <div style={searchWrap(t)}>
        <SearchIcon color={t.fgMuted} />
        <input
          aria-label="Search graph"
          value={props.search}
          onChange={(event) => props.onSearch(event.target.value)}
          placeholder="Search nodes…"
          style={searchInput(t)}
        />
        <kbd style={kbd(t)}>⌘K</kbd>
      </div>

      <div style={topActions}>
        <IconButton t={t} onClick={props.onFit} label="Fit view">
          Fit
        </IconButton>
        <IconButton t={t} onClick={props.onReset} label="Reset layout">
          Reset
        </IconButton>
        <IconButton
          t={t}
          onClick={props.onToggleTheme}
          label="Toggle theme"
          title={props.theme === "dark" ? "Light mode" : "Dark mode"}
        >
          {props.theme === "dark" ? <SunIcon /> : <MoonIcon />}
        </IconButton>
      </div>
    </header>
  );
}

type SidebarProps = {
  readonly t: Tokens;
  readonly clustering: ClusteringStrategy;
  readonly onClustering: (value: ClusteringStrategy) => void;
  readonly layoutStrategy: LayoutStrategyId;
  readonly onLayoutStrategy: (value: LayoutStrategyId) => void;
  readonly edgeKinds: readonly string[];
  readonly enabledEdgeKinds: Set<string>;
  readonly onToggleEdge: (kind: string) => void;
  readonly nodeKinds: readonly string[];
  readonly enabledNodeKinds: Set<string>;
  readonly onToggleNode: (kind: string) => void;
  readonly hideDisconnected: boolean;
  readonly onToggleHideDisconnected: () => void;
};

function Sidebar(props: SidebarProps) {
  const { t } = props;
  return (
    <aside style={sidebar(t)}>
      <Section t={t} title="Layout">
        <div style={segmentedGroup}>
          {LAYOUT_STRATEGIES.map((s) => (
            <button
              key={s.id}
              type="button"
              title={s.description}
              onClick={() => props.onLayoutStrategy(s.id)}
              style={segmentedBtn(t, props.layoutStrategy === s.id)}
            >
              {s.label}
            </button>
          ))}
        </div>
      </Section>

      <Section t={t} title="Clustering">
        <div style={segmentedGroup}>
          {CLUSTERINGS.map((c) => (
            <button
              key={c.id}
              type="button"
              title={c.description}
              onClick={() => props.onClustering(c.id)}
              style={segmentedBtn(t, props.clustering === c.id)}
            >
              {c.label}
            </button>
          ))}
        </div>
      </Section>

      <Section t={t} title="Display">
        <Switch
          t={t}
          checked={props.hideDisconnected}
          onChange={props.onToggleHideDisconnected}
          label="Hide disconnected"
        />
      </Section>

      <Section t={t} title="Node kinds">
        {props.nodeKinds.length === 0 ? (
          <span style={emptyText(t)}>—</span>
        ) : (
          props.nodeKinds.map((kind) => (
            <Row
              key={kind}
              t={t}
              checked={props.enabledNodeKinds.has(kind)}
              onToggle={() => props.onToggleNode(kind)}
              label={kind}
            />
          ))
        )}
      </Section>

      <Section t={t} title="Edge kinds">
        {props.edgeKinds.length === 0 ? (
          <span style={emptyText(t)}>—</span>
        ) : (
          props.edgeKinds.map((kind) => (
            <Row
              key={kind}
              t={t}
              checked={props.enabledEdgeKinds.has(kind)}
              onToggle={() => props.onToggleEdge(kind)}
              label={kind}
            />
          ))
        )}
      </Section>
    </aside>
  );
}

function Section(props: {
  readonly t: Tokens;
  readonly title: string;
  readonly children: React.ReactNode;
}) {
  return (
    <div style={sectionWrap}>
      <div style={sectionTitle(props.t)}>{props.title}</div>
      <div style={sectionBody}>{props.children}</div>
    </div>
  );
}

function Row(props: {
  readonly t: Tokens;
  readonly checked: boolean;
  readonly onToggle: () => void;
  readonly label: string;
}) {
  const { t } = props;
  return (
    <button
      type="button"
      onClick={props.onToggle}
      style={rowBtn(t, props.checked)}
    >
      <span style={rowDot(t, props.checked)} />
      <span style={rowLabel(t, props.checked)}>{props.label}</span>
    </button>
  );
}

function Switch(props: {
  readonly t: Tokens;
  readonly checked: boolean;
  readonly onChange: () => void;
  readonly label: string;
}) {
  const { t } = props;
  return (
    <button type="button" onClick={props.onChange} style={switchRow(t)}>
      <span style={switchLabel(t)}>{props.label}</span>
      <span style={switchTrack(t, props.checked)}>
        <span style={switchThumb(t, props.checked)} />
      </span>
    </button>
  );
}

function IconButton(props: {
  readonly t: Tokens;
  readonly onClick: () => void;
  readonly label: string;
  readonly title?: string;
  readonly children: React.ReactNode;
}) {
  return (
    <button
      type="button"
      onClick={props.onClick}
      aria-label={props.label}
      title={props.title ?? props.label}
      style={iconBtn(props.t)}
    >
      {props.children}
    </button>
  );
}

function Hint(props: { readonly t: Tokens }) {
  return (
    <div style={hintBox(props.t)}>
      <HintItem label="drag" desc="move node" />
      <HintItem label="scroll" desc="zoom" />
      <HintItem label="dbl-click" desc="focus" />
      <HintItem label="build" desc={BUILD_STAMP} />
    </div>
  );
}

function HintItem(props: { readonly label: string; readonly desc: string }) {
  return (
    <div style={hintItem}>
      <span style={hintLabel}>{props.label}</span>
      <span style={hintDesc}>{props.desc}</span>
    </div>
  );
}

// ────────────────────────────────────────────────────────────
// Icons (inline SVG, 14px)

function SearchIcon(props: { readonly color: string }) {
  return (
    <svg width="14" height="14" viewBox="0 0 14 14" fill="none" aria-hidden>
      <circle cx="6" cy="6" r="4.25" stroke={props.color} strokeWidth="1.2" />
      <path
        d="M9.5 9.5L12 12"
        stroke={props.color}
        strokeWidth="1.2"
        strokeLinecap="round"
      />
    </svg>
  );
}

function SunIcon() {
  return (
    <svg width="14" height="14" viewBox="0 0 14 14" fill="none" aria-hidden>
      <circle cx="7" cy="7" r="2.5" stroke="currentColor" strokeWidth="1.2" />
      <path
        d="M7 1.5v1.5M7 11v1.5M1.5 7h1.5M11 7h1.5M3.2 3.2l1 1M9.8 9.8l1 1M3.2 10.8l1-1M9.8 4.2l1-1"
        stroke="currentColor"
        strokeWidth="1.2"
        strokeLinecap="round"
      />
    </svg>
  );
}

function MoonIcon() {
  return (
    <svg width="14" height="14" viewBox="0 0 14 14" fill="none" aria-hidden>
      <path
        d="M11.5 8.5A5 5 0 0 1 5.5 2.5a5 5 0 1 0 6 6z"
        stroke="currentColor"
        strokeWidth="1.2"
        strokeLinejoin="round"
      />
    </svg>
  );
}

// ────────────────────────────────────────────────────────────
// Design tokens

type Tokens = {
  readonly bg: string;
  readonly bgElevated: string;
  readonly bgSubtle: string;
  readonly border: string;
  readonly borderStrong: string;
  readonly fg: string;
  readonly fgMuted: string;
  readonly fgSubtle: string;
  readonly accent: string;
  readonly accentFg: string;
  readonly focus: string;
};

const darkTokens: Tokens = {
  bg: "#09090b",
  bgElevated: "#0f0f11",
  bgSubtle: "#18181b",
  border: "#1f1f23",
  borderStrong: "#27272a",
  fg: "#fafafa",
  fgMuted: "#a1a1aa",
  fgSubtle: "#52525b",
  accent: "#fafafa",
  accentFg: "#09090b",
  focus: "rgba(250, 250, 250, 0.15)",
};

const lightTokens: Tokens = {
  bg: "#ffffff",
  bgElevated: "#ffffff",
  bgSubtle: "#fafafa",
  border: "#e4e4e7",
  borderStrong: "#d4d4d8",
  fg: "#09090b",
  fgMuted: "#52525b",
  fgSubtle: "#a1a1aa",
  accent: "#09090b",
  accentFg: "#ffffff",
  focus: "rgba(9, 9, 11, 0.12)",
};

// ────────────────────────────────────────────────────────────
// Styles

const FONT_STACK =
  'Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif';
const MONO_STACK =
  'ui-monospace, SFMono-Regular, "SF Mono", Menlo, Consolas, "Liberation Mono", monospace';

const page = (t: Tokens): CSSProperties => ({
  width: "100vw",
  height: "100vh",
  margin: 0,
  display: "grid",
  gridTemplateRows: "48px 1fr",
  background: t.bg,
  color: t.fg,
  fontFamily: FONT_STACK,
  fontSize: 13,
  letterSpacing: "-0.003em",
  WebkitFontSmoothing: "antialiased",
});

const topbar = (t: Tokens): CSSProperties => ({
  display: "grid",
  gridTemplateColumns:
    "minmax(220px, 1fr) minmax(300px, 520px) minmax(220px, 1fr)",
  alignItems: "center",
  gap: 16,
  padding: "0 16px",
  borderBottom: `1px solid ${t.border}`,
  background: t.bgElevated,
});

const brand = (_t: Tokens): CSSProperties => ({
  display: "flex",
  alignItems: "center",
  gap: 10,
});

const logoDot = (t: Tokens): CSSProperties => ({
  width: 8,
  height: 8,
  borderRadius: 2,
  background: t.fg,
  boxShadow: `0 0 0 3px ${t.bgSubtle}`,
});

const brandText = (t: Tokens): CSSProperties => ({
  fontSize: 13,
  fontWeight: 600,
  color: t.fg,
  letterSpacing: "-0.01em",
});

const brandDivider = (t: Tokens): CSSProperties => ({
  width: 1,
  height: 14,
  background: t.border,
});

const brandSub = (t: Tokens): CSSProperties => ({
  fontSize: 12,
  color: t.fgMuted,
  fontWeight: 500,
});

const brandStats = (t: Tokens): CSSProperties => ({
  fontFamily: MONO_STACK,
  fontSize: 11,
  color: t.fgSubtle,
});

const placeholderWrap = (t: Tokens): CSSProperties => ({
  display: "flex",
  alignItems: "center",
  justifyContent: "center",
  width: "100%",
  height: "100%",
  background: t.bg,
});

const placeholderText = (t: Tokens): CSSProperties => ({
  fontFamily: MONO_STACK,
  fontSize: 12,
  color: t.fgMuted,
});

const segmentedGroup: CSSProperties = {
  display: "flex",
  flexWrap: "wrap",
  gap: 4,
  padding: "0 6px",
};

const segmentedBtn = (t: Tokens, active: boolean): CSSProperties => ({
  flex: "1 1 auto",
  minWidth: 48,
  padding: "5px 8px",
  fontFamily: MONO_STACK,
  fontSize: 11,
  fontWeight: 500,
  color: active ? t.accentFg : t.fgMuted,
  background: active ? t.accent : "transparent",
  border: `1px solid ${active ? t.accent : t.border}`,
  borderRadius: 4,
  cursor: "pointer",
  transition:
    "background 120ms ease, color 120ms ease, border-color 120ms ease",
  textAlign: "left",
});

const emptyText = (t: Tokens): CSSProperties => ({
  fontFamily: MONO_STACK,
  fontSize: 11,
  color: t.fgSubtle,
  padding: "4px 8px",
});

const searchWrap = (t: Tokens): CSSProperties => ({
  display: "flex",
  alignItems: "center",
  gap: 8,
  height: 30,
  padding: "0 10px",
  border: `1px solid ${t.border}`,
  borderRadius: 6,
  background: t.bgSubtle,
  justifySelf: "stretch",
});

const searchInput = (t: Tokens): CSSProperties => ({
  flex: 1,
  border: "none",
  outline: "none",
  background: "transparent",
  color: t.fg,
  fontFamily: FONT_STACK,
  fontSize: 13,
  padding: 0,
});

const kbd = (t: Tokens): CSSProperties => ({
  fontFamily: MONO_STACK,
  fontSize: 11,
  color: t.fgSubtle,
  background: t.bg,
  border: `1px solid ${t.border}`,
  borderRadius: 4,
  padding: "2px 5px",
  lineHeight: 1,
});

const topActions: CSSProperties = {
  display: "flex",
  alignItems: "center",
  gap: 6,
  justifySelf: "end",
};

const iconBtn = (t: Tokens): CSSProperties => ({
  display: "inline-flex",
  alignItems: "center",
  justifyContent: "center",
  gap: 6,
  minWidth: 30,
  height: 30,
  padding: "0 10px",
  fontFamily: FONT_STACK,
  fontSize: 12,
  fontWeight: 500,
  color: t.fg,
  background: "transparent",
  border: `1px solid ${t.border}`,
  borderRadius: 6,
  cursor: "pointer",
  transition: "background 120ms ease, border-color 120ms ease",
});

const body = (t: Tokens): CSSProperties => ({
  display: "grid",
  gridTemplateColumns: "240px 1fr",
  minHeight: 0,
  background: t.bg,
});

const sidebar = (t: Tokens): CSSProperties => ({
  display: "flex",
  flexDirection: "column",
  gap: 20,
  padding: "16px 12px",
  borderRight: `1px solid ${t.border}`,
  background: t.bgElevated,
  overflowY: "auto",
});

const sectionWrap: CSSProperties = {
  display: "flex",
  flexDirection: "column",
  gap: 6,
};

const sectionTitle = (t: Tokens): CSSProperties => ({
  fontFamily: MONO_STACK,
  fontSize: 10,
  fontWeight: 500,
  letterSpacing: "0.08em",
  textTransform: "uppercase",
  color: t.fgSubtle,
  padding: "0 8px",
  marginBottom: 2,
});

const sectionBody: CSSProperties = {
  display: "flex",
  flexDirection: "column",
  gap: 1,
};

const rowBtn = (t: Tokens, checked: boolean): CSSProperties => ({
  display: "flex",
  alignItems: "center",
  gap: 10,
  padding: "6px 8px",
  background: "transparent",
  border: "none",
  borderRadius: 4,
  cursor: "pointer",
  textAlign: "left",
  transition: "background 120ms ease",
  opacity: checked ? 1 : 0.55,
});

const rowDot = (t: Tokens, checked: boolean): CSSProperties => ({
  width: 6,
  height: 6,
  borderRadius: 999,
  background: checked ? t.fg : "transparent",
  border: `1px solid ${checked ? t.fg : t.borderStrong}`,
  flexShrink: 0,
});

const rowLabel = (t: Tokens, checked: boolean): CSSProperties => ({
  fontSize: 12,
  fontWeight: 500,
  color: checked ? t.fg : t.fgMuted,
  fontFamily: MONO_STACK,
  letterSpacing: "-0.01em",
});

const switchRow = (_t: Tokens): CSSProperties => ({
  display: "flex",
  alignItems: "center",
  justifyContent: "space-between",
  gap: 10,
  padding: "6px 8px",
  background: "transparent",
  border: "none",
  borderRadius: 4,
  cursor: "pointer",
  width: "100%",
});

const switchLabel = (t: Tokens): CSSProperties => ({
  fontSize: 12,
  fontWeight: 500,
  color: t.fg,
});

const switchTrack = (t: Tokens, checked: boolean): CSSProperties => ({
  position: "relative",
  width: 26,
  height: 14,
  borderRadius: 999,
  background: checked ? t.fg : t.borderStrong,
  transition: "background 120ms ease",
  flexShrink: 0,
});

const switchThumb = (t: Tokens, checked: boolean): CSSProperties => ({
  position: "absolute",
  top: 2,
  left: checked ? 14 : 2,
  width: 10,
  height: 10,
  borderRadius: 999,
  background: checked ? t.bg : t.bgElevated,
  transition: "left 140ms ease",
});

const viewer = (t: Tokens): CSSProperties => ({
  position: "relative",
  minHeight: 0,
  minWidth: 0,
  background: t.bg,
});

const hintBox = (t: Tokens): CSSProperties => ({
  position: "absolute",
  bottom: 12,
  right: 12,
  display: "flex",
  gap: 12,
  padding: "6px 10px",
  borderRadius: 6,
  background: t.bgElevated,
  border: `1px solid ${t.border}`,
  pointerEvents: "none",
  fontFamily: MONO_STACK,
  fontSize: 11,
});

const hintItem: CSSProperties = {
  display: "flex",
  alignItems: "center",
  gap: 6,
};

const hintLabel: CSSProperties = {
  color: "currentColor",
  opacity: 0.95,
};

const hintDesc: CSSProperties = {
  opacity: 0.5,
};

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <DevApp />
  </StrictMode>,
);
