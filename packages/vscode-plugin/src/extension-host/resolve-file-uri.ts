/**
 * @file Resolve file paths to workspace-relative URIs.
 *
 * The indexion server returns relative file paths (e.g. "cmd/indexion/explore/cli.mbt").
 * VSCode's Uri.file() expects absolute paths. This utility resolves relative paths
 * against the first workspace folder.
 */

import * as vscode from "vscode";

/** Resolve a file path that may be relative to the workspace root. */
export const resolveFileUri = (filePath: string): vscode.Uri => {
  if (filePath.startsWith("/")) {
    return vscode.Uri.file(filePath);
  }
  const wsFolder = vscode.workspace.workspaceFolders?.[0];
  if (wsFolder) {
    return vscode.Uri.joinPath(wsFolder.uri, filePath);
  }
  return vscode.Uri.file(filePath);
};
