/**
 * @file Command handler for `indexion.explore`.
 */

import * as vscode from "vscode";
import { resolveFileUri } from "../extension-host/resolve-file-uri.ts";
import { runExplore } from "@indexion/api-client";
import { runWithProgress } from "./progress.ts";
import { requireConfig } from "./plan-common.ts";
import type { ComparisonStrategy } from "@indexion/api-client";

/** Prompt user for explore options and run the command. */
export const executeExplore = async (): Promise<void> => {
  const resolved = requireConfig();
  if (!resolved) {
    return;
  }

  const folder = await vscode.window.showOpenDialog({
    canSelectFolders: true,
    canSelectFiles: false,
    canSelectMany: false,
    defaultUri: vscode.Uri.file(resolved.config.workspaceDir),
    openLabel: "Select directory to explore",
  });

  if (!folder || folder.length === 0) {
    return;
  }

  const strategyPick = await vscode.window.showQuickPick(["tfidf", "ncd", "hybrid", "apted", "tsed"], {
    placeHolder: "Select comparison strategy",
    title: "Comparison Strategy",
  });

  const thresholdInput = await vscode.window.showInputBox({
    prompt: "Similarity threshold (0.0-1.0)",
    value: String(resolved.config.threshold),
    validateInput: (v) => {
      const n = Number(v);
      return Number.isNaN(n) || n < 0 || n > 1 ? "Must be a number between 0.0 and 1.0" : null;
    },
  });

  if (thresholdInput === undefined) {
    return;
  }

  const result = await runWithProgress("indexion: Exploring similarity...", (token) => {
    const abortController = new AbortController();
    token.onCancellationRequested(() => abortController.abort());
    return runExplore(
      resolved.client,
      {
        targetDirs: [folder[0].fsPath],
        threshold: Number(thresholdInput),
        strategy: (strategyPick as ComparisonStrategy) ?? resolved.config.strategy,
      },
      abortController.signal,
    );
  });

  if (!result.ok) {
    vscode.window.showErrorMessage(`Explore failed: ${result.error}`);
    return;
  }

  if (result.data.pairs.length === 0) {
    vscode.window.showInformationMessage(
      `No similar files found above threshold in ${result.data.files.length} files.`,
    );
    return;
  }

  const items = result.data.pairs.map((pair) => ({
    label: `${Math.round(pair.similarity * 100)}%`,
    description: `${pair.file1} ↔ ${pair.file2}`,
    pair,
  }));

  const selected = await vscode.window.showQuickPick(items, {
    placeHolder: `${result.data.pairs.length} similar pairs found in ${result.data.files.length} files`,
    title: "Explore Results",
  });

  if (selected) {
    await vscode.commands.executeCommand(
      "vscode.diff",
      resolveFileUri(selected.pair.file1),
      resolveFileUri(selected.pair.file2),
      `${selected.pair.file1} ↔ ${selected.pair.file2}`,
    );
  }
};
