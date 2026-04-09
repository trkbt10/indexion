# packages/wiki -- DeepWiki Frontend

The wiki package is a React SPA that serves as the visual frontend for indexion.
It provides a code explorer, 3D dependency graph, auto-generated wiki pages, and
a settings page. The app communicates with the `indexion serve` backend via the
`@indexion/api-client` package and supports both live-server and static export modes.

## Architecture

```mermaid
graph TD
    subgraph "App Shell"
        main["main.tsx<br/>React root"] --> router["router.tsx<br/>react-router"]
        router --> layout["AppLayout<br/>Header + ConnectionGuard + CommandPalette"]
    end

    subgraph "Pages"
        layout --> explorer["ExplorerPage<br/>File similarity explorer"]
        layout --> graph["GraphPage<br/>3D dependency graph (Three.js)"]
        layout --> wiki["WikiPage<br/>Auto-generated documentation"]
        layout --> settings["SettingsPage"]
    end

    subgraph "Shared Components"
        kgf_block["KgfCodeBlock<br/>Client-side syntax highlighting"]
        mermaid_diag["MermaidDiagram"]
        cmd_palette["CommandPalette (cmdk)"]
        conn_guard["ConnectionGuard<br/>Server health check"]
    end

    subgraph "Libraries"
        client["lib/client.ts<br/>API client instance"]
        api_cache["lib/api-cache.ts"]
        hooks["lib/hooks.ts"]
        kgf_highlight["lib/kgf/use-kgf-highlight.ts"]
    end

    explorer --> client
    graph --> client
    wiki --> client
    kgf_block --> kgf_highlight
    kgf_highlight --> kgf_tokenizer["cmd/kgf-tokenizer (WASM/JS)"]
```

## Key Components

### Pages

| Page | Route | Description |
|------|-------|-------------|
| `ExplorerPage` | `/` (index) | File similarity explorer with tree view, table view, and 2D graph visualization (Cytoscape). Allows browsing folders, inspecting functions, and viewing similarity pairs. |
| `GraphPage` | `/graph` | 3D dependency graph rendered with Three.js. Includes layout algorithms and interactive scene controls. |
| `WikiPage` | `/wiki/*` | Displays auto-generated wiki content with navigation sidebar, table of contents, source badges, and Markdown rendering (react-markdown + remark-gfm + rehype-slug). |
| `SettingsPage` | `/settings` | Configuration page (available in live-server mode only). |

### Routing

The router (`router.tsx`) uses `react-router` v7 with lazy-loaded pages via `React.lazy()`. It supports two route sets:
- **Full mode** (live server): all four pages
- **Static mode** (`VITE_STATIC_MODE=true`): Explorer and Wiki only (no graph/settings that require server)

### Client-Side KGF Highlighting

The `KgfCodeBlock` component and `use-kgf-highlight` hook load the `cmd/kgf-tokenizer` JS module to tokenize source code entirely in the browser, enabling syntax highlighting without server calls.

### Shared UI Components

Built with Radix UI primitives (Collapsible, Dialog, ScrollArea, Separator, Slot, ToggleGroup, Tooltip) and styled with Tailwind CSS v4. The `CommandPalette` uses the `cmdk` library for keyboard-driven navigation.

### Explorer Sub-Components

- `explorer-tree-view.tsx` / `explorer-tree-builder.ts` -- hierarchical folder/file tree
- `explorer-table-view.tsx` -- tabular similarity pair listing
- `explorer-graph-2d.tsx` -- 2D similarity graph (Cytoscape)
- `folder-item.tsx`, `file-item.tsx`, `function-detail.tsx` -- tree node renderers

## Dependencies

### Runtime

| Package | Purpose |
|---------|---------|
| `@indexion/api-client` | Typed API client (workspace dependency) |
| `react` / `react-dom` | UI framework (v19) |
| `react-router` | Client-side routing (v7) |
| `cytoscape` | 2D graph rendering |
| `three` | 3D graph rendering |
| `react-zoom-pan-pinch` | Pan/zoom for graphs |
| `mermaid` | Mermaid diagram rendering |
| `react-markdown` + `remark-gfm` + `rehype-slug` | Markdown rendering |
| `cmdk` | Command palette |
| `lucide-react` | Icons |
| Radix UI (`@radix-ui/react-*`) | Accessible UI primitives |
| `tailwind-merge` / `clsx` / `class-variance-authority` | Style utilities |

### Dev

| Package | Purpose |
|---------|---------|
| Vite + `@vitejs/plugin-react` | Build tooling |
| Tailwind CSS v4 + `@tailwindcss/vite` | Styling |
| Vitest + `@testing-library/react` | Testing |
| TypeScript | Type checking |

### Build

The Vite config (`vite.config.ts`) sets the root to `src/client`, outputs to `dist/client`, and proxies `/api` to `http://localhost:3741` during development. In static mode, the base path is set to `/indexion/` for GitHub Pages deployment.

## See Also

- [DeepWiki Frontend](wiki://deepwiki-frontend) -- user-facing guide to the web interface features

> Source: `packages/wiki/`
