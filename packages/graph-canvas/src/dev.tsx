import { StrictMode, useMemo, useRef, useState } from "react";
import { createRoot } from "react-dom/client";
import { GraphCanvas } from "./graph-canvas.tsx";
import type { GraphCanvasHandle, GraphJSON } from "./types.ts";
import "./dev.css";

const EDGE_KINDS = ["dependency", "calls", "extends", "implements", "declares", "references", "imports"];

function DevApp() {
  const graphRef = useRef<GraphCanvasHandle>(null);
  const [theme, setTheme] = useState<"dark" | "light">("dark");
  const [searchQuery, setSearchQuery] = useState("");
  const [enabledEdgeKinds, setEnabledEdgeKinds] = useState<Set<string>>(() => new Set(EDGE_KINDS));
  const graph = useMemo(() => sampleGraph(), []);

  const toggleEdgeKind = (kind: string) => {
    setEnabledEdgeKinds((current) => {
      const next = new Set(current);
      if (next.has(kind)) {
        next.delete(kind);
      } else {
        next.add(kind);
      }
      return next;
    });
  };

  return (
    <main style={styles.page}>
      <div style={styles.toolbar}>
        <div style={styles.titleGroup}>
          <h1 style={styles.title}>Code Graph</h1>
          <p style={styles.subtitle}>Drag nodes, pan the background, scroll to zoom, double-click to focus.</p>
        </div>
        <input
          aria-label="Search graph"
          value={searchQuery}
          onChange={(event) => setSearchQuery(event.target.value)}
          placeholder="Search label or id"
          style={styles.input}
        />
        <button
          type="button"
          onClick={() => setTheme((current) => (current === "dark" ? "light" : "dark"))}
          style={styles.button}
        >
          {theme === "dark" ? "Light" : "Dark"}
        </button>
        <button type="button" onClick={() => graphRef.current?.fitToView()} style={styles.button}>
          Fit
        </button>
      </div>

      <div style={styles.filters}>
        {EDGE_KINDS.map((kind) => (
          <label key={kind} style={styles.checkboxLabel}>
            <input
              type="checkbox"
              checked={enabledEdgeKinds.has(kind)}
              onChange={() => toggleEdgeKind(kind)}
            />
            {kind}
          </label>
        ))}
      </div>

      <section style={styles.viewer}>
        <GraphCanvas
          ref={graphRef}
          graph={graph}
          theme={theme}
          enabledEdgeKinds={enabledEdgeKinds}
          searchQuery={searchQuery}
          hideDisconnected={false}
          onNodeClick={(node) => {
            console.log("node click", node.id);
          }}
          onNodeDoubleClick={(node) => {
            console.log("node double click", node.id);
          }}
        />
      </section>
    </main>
  );
}

const styles: Record<string, React.CSSProperties> = {
  page: {
    width: "100vw",
    height: "100vh",
    margin: 0,
    display: "grid",
    gridTemplateRows: "auto auto 1fr",
    background: "#18181b",
    color: "#f9fafb",
    fontFamily: "ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, Segoe UI, sans-serif",
  },
  toolbar: {
    display: "flex",
    alignItems: "center",
    gap: 12,
    padding: "14px 16px 10px",
    borderBottom: "1px solid #3f3f46",
    background: "#27272a",
  },
  titleGroup: {
    minWidth: 220,
    flex: 1,
  },
  title: {
    margin: 0,
    fontSize: 20,
    fontWeight: 700,
  },
  subtitle: {
    margin: "4px 0 0",
    color: "#d4d4d8",
    fontSize: 13,
  },
  input: {
    width: 220,
    border: "1px solid #52525b",
    borderRadius: 6,
    background: "#09090b",
    color: "#f9fafb",
    padding: "8px 10px",
  },
  button: {
    border: "1px solid #71717a",
    borderRadius: 6,
    background: "#0f766e",
    color: "#ffffff",
    padding: "8px 12px",
    cursor: "pointer",
  },
  filters: {
    display: "flex",
    flexWrap: "wrap",
    gap: 12,
    padding: "10px 16px",
    background: "#18181b",
    borderBottom: "1px solid #3f3f46",
  },
  checkboxLabel: {
    display: "inline-flex",
    alignItems: "center",
    gap: 6,
    fontSize: 13,
    color: "#e5e7eb",
  },
  viewer: {
    minHeight: 0,
  },
};

function sampleGraph(): GraphJSON {
  const nodes = [
    { id: "mod:index", label: "src/index.mbt", kind: "module", file: "src/index.mbt" },
    { id: "mod:graph", label: "src/graph.mbt", kind: "module", file: "src/graph.mbt" },
    { id: "mod:parser", label: "src/parser.mbt", kind: "module", file: "src/parser.mbt" },
    { id: "mod:filter", label: "src/filter.mbt", kind: "module", file: "src/filter.mbt" },
    { id: "mod:wiki", label: "src/wiki.mbt", kind: "module", file: "src/wiki.mbt" },
    { id: "mod:api", label: "packages/api", kind: "module", file: "packages/api/src/lib.mbt" },
    { id: "ext:moonbit", label: "moonbitlang/core", kind: "external" },
    { id: "ext:vscode", label: "vscode", kind: "external" },
    { id: "fn:buildGraph", label: "buildGraph", kind: "function", file: "src/graph.mbt" },
    { id: "fn:addNode", label: "addNode", kind: "function", file: "src/graph.mbt" },
    { id: "fn:addEdge", label: "addEdge", kind: "function", file: "src/graph.mbt" },
    { id: "fn:parseFile", label: "parseFile", kind: "function", file: "src/parser.mbt" },
    { id: "fn:parseSymbol", label: "parseSymbol", kind: "function", file: "src/parser.mbt" },
    { id: "fn:filterFiles", label: "filterFiles", kind: "function", file: "src/filter.mbt" },
    { id: "fn:matchPattern", label: "matchPattern", kind: "function", file: "src/filter.mbt" },
    { id: "fn:renderWiki", label: "renderWiki", kind: "function", file: "src/wiki.mbt" },
    { id: "fn:fetchGraph", label: "fetchGraph", kind: "function", file: "packages/api/src/client.mbt" },
    { id: "type:CodeGraph", label: "CodeGraph", kind: "type", file: "src/graph.mbt" },
    { id: "type:GraphNode", label: "GraphNode", kind: "struct", file: "src/graph.mbt" },
    { id: "type:GraphEdge", label: "GraphEdge", kind: "struct", file: "src/graph.mbt" },
    { id: "type:FilterConfig", label: "FilterConfig", kind: "type", file: "src/filter.mbt" },
    { id: "type:WikiPage", label: "WikiPage", kind: "struct", file: "src/wiki.mbt" },
    { id: "var:cache", label: "graphCache", kind: "variable", file: "src/index.mbt" },
    { id: "var:patterns", label: "ignorePatterns", kind: "variable", file: "src/filter.mbt" },
    { id: "fn:indexWorkspace", label: "indexWorkspace", kind: "function", file: "src/index.mbt" },
    { id: "fn:loadConfig", label: "loadConfig", kind: "function", file: "src/index.mbt" },
    { id: "fn:writeArtifacts", label: "writeArtifacts", kind: "function", file: "src/wiki.mbt" },
    { id: "type:ApiClient", label: "ApiClient", kind: "type", file: "packages/api/src/client.mbt" },
    { id: "fn:openPreview", label: "openPreview", kind: "function", file: "packages/vscode/src/extension.ts" },
    { id: "type:PreviewPanel", label: "PreviewPanel", kind: "struct", file: "packages/vscode/src/panel.ts" },
  ];

  const edges = [
    { from: "mod:index", to: "mod:graph", kind: "dependency" },
    { from: "mod:index", to: "mod:filter", kind: "dependency" },
    { from: "mod:index", to: "mod:wiki", kind: "dependency" },
    { from: "mod:graph", to: "mod:parser", kind: "dependency" },
    { from: "mod:wiki", to: "mod:api", kind: "imports" },
    { from: "mod:parser", to: "ext:moonbit", kind: "imports" },
    { from: "mod:api", to: "ext:moonbit", kind: "imports" },
    { from: "fn:indexWorkspace", to: "fn:loadConfig", kind: "calls" },
    { from: "fn:indexWorkspace", to: "fn:filterFiles", kind: "calls" },
    { from: "fn:indexWorkspace", to: "fn:buildGraph", kind: "calls" },
    { from: "fn:indexWorkspace", to: "fn:renderWiki", kind: "calls" },
    { from: "fn:buildGraph", to: "fn:parseFile", kind: "calls" },
    { from: "fn:buildGraph", to: "fn:addNode", kind: "calls" },
    { from: "fn:buildGraph", to: "fn:addEdge", kind: "calls" },
    { from: "fn:parseFile", to: "fn:parseSymbol", kind: "calls" },
    { from: "fn:filterFiles", to: "fn:matchPattern", kind: "calls" },
    { from: "fn:renderWiki", to: "fn:writeArtifacts", kind: "calls" },
    { from: "fn:renderWiki", to: "fn:fetchGraph", kind: "calls" },
    { from: "fn:openPreview", to: "fn:fetchGraph", kind: "calls" },
    { from: "type:CodeGraph", to: "type:GraphNode", kind: "declares" },
    { from: "type:CodeGraph", to: "type:GraphEdge", kind: "declares" },
    { from: "fn:buildGraph", to: "type:CodeGraph", kind: "references" },
    { from: "fn:addNode", to: "type:GraphNode", kind: "references" },
    { from: "fn:addEdge", to: "type:GraphEdge", kind: "references" },
    { from: "fn:filterFiles", to: "type:FilterConfig", kind: "references" },
    { from: "fn:renderWiki", to: "type:WikiPage", kind: "references" },
    { from: "fn:fetchGraph", to: "type:ApiClient", kind: "references" },
    { from: "type:PreviewPanel", to: "ext:vscode", kind: "implements" },
    { from: "type:ApiClient", to: "ext:moonbit", kind: "extends" },
    { from: "var:cache", to: "type:CodeGraph", kind: "references" },
    { from: "var:patterns", to: "type:FilterConfig", kind: "references" },
    { from: "mod:wiki", to: "mod:graph", kind: "dependency" },
    { from: "mod:graph", to: "mod:wiki", kind: "references" },
  ];

  return {
    title: "Indexion sample",
    nodes,
    edges,
  };
}

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <DevApp />
  </StrictMode>,
);
