import { lazy, Suspense } from "react";
import { createBrowserRouter } from "react-router";
import { AppLayout } from "./components/layout/app-layout.tsx";
import { LoadingSpinner } from "./components/shared/loading-spinner.tsx";
import { isStaticMode } from "./lib/client.ts";

const ExplorerPage = lazy(() =>
  import("./pages/explorer/explorer-page.tsx").then((m) => ({
    default: m.ExplorerPage,
  })),
);

const GraphPage = lazy(() =>
  import("./pages/graph/graph-page.tsx").then((m) => ({
    default: m.GraphPage,
  })),
);

const WikiPage = lazy(() =>
  import("./pages/wiki/wiki-page.tsx").then((m) => ({ default: m.WikiPage })),
);

const SettingsPage = lazy(() =>
  import("./pages/settings/settings-page.tsx").then((m) => ({
    default: m.SettingsPage,
  })),
);

const fullRoutes = [
  {
    index: true,
    element: (
      <Suspense fallback={<LoadingSpinner message="Loading..." />}>
        <ExplorerPage />
      </Suspense>
    ),
  },
  {
    path: "graph",
    element: (
      <Suspense fallback={<LoadingSpinner message="Loading 3D graph..." />}>
        <GraphPage />
      </Suspense>
    ),
  },
  {
    path: "wiki/*",
    element: (
      <Suspense fallback={<LoadingSpinner message="Loading wiki..." />}>
        <WikiPage />
      </Suspense>
    ),
  },
  {
    path: "settings",
    element: (
      <Suspense fallback={<LoadingSpinner />}>
        <SettingsPage />
      </Suspense>
    ),
  },
];

const staticRoutes = [
  {
    index: true,
    element: (
      <Suspense fallback={<LoadingSpinner message="Loading..." />}>
        <ExplorerPage />
      </Suspense>
    ),
  },
  {
    path: "wiki/*",
    element: (
      <Suspense fallback={<LoadingSpinner message="Loading wiki..." />}>
        <WikiPage />
      </Suspense>
    ),
  },
];

export const router = createBrowserRouter([
  {
    element: <AppLayout />,
    children: isStaticMode ? staticRoutes : fullRoutes,
  },
]);
