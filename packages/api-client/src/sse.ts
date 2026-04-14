/**
 * @file SSE (Server-Sent Events) streaming client for indexion serve.
 *
 * Consumes `text/event-stream` responses from `/api/.../stream` endpoints.
 * Each SSE event line is `data: {json}\n\n`.
 *
 * Uses an async generator internally so the consumer drives the pace.
 * Every YIELD_BATCH_SIZE events, the generator yields to the event loop
 * to prevent blocking other extension host tasks.
 */

/** SSE event types emitted by the server. */
export type SseEvent =
  | {
      readonly type: "progress";
      readonly phase: string;
      readonly detail: string;
    }
  | { readonly type: "item"; readonly data: unknown }
  | { readonly type: "items"; readonly data: ReadonlyArray<unknown> }
  | { readonly type: "result"; readonly data: unknown }
  | { readonly type: "done"; readonly total: number }
  | { readonly type: "error"; readonly message: string };

/** Options for streaming POST request. */
export type StreamPostOptions = {
  readonly body: unknown;
  readonly signal?: AbortSignal;
  readonly onEvent: (event: SseEvent) => void;
};

/** Yield to the event loop. */
const yieldTick = (): Promise<void> => new Promise((r) => setTimeout(r, 0));

/** Max events to emit before yielding to avoid blocking the event loop. */
const YIELD_BATCH_SIZE = 50;

/**
 * Async generator that reads an SSE stream and yields parsed events.
 *
 * Yields to the event loop every YIELD_BATCH_SIZE events to prevent
 * monopolising the extension host when the server sends thousands of results.
 */
async function* readSseStream(reader: ReadableStreamDefaultReader<Uint8Array>): AsyncGenerator<SseEvent> {
  const decoder = new TextDecoder();
  const state = { buffer: "", count: 0 };

  for (;;) {
    const { done, value } = await reader.read();
    if (done) {
      break;
    }

    state.buffer += decoder.decode(value, { stream: true });

    for (;;) {
      const boundary = state.buffer.indexOf("\n\n");
      if (boundary === -1) {
        break;
      }

      const chunk = state.buffer.slice(0, boundary);
      state.buffer = state.buffer.slice(boundary + 2);

      for (const line of chunk.split("\n")) {
        if (line.startsWith("data: ")) {
          try {
            yield JSON.parse(line.slice(6)) as SseEvent;
          } catch {
            // Skip malformed JSON — partial writes from the server
          }
          state.count++;
          if (state.count >= YIELD_BATCH_SIZE) {
            state.count = 0;
            await yieldTick();
          }
        }
      }
    }
  }
}

/**
 * POST to a streaming SSE endpoint and invoke onEvent for each parsed event.
 *
 * @param baseUrl  The base URL for the API (e.g. "http://127.0.0.1:3741/api").
 * @param path     The endpoint path (e.g. "/search/stream").
 * @param options  Request body, abort signal, and event callback.
 */
export const postStream = async (
  baseUrl: string,
  path: string,
  options: StreamPostOptions,
): Promise<void> => {
  const res = await fetch(`${baseUrl}${path}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(options.body),
    signal: options.signal,
  });

  if (!res.ok) {
    options.onEvent({
      type: "error",
      message: `HTTP ${res.status}: ${res.statusText}`,
    });
    return;
  }

  const reader = res.body?.getReader();
  if (!reader) {
    options.onEvent({ type: "error", message: "No response body" });
    return;
  }

  for await (const event of readSseStream(reader)) {
    options.onEvent(event);
  }
};
