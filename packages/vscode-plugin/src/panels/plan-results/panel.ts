/**
 * @file WebviewPanel controller for plan results display.
 */

import * as vscode from "vscode";
import type { PlanResultsToWebview, PlanResultsFromWebview } from "./messages.ts";
import { buildWebviewHtml } from "../../extension-host/webview-html.ts";
import { resolveFileUri } from "../../extension-host/resolve-file-uri.ts";

/** Options for opening the plan results panel. */
type PlanResultsPanelOptions = {
  readonly context: vscode.ExtensionContext;
  readonly title: string;
  readonly content: string;
  readonly format: string;
};

/** Open a plan results panel showing the given content. */
export const openPlanResultsPanel = (options: PlanResultsPanelOptions): void => {
  const { context, title, content, format } = options;
  const panel = vscode.window.createWebviewPanel("indexion.planResults", `indexion: ${title}`, vscode.ViewColumn.One, {
    enableScripts: true,
    localResourceRoots: [vscode.Uri.joinPath(context.extensionUri, "dist", "webview")],
  });
  panel.iconPath = {
    light: vscode.Uri.joinPath(context.extensionUri, "media", "plan-light.svg"),
    dark: vscode.Uri.joinPath(context.extensionUri, "media", "plan-dark.svg"),
  };

  const scriptUri = panel.webview.asWebviewUri(
    vscode.Uri.joinPath(context.extensionUri, "dist", "webview", "plan-results.js"),
  );
  const styleUri = panel.webview.asWebviewUri(
    vscode.Uri.joinPath(context.extensionUri, "dist", "webview", "style.css"),
  );

  panel.webview.html = buildWebviewHtml({
    webview: panel.webview,
    scriptUri,
    styleUri,
    title: "indexion Plan Results",
  });

  const message: PlanResultsToWebview = { type: "resultLoaded", title, content, format };
  panel.webview.postMessage(message);

  panel.webview.onDidReceiveMessage(
    (msg: PlanResultsFromWebview) => {
      if (msg.type === "openFile") {
        const uri = resolveFileUri(msg.filePath);
        vscode.workspace.openTextDocument(uri).then((doc) => vscode.window.showTextDocument(doc));
      }
      if (msg.type === "copyContent") {
        vscode.env.clipboard.writeText(content);
        vscode.window.showInformationMessage("Content copied to clipboard.");
      }
    },
    undefined,
    context.subscriptions,
  );
};
