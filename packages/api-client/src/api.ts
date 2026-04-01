/**
 * @file Typed API functions — single source of truth for all endpoint calls.
 *
 * Both the wiki frontend and the vscode-plugin consume these functions.
 * No consumer should construct endpoint URLs directly.
 */

import type { HttpClient } from "./client.ts";
import type {
  ApiResponse,
  CodeGraph,
  DigestMatch,
  ServerConfig,
  ExploreResult,
  IndexedFunction,
  KgfEdge,
  KgfSpecInfo,
  KgfToken,
  WikiNav,
  WikiPage,
} from "./types.ts";

// --- Graph ---

export const fetchGraph = (
  client: HttpClient,
  signal?: AbortSignal,
): Promise<ApiResponse<CodeGraph>> => client.get<CodeGraph>("/graph", signal);

// --- Digest ---

export const queryDigest = (
  client: HttpClient,
  body: {
    readonly purpose: string;
    readonly topK?: number;
    readonly minScore?: number;
  },
  signal?: AbortSignal,
): Promise<ApiResponse<ReadonlyArray<DigestMatch>>> =>
  client.post<ReadonlyArray<DigestMatch>>("/digest/query", body, signal);

export const fetchDigestIndex = (
  client: HttpClient,
  signal?: AbortSignal,
): Promise<ApiResponse<ReadonlyArray<IndexedFunction>>> =>
  client.get<ReadonlyArray<IndexedFunction>>("/digest/index", signal);

export const fetchDigestStats = <T = unknown>(
  client: HttpClient,
  signal?: AbortSignal,
): Promise<ApiResponse<T>> => client.get<T>("/digest/stats", signal);

export const rebuildDigest = (
  client: HttpClient,
  signal?: AbortSignal,
): Promise<
  ApiResponse<{ readonly rebuilt: boolean; readonly functions: number }>
> =>
  client.post<{ readonly rebuilt: boolean; readonly functions: number }>(
    "/digest/rebuild",
    {},
    signal,
  );

// --- Wiki ---

export const fetchWikiNav = (
  client: HttpClient,
  signal?: AbortSignal,
): Promise<ApiResponse<WikiNav>> => client.get<WikiNav>("/wiki/nav", signal);

export const fetchWikiPage = (
  client: HttpClient,
  pageId: string,
  signal?: AbortSignal,
): Promise<ApiResponse<WikiPage>> =>
  client.get<WikiPage>(`/wiki/pages/${pageId}`, signal);

export const searchWiki = (
  client: HttpClient,
  body: { readonly query: string; readonly topK?: number },
  signal?: AbortSignal,
): Promise<ApiResponse<ReadonlyArray<unknown>>> =>
  client.post<ReadonlyArray<unknown>>("/wiki/search", body, signal);

// --- Explore ---

export type ExploreRequest = {
  readonly targetDirs: ReadonlyArray<string>;
  readonly threshold?: number;
  readonly strategy?: string;
  readonly includes?: ReadonlyArray<string>;
  readonly excludes?: ReadonlyArray<string>;
};

export const runExplore = (
  client: HttpClient,
  body: ExploreRequest,
  signal?: AbortSignal,
): Promise<ApiResponse<ExploreResult>> =>
  client.post<ExploreResult>("/explore", body, signal);

// --- KGF ---

export const fetchKgfList = (
  client: HttpClient,
  signal?: AbortSignal,
): Promise<ApiResponse<ReadonlyArray<KgfSpecInfo>>> =>
  client.get<ReadonlyArray<KgfSpecInfo>>("/kgf/list", signal);

export const tokenizeFile = (
  client: HttpClient,
  body: { readonly file: string; readonly spec?: string },
  signal?: AbortSignal,
): Promise<ApiResponse<ReadonlyArray<KgfToken>>> =>
  client.post<ReadonlyArray<KgfToken>>("/kgf/tokens", body, signal);

export const extractEdges = (
  client: HttpClient,
  body: { readonly file: string; readonly spec?: string },
  signal?: AbortSignal,
): Promise<ApiResponse<ReadonlyArray<KgfEdge>>> =>
  client.post<ReadonlyArray<KgfEdge>>("/kgf/edges", body, signal);

// --- Doc ---

export type DocGraphRequest = {
  readonly inputPaths: ReadonlyArray<string>;
  readonly format?: string;
  readonly title?: string;
};

export const generateDocGraph = (
  client: HttpClient,
  body: DocGraphRequest,
  signal?: AbortSignal,
): Promise<ApiResponse<string>> =>
  client.post<string>("/doc/graph", body, signal);

// --- Plan ---

export type PlanRequest = {
  readonly targetDir: string;
  readonly threshold?: number;
  readonly strategy?: string;
  readonly format?: string;
  readonly includes?: ReadonlyArray<string>;
  readonly excludes?: ReadonlyArray<string>;
  readonly [key: string]: unknown;
};

export const runPlanRefactor = (
  client: HttpClient,
  body: PlanRequest,
  signal?: AbortSignal,
): Promise<ApiResponse<string>> =>
  client.post<string>("/plan/refactor", body, signal);

export const runPlanDocumentation = (
  client: HttpClient,
  body: PlanRequest,
  signal?: AbortSignal,
): Promise<ApiResponse<string>> =>
  client.post<string>("/plan/documentation", body, signal);

export const runPlanReconcile = (
  client: HttpClient,
  body: PlanRequest,
  signal?: AbortSignal,
): Promise<ApiResponse<string>> =>
  client.post<string>("/plan/reconcile", body, signal);

export const runPlanSolid = (
  client: HttpClient,
  body: PlanRequest & {
    readonly fromDirs: ReadonlyArray<string>;
    readonly toDir?: string;
  },
  signal?: AbortSignal,
): Promise<ApiResponse<string>> =>
  client.post<string>("/plan/solid", body, signal);

export const runPlanUnwrap = (
  client: HttpClient,
  body: PlanRequest,
  signal?: AbortSignal,
): Promise<ApiResponse<string>> =>
  client.post<string>("/plan/unwrap", body, signal);

export const runPlanReadme = (
  client: HttpClient,
  body: PlanRequest & { readonly template: string; readonly plansDir?: string },
  signal?: AbortSignal,
): Promise<ApiResponse<string>> =>
  client.post<string>("/plan/readme", body, signal);

// --- Health ---

export const checkHealth = (
  client: HttpClient,
  signal?: AbortSignal,
): Promise<ApiResponse<{ readonly status: string }>> =>
  client.get<{ readonly status: string }>("/health", signal);

// --- Config (readonly) ---

export const fetchConfig = (
  client: HttpClient,
  signal?: AbortSignal,
): Promise<ApiResponse<ServerConfig>> =>
  client.get<ServerConfig>("/config", signal);
