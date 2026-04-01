/**
 * @file Re-export React hooks from @indexion/api-client + app-level cached variant.
 */

import { useState, useEffect, useSyncExternalStore } from "react";
import type { ApiResponse } from "@indexion/api-client";
import {
  cachedFetch,
  getCacheVersion,
  subscribe,
  type CacheKeyValue,
} from "./api-cache.ts";

export type { ApiState } from "@indexion/api-client/react";
export { useApiCall, useApiMutationCall } from "@indexion/api-client/react";

type CachedState<T> =
  | { readonly status: "loading" }
  | { readonly status: "success"; readonly data: T }
  | { readonly status: "error"; readonly error: string };

/**
 * Like useApiCall but backed by the app-level cache.
 * Same key → same data across all components and page navigations.
 * Automatically re-fetches when the cache is invalidated (e.g. after rebuild).
 */
export const useCachedApiCall = <T>(
  key: CacheKeyValue,
  fetch: () => Promise<ApiResponse<T>>,
): CachedState<T> => {
  const [state, setState] = useState<CachedState<T>>({ status: "loading" });
  const cacheVersion = useSyncExternalStore(subscribe, getCacheVersion);

  useEffect(() => {
    let cancelled = false;
    setState({ status: "loading" });
    cachedFetch(key, fetch).then((result) => {
      if (cancelled) {
        return;
      }
      if (result.ok) {
        setState({ status: "success", data: result.data });
      } else {
        setState({ status: "error", error: result.error });
      }
    });
    return () => {
      cancelled = true;
    };
  }, [key, cacheVersion]);

  return state;
};
