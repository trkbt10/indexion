/**
 * @file Indexion serve process lifecycle manager.
 *
 * Manages a single `indexion serve` child process — the ONLY subprocess
 * spawned by the extension. All other operations use the HTTP API.
 *
 * Lifecycle:
 * - start() spawns the process, polls /api/health until ready
 * - If the process dies unexpectedly, it is automatically restarted
 * - stop() sends SIGTERM, falls back to SIGKILL after 5s
 * - Multiple concurrent start() calls are prevented by a starting guard
 */

import { spawn, execSync, type ChildProcess } from "node:child_process";
import { existsSync } from "node:fs";
import { createServer } from "node:net";
import { resolve } from "node:path";
import * as vscode from "vscode";
import { createHttpClient, type HttpClient } from "@indexion/api-client";

/** Find a free TCP port by briefly binding to port 0. */
const findFreePort = (): Promise<number> =>
  new Promise((ok, fail) => {
    const srv = createServer();
    srv.listen(0, "127.0.0.1", () => {
      const addr = srv.address();
      if (addr && typeof addr === "object") {
        const { port } = addr;
        srv.close(() => ok(port));
      } else {
        srv.close(() => fail(new Error("Failed to get port")));
      }
    });
    srv.on("error", fail);
  });

/** Configuration for the server manager. */
export type ServerConfig = {
  readonly binaryPath: string;
  readonly workspaceDir: string;
  readonly specsDir: string;
  readonly port: number;
};

/** Local build binary path relative to workspace root (MoonBit native target). */
const LOCAL_BUILD_BINARY = "_build/native/debug/build/cmd/indexion/indexion.exe";

/** Resolved binary information. */
type ResolvedBinary = {
  readonly binary: string;
  readonly prefixArgs: ReadonlyArray<string>;
};

/**
 * Resolve the indexion binary path.
 *
 * Priority:
 * 1. Explicit path from settings (binaryPath)
 * 2. Local build in workspace (_build/native/debug/...)
 * 3. Global `indexion` on PATH
 * 4. `moon run` fallback
 */
const resolveBinary = (binaryPath: string, workspaceDir: string): ResolvedBinary => {
  if (binaryPath) {
    return { binary: binaryPath, prefixArgs: [] };
  }
  const localBinary = resolve(workspaceDir, LOCAL_BUILD_BINARY);
  if (existsSync(localBinary)) {
    return { binary: localBinary, prefixArgs: [] };
  }
  try {
    execSync("which indexion", { stdio: "ignore" });
    return { binary: "indexion", prefixArgs: [] };
  } catch {
    /* indexion not on PATH */
  }
  try {
    execSync("which moon", { stdio: "ignore" });
    return { binary: "moon", prefixArgs: ["run", "cmd/indexion", "--target", "native", "--"] };
  } catch {
    /* moon not on PATH */
  }
  return { binary: "indexion", prefixArgs: [] };
};

/** Format an unknown caught value as a string. */
const formatError = (err: unknown): string => (err instanceof Error ? err.message : String(err));

/** Health poll options. */
type PollOptions = {
  readonly baseUrl: string;
  readonly shouldAbort: () => boolean;
  readonly log: vscode.OutputChannel;
};

/** Poll /api/health until the server responds OK. Returns true if healthy. */
const pollHealth = async (options: PollOptions): Promise<boolean> => {
  const maxAttempts = 120;
  const intervalMs = 500;
  for (let i = 0; i < maxAttempts; i++) {
    if (options.shouldAbort()) {
      options.log.appendLine("[server] process gone or stopped, aborting poll");
      return false;
    }
    const result = await fetchHealthOnce(options.baseUrl);
    if (result.healthy) {
      options.log.appendLine(`[server] healthy after ${i + 1} attempts (${(i + 1) * intervalMs}ms)`);
      return true;
    }
    if (result.status !== undefined) {
      options.log.appendLine(`[server] health returned ${result.status}, retrying...`);
    } else if (i % 10 === 0) {
      options.log.appendLine(`[server] poll attempt ${i + 1}: ${result.error ?? "connection refused"}`);
    }
    await new Promise((r) => setTimeout(r, intervalMs));
  }
  options.log.appendLine(`[server] health poll timed out after ${maxAttempts * intervalMs}ms`);
  return false;
};

/** Single health check attempt result. */
type HealthResult =
  | { readonly healthy: true; readonly status?: undefined; readonly error?: undefined }
  | { readonly healthy: false; readonly status?: number; readonly error?: string };

/** Attempt a single health check. Never throws. */
const fetchHealthOnce = async (baseUrl: string): Promise<HealthResult> => {
  try {
    const res = await fetch(`${baseUrl}/health`);
    if (res.ok) {
      return { healthy: true };
    }
    return { healthy: false, status: res.status };
  } catch (err) {
    return { healthy: false, error: formatError(err) };
  }
};

/** Public interface for managing the serve process. */
export type ServerManager = {
  readonly start: () => Promise<void>;
  readonly stop: () => void;
  readonly getClient: () => HttpClient | undefined;
  readonly getBaseUrl: () => string | undefined;
  readonly isReady: () => boolean;
  readonly onReady: vscode.Event<void>;
  readonly onDown: vscode.Event<void>;
};

/** Mutable lifecycle state for the server process. */
type ServerState = {
  proc: ChildProcess | undefined;
  client: HttpClient | undefined;
  baseUrl: string | undefined;
  ready: boolean;
  starting: boolean;
  stopped: boolean;
};

/** Create a server lifecycle manager. */
export const createServerManager = (config: ServerConfig, log: vscode.OutputChannel): ServerManager => {
  const resolved = resolveBinary(config.binaryPath, config.workspaceDir);
  const s: ServerState = {
    proc: undefined,
    client: undefined,
    baseUrl: undefined,
    ready: false,
    starting: false,
    stopped: false,
  };
  const readyEmitter = new vscode.EventEmitter<void>();
  const downEmitter = new vscode.EventEmitter<void>();

  const start = async (): Promise<void> => {
    if (s.starting) {
      log.appendLine("[server] start() already in progress, skipping");
      return;
    }
    if (s.stopped) {
      log.appendLine("[server] stopped, not restarting");
      return;
    }
    s.starting = true;

    try {
      const port = config.port || (await findFreePort());
      const baseUrl = `http://127.0.0.1:${port}/api`;

      const args = [
        ...resolved.prefixArgs,
        "serve",
        "--cors",
        `--port=${port}`,
        `--specs=${config.specsDir}`,
        config.workspaceDir,
      ];

      log.appendLine(`[server] binary: ${resolved.binary} ${args.join(" ")}`);
      log.appendLine(`[server] polling ${baseUrl}/health ...`);

      s.proc = spawn(resolved.binary, args, {
        cwd: config.workspaceDir,
        stdio: ["ignore", "pipe", "pipe"],
      });

      s.proc.stdout?.on("data", (chunk: Buffer) => {
        log.appendLine(`[server stdout] ${chunk.toString("utf-8").trimEnd()}`);
      });

      s.proc.stderr?.on("data", (chunk: Buffer) => {
        log.appendLine(`[server stderr] ${chunk.toString("utf-8").trimEnd()}`);
      });

      s.proc.on("error", (err) => {
        log.appendLine(`[server] spawn error: ${err.message}`);
        vscode.window.showErrorMessage(`indexion serve failed to start: ${err.message}`);
      });

      s.proc.on("close", (code) => {
        log.appendLine(`[server] process exited with code ${code}`);
        const wasReady = s.ready;
        s.ready = false;
        s.client = undefined;
        s.baseUrl = undefined;
        s.proc = undefined;
        s.starting = false;
        if (wasReady) {
          downEmitter.fire();
        }
        if (!s.stopped && wasReady) {
          log.appendLine("[server] unexpected exit, restarting in 2s...");
          setTimeout(() => {
            start().catch((err) => {
              log.appendLine(`[server] restart failed: ${formatError(err)}`);
            });
          }, 2000);
        }
      });

      const healthy = await pollHealth({
        baseUrl,
        shouldAbort: () => !s.proc || s.stopped,
        log,
      });
      if (healthy) {
        s.client = createHttpClient(baseUrl);
        s.baseUrl = baseUrl;
        s.ready = true;
        readyEmitter.fire();
      }
    } finally {
      s.starting = false;
    }
  };

  const stop = (): void => {
    s.stopped = true;
    const p = s.proc;
    s.proc = undefined;
    s.client = undefined;
    s.baseUrl = undefined;
    s.ready = false;
    if (!p) {
      return;
    }
    log.appendLine("[server] stopping...");
    p.kill("SIGTERM");
    const forceKillTimer = setTimeout(() => {
      if (!p.killed) {
        log.appendLine("[server] SIGTERM timed out, sending SIGKILL");
        p.kill("SIGKILL");
      }
    }, 5000);
    p.on("close", () => clearTimeout(forceKillTimer));
  };

  return {
    start,
    stop,
    getClient: () => s.client,
    getBaseUrl: () => s.baseUrl,
    isReady: () => s.ready,
    onReady: readyEmitter.event,
    onDown: downEmitter.event,
  };
};
