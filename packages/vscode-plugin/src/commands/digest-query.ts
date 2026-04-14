/**
 * @file Command handler for `indexion.digestQuery`.
 */

import * as vscode from "vscode";
import { resolveFileUri } from "../extension-host/resolve-file-uri.ts";
import { queryDigest } from "@indexion/api-client";
import { runWithProgress } from "./progress.ts";
import { requireConfig } from "./plan-common.ts";

/** Execute digest query command. */
export const executeDigestQuery = async (): Promise<void> => {
  const resolved = requireConfig();
  if (!resolved) {
    return;
  }

  const purpose = await vscode.window.showInputBox({
    prompt: "Search functions by purpose (natural language)",
    placeHolder: "e.g., parse JSON configuration",
  });

  if (!purpose) {
    return;
  }

  const result = await runWithProgress("indexion: Searching by purpose...", (token) => {
    const abortController = new AbortController();
    token.onCancellationRequested(() => abortController.abort());
    return queryDigest(resolved.client, { purpose, topK: 10 }, abortController.signal);
  });

  if (!result.ok) {
    vscode.window.showErrorMessage(`Digest query failed: ${result.error}`);
    return;
  }

  if (result.data.length === 0) {
    vscode.window.showInformationMessage("No matching functions found.");
    return;
  }

  const items = result.data.map((match) => ({
    label: match.name,
    description: `${Math.round(match.score * 100)}% — ${match.file}`,
    detail: match.summary,
    match,
  }));

  const selected = await vscode.window.showQuickPick(items, {
    placeHolder: `${result.data.length} functions found`,
    title: "Digest Query Results",
  });

  if (selected) {
    const doc = await vscode.workspace.openTextDocument(resolveFileUri(selected.match.file));
    await vscode.window.showTextDocument(doc);
  }
};
