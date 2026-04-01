/**
 * @file Application-level API response cache with domain-scoped invalidation.
 *
 * Cache keys are organized by domain. Each domain defines its keys
 * and can be invalidated as a unit.
 */

import type { ApiResponse } from "@indexion/api-client";

// ── Domains and keys (SoT) ──

const Digest = {
  graph: "digest:graph",
  index: "digest:index",
  stats: "digest:stats",
} as const;
const Wiki = { nav: "wiki:nav" } as const;
const Server = { config: "server:config" } as const;

/** Cache key registry. Usage: `CacheKey.digest.graph`, `CacheKey.wiki.nav` */
export const CacheKey = { digest: Digest, wiki: Wiki, server: Server } as const;

type ValuesOf<T> = T[keyof T];
type AllKeys =
  | ValuesOf<typeof Digest>
  | ValuesOf<typeof Wiki>
  | ValuesOf<typeof Server>;
export type CacheKeyValue = AllKeys;

/** Invalidation scopes. `invalidateScope("digest")` clears all digest keys. */
const SCOPES: Record<string, ReadonlyArray<CacheKeyValue>> = {
  digest: Object.values(Digest),
  wiki: Object.values(Wiki),
  server: Object.values(Server),
};

// ── Cache internals ──

type CacheEntry<T> = {
  promise: Promise<ApiResponse<T>>;
  result: ApiResponse<T> | null;
};

const cache = new Map<string, CacheEntry<unknown>>();
const listeners = new Set<() => void>();
let version = 0;

const notify = () => {
  version++;
  for (const fn of listeners) {
    fn();
  }
};

// ── Public API ──

/** Fetch with deduplication and caching. */
export const cachedFetch = <T>(
  key: CacheKeyValue,
  fetch: () => Promise<ApiResponse<T>>,
): Promise<ApiResponse<T>> => {
  const existing = cache.get(key) as CacheEntry<T> | undefined;
  if (existing) {
    return existing.promise;
  }

  const promise = fetch().then((result) => {
    const entry = cache.get(key) as CacheEntry<T> | undefined;
    if (entry) {
      entry.result = result;
    }
    return result;
  });

  cache.set(key, {
    promise: promise as Promise<ApiResponse<unknown>>,
    result: null,
  });
  return promise;
};

/** Invalidate a named scope (e.g. "digest", "wiki"). */
export const invalidateScope = (scope: keyof typeof SCOPES): void => {
  for (const key of SCOPES[scope]) {
    cache.delete(key);
  }
  notify();
};

/** Invalidate specific keys. */
export const invalidate = (...keys: CacheKeyValue[]): void => {
  for (const key of keys) {
    cache.delete(key);
  }
  notify();
};

/** Current cache version. Changes on every invalidation. */
export const getCacheVersion = (): number => version;

/** Subscribe to invalidation events. Returns unsubscribe. */
export const subscribe = (fn: () => void): (() => void) => {
  listeners.add(fn);
  return () => {
    listeners.delete(fn);
  };
};
