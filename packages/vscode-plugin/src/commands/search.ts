/**
 * @file Command handler for `indexion.search`.
 */

import * as vscode from "vscode";
import { resolveFileUri } from "../extension-host/resolve-file-uri.ts";
import { runSearch } from "@indexion/api-client";
import { runWithProgress } from "./progress.ts";
import { requireConfig } from "./plan-common.ts";

/** Execute semantic search command. */
export const executeSearch = async (): Promise<void> => {
  const resolved = requireConfig();
  if (!resolved) {
    return;
  }

  const query = await vscode.window.showInputBox({
    prompt: "Semantic search across code, wiki, and documentation",
    placeHolder: "e.g., error handling, parser configuration",
  });

  if (!query) {
    return;
  }

  const result = await runWithProgress("indexion: Searching...", (token) => {
    const abortController = new AbortController();
    token.onCancellationRequested(() => abortController.abort());
    return runSearch(resolved.client, { query, topK: 20 }, abortController.signal);
  });

  if (!result.ok) {
    vscode.window.showErrorMessage(`Search failed: ${result.error}`);
    return;
  }

  if (result.data.length === 0) {
    vscode.window.showInformationMessage("No results found.");
    return;
  }

  const items = result.data.map((hit) => ({
    label: hit.title,
    description: `${Math.round(hit.score * 100)}% — ${hit.source}${hit.line > 0 ? `:${hit.line}` : ""}`,
    detail: hit.kind,
    hit,
  }));

  const selected = await vscode.window.showQuickPick(items, {
    placeHolder: `${result.data.length} results found`,
    title: "Search Results",
  });

  if (selected) {
    const uri = resolveFileUri(selected.hit.source);
    const doc = await vscode.workspace.openTextDocument(uri);
    const line = Math.max(0, selected.hit.line - 1);
    await vscode.window.showTextDocument(doc, {
      selection: new vscode.Range(line, 0, line, 0),
    });
  }
};
