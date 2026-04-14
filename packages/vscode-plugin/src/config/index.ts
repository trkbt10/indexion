/**
 * @file Extension configuration.
 *
 * Server startup config (binaryPath, port) comes from VSCode settings.
 * Runtime config (workspaceDir, specsDir, paths) comes from `GET /api/config`
 * on the running serve instance — the MoonBit side is the SoT.
 */

import * as vscode from "vscode";
import type { ComparisonStrategy } from "@indexion/api-client";

/** VSCode extension settings (from contributes.configuration). */
export type ExtensionSettings = {
  readonly binaryPath: string;
  readonly specsDir: string;
  readonly defaultThreshold: number;
  readonly defaultStrategy: ComparisonStrategy;
};

/** Read VSCode extension settings. */
export const getExtensionSettings = (): ExtensionSettings => {
  const config = vscode.workspace.getConfiguration("indexion");
  return {
    binaryPath: config.get<string>("binaryPath", ""),
    specsDir: config.get<string>("specsDir", "kgfs"),
    defaultThreshold: config.get<number>("defaultThreshold", 0.7),
    defaultStrategy: config.get<string>("defaultStrategy", "hybrid") as ComparisonStrategy,
  };
};

/** Get the current workspace root directory. */
export const getWorkspaceDir = (): string | undefined => vscode.workspace.workspaceFolders?.[0]?.uri.fsPath;

/** Minimal resolved config needed to start the server and run commands. */
export type ResolvedConfig = {
  readonly binaryPath: string;
  readonly specsDir: string;
  readonly threshold: number;
  readonly strategy: ComparisonStrategy;
  readonly workspaceDir: string;
};

/** Resolve config from VSCode settings + workspace. */
export const resolveConfig = (): ResolvedConfig | undefined => {
  const workspaceDir = getWorkspaceDir();
  if (!workspaceDir) {
    return undefined;
  }
  const settings = getExtensionSettings();
  return {
    binaryPath: settings.binaryPath,
    specsDir: settings.specsDir,
    threshold: settings.defaultThreshold,
    strategy: settings.defaultStrategy,
    workspaceDir,
  };
};
