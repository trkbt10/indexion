/**
 * @file HTTP client for indexion serve API.
 *
 * Provides both a factory (for dynamic base URL) and bare functions
 * (for fixed base URL contexts like browser SPAs).
 */

import type { ApiResponse } from "./types.ts";

/** HTTP client bound to a base URL. */
export type HttpClient = {
  readonly get: <T>(
    path: string,
    signal?: AbortSignal,
  ) => Promise<ApiResponse<T>>;
  readonly post: <T>(
    path: string,
    body: unknown,
    signal?: AbortSignal,
  ) => Promise<ApiResponse<T>>;
};

/** GET request. */
const doGet = async <T>(
  baseUrl: string,
  path: string,
  signal?: AbortSignal,
): Promise<ApiResponse<T>> => {
  try {
    const res = await fetch(`${baseUrl}${path}`, { signal });
    return (await res.json()) as ApiResponse<T>;
  } catch (err) {
    if (err instanceof DOMException && err.name === "AbortError") {
      return { ok: false, error: "Request aborted" };
    }
    return {
      ok: false,
      error: err instanceof Error ? err.message : "Unknown error",
    };
  }
};

/** POST request. */
const doPost = async <T>(
  baseUrl: string,
  path: string,
  opts: { readonly body: unknown; readonly signal?: AbortSignal },
): Promise<ApiResponse<T>> => {
  try {
    const res = await fetch(`${baseUrl}${path}`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(opts.body),
      signal: opts.signal,
    });
    return (await res.json()) as ApiResponse<T>;
  } catch (err) {
    if (err instanceof DOMException && err.name === "AbortError") {
      return { ok: false, error: "Request aborted" };
    }
    return {
      ok: false,
      error: err instanceof Error ? err.message : "Unknown error",
    };
  }
};

/** Create an HTTP client bound to a specific base URL. */
export const createHttpClient = (baseUrl: string): HttpClient => ({
  get: <T>(path: string, signal?: AbortSignal) =>
    doGet<T>(baseUrl, path, signal),
  post: <T>(path: string, body: unknown, signal?: AbortSignal) =>
    doPost<T>(baseUrl, path, { body, signal }),
});

/**
 * Bare GET for fixed-base-URL contexts (e.g. browser SPA behind a proxy).
 * Uses `/api` as default base.
 */
export const apiGet = async <T>(
  path: string,
  signal?: AbortSignal,
): Promise<ApiResponse<T>> => doGet<T>("/api", path, signal);

/**
 * Bare POST for fixed-base-URL contexts.
 * Uses `/api` as default base.
 */
export const apiPost = async <T>(
  path: string,
  body: unknown,
  signal?: AbortSignal,
): Promise<ApiResponse<T>> => doPost<T>("/api", path, { body, signal });
