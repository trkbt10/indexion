/**
 * @file Command handler for `indexion.grep`.
 */

import * as vscode from "vscode";
import { runGrep } from "@indexion/api-client";
import { runWithProgress } from "./progress.ts";
import { requireConfig } from "./plan-common.ts";

/** Execute KGF-aware grep command. */
export const executeGrep = async (): Promise<void> => {
  const resolved = requireConfig();
  if (!resolved) {
    return;
  }

  const pattern = await vscode.window.showInputBox({
    prompt: "KGF token pattern (e.g., 'pub fn Ident') or leave empty for --undocumented",
    placeHolder: "e.g., KW_pub KW_fn Ident, or pub fn ...",
  });

  if (pattern === undefined) {
    return; // cancelled
  }

  const body = pattern.length > 0 ? { pattern } : { undocumented: true };

  const result = await runWithProgress("indexion: Grep searching...", (token) => {
    const abortController = new AbortController();
    token.onCancellationRequested(() => abortController.abort());
    return runGrep(resolved.client, body, abortController.signal);
  });

  if (!result.ok) {
    vscode.window.showErrorMessage(`Grep failed: ${result.error}`);
    return;
  }

  if (result.data.length === 0) {
    vscode.window.showInformationMessage("No matches found.");
    return;
  }

  const items = result.data.map((match) => ({
    label: match.name ?? match.matched ?? "(match)",
    description: `${match.file}:${match.line}`,
    detail: match.detail ?? match.kind,
    match,
  }));

  const selected = await vscode.window.showQuickPick(items, {
    placeHolder: `${result.data.length} matches found`,
    title: "Grep Results",
  });

  if (selected) {
    const uri = vscode.Uri.file(selected.match.file);
    const doc = await vscode.workspace.openTextDocument(uri);
    const line = Math.max(0, selected.match.line - 1);
    await vscode.window.showTextDocument(doc, {
      selection: new vscode.Range(line, 0, line, 0),
    });
  }
};
