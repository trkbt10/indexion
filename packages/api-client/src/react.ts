/**
 * @file React hooks for @indexion/api-client.
 *
 * Generic hooks that accept typed api-client functions, so that
 * endpoint URLs are never hard-coded in page components.
 */

import {
  useState,
  useEffect,
  useEffectEvent,
  useCallback,
  useRef,
} from "react";
import type { ApiResponse } from "./types.ts";

export type ApiState<T> =
  | { readonly status: "idle" }
  | { readonly status: "loading" }
  | { readonly status: "success"; readonly data: T }
  | { readonly status: "error"; readonly error: string };

/**
 * Fetch data via a typed api-client function.
 *
 * @param call - `(signal) => Promise<ApiResponse<T>>`, or `null` to skip.
 * @param deps - Re-fetches whenever any value in `deps` changes.
 *               Defaults to `[]` (fetch once on mount).
 */
export const useApiCall = <T>(
  call: ((signal: AbortSignal) => Promise<ApiResponse<T>>) | null,
  deps: readonly unknown[] = [],
): ApiState<T> => {
  const [state, setState] = useState<ApiState<T>>({ status: "idle" });

  const onCall = useEffectEvent((signal: AbortSignal) => {
    if (!call) {
      setState({ status: "idle" });
      return;
    }
    setState({ status: "loading" });
    call(signal).then((result) => {
      if (signal.aborted) {
        return;
      }
      if (result.ok) {
        setState({ status: "success", data: result.data });
      } else {
        setState({ status: "error", error: result.error });
      }
    });
  });

  useEffect(() => {
    const controller = new AbortController();
    onCall(controller.signal);
    return () => {
      controller.abort();
    };
  }, deps);

  return state;
};

/**
 * Mutation hook that accepts a typed api-client function.
 *
 * Unlike `useApiCall`, the request is triggered imperatively via `mutate()`.
 */
export const useApiMutationCall = <T>(): {
  state: ApiState<T>;
  mutate: (call: () => Promise<ApiResponse<T>>) => Promise<void>;
} => {
  const [state, setState] = useState<ApiState<T>>({ status: "idle" });
  const activeRef = useRef(0);

  const mutate = useCallback(async (call: () => Promise<ApiResponse<T>>) => {
    const id = ++activeRef.current;
    setState({ status: "loading" });
    const result = await call();
    if (activeRef.current !== id) {
      return;
    }
    if (result.ok) {
      setState({ status: "success", data: result.data });
    } else {
      setState({ status: "error", error: result.error });
    }
  }, []);

  return { state, mutate };
};
