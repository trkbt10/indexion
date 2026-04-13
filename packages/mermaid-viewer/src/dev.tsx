/**
 * @file Dev entry point for testing MermaidDiagram in isolation.
 *
 * Run `bun run dev` to start the Vite dev server.
 */

import ReactDOM from "react-dom/client";
import { MermaidDiagram } from "./mermaid-diagram.tsx";
import "./dev.css";

const SAMPLES = [
  {
    title: "Flowchart",
    code: `graph TD
    A[Start] --> B{Is it working?}
    B -->|Yes| C[Great!]
    B -->|No| D[Debug]
    D --> B`,
  },
  {
    title: "Sequence",
    code: `sequenceDiagram
    participant A as Client
    participant B as Server
    A->>B: Request
    B-->>A: Response`,
  },
  {
    title: "State",
    code: `stateDiagram-v2
    [*] --> Idle
    Idle --> Loading: fetch
    Loading --> Ready: success
    Loading --> Error: fail
    Error --> Loading: retry`,
  },
];

const App = (): React.JSX.Element => (
  <div style={{ maxWidth: 800, margin: "0 auto", padding: 24 }}>
    <h1 style={{ fontSize: 24, marginBottom: 16 }}>Mermaid Viewer — Dev</h1>
    {SAMPLES.map((s) => (
      <section key={s.title} style={{ marginBottom: 32 }}>
        <h2 style={{ fontSize: 18, marginBottom: 8 }}>{s.title}</h2>
        <MermaidDiagram code={s.code} className="my-4" />
        <details style={{ marginTop: 8, fontSize: 12, color: "#888" }}>
          <summary>Source</summary>
          <pre style={{ whiteSpace: "pre-wrap" }}>{s.code}</pre>
        </details>
      </section>
    ))}
  </div>
);

const root = document.getElementById("root");
if (root) {
  ReactDOM.createRoot(root).render(<App />);
}
