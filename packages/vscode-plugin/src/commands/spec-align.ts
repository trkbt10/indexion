/**
 * @file Command handlers for `indexion.specAlign*` commands.
 */

import * as vscode from "vscode";
import { runSpecAlignDiff, runSpecAlignTrace, runSpecAlignSuggest, runSpecAlignStatus } from "@indexion/api-client";
import { runPlanCommand, requireConfig } from "./plan-common.ts";

/** Prompt user to pick spec and impl files, returns undefined on cancel. */
const pickSpecImplPaths = async (): Promise<{ specPath: string; implPath: string } | undefined> => {
  const specUris = await vscode.window.showOpenDialog({
    canSelectMany: false,
    openLabel: "Select Spec File",
    title: "Spec file (SDD / spec.mbt / spec.*)",
  });
  if (!specUris || specUris.length === 0) {
    return undefined;
  }

  const implUris = await vscode.window.showOpenDialog({
    canSelectMany: false,
    openLabel: "Select Implementation File/Dir",
    title: "Implementation file or directory",
    canSelectFolders: true,
  });
  if (!implUris || implUris.length === 0) {
    return undefined;
  }

  const resolved = requireConfig();
  if (!resolved) {
    return undefined;
  }

  return {
    specPath: vscode.workspace.asRelativePath(specUris[0]),
    implPath: vscode.workspace.asRelativePath(implUris[0]),
  };
};

/** Execute spec align diff command. */
export const executeSpecAlignDiff = async (): Promise<void> => {
  const paths = await pickSpecImplPaths();
  if (!paths) {
    return;
  }

  return runPlanCommand(
    "Spec Align: Diff",
    "indexion: Comparing spec vs implementation...",
    (client, _config, signal) =>
      runSpecAlignDiff(client, { specPath: paths.specPath, implPath: paths.implPath, format: "md" }, signal),
  );
};

/** Execute spec align trace command. */
export const executeSpecAlignTrace = async (): Promise<void> => {
  const paths = await pickSpecImplPaths();
  if (!paths) {
    return;
  }

  return runPlanCommand(
    "Spec Align: Trace",
    "indexion: Tracing spec/impl relationships...",
    (client, _config, signal) =>
      runSpecAlignTrace(client, { specPath: paths.specPath, implPath: paths.implPath, format: "md" }, signal),
  );
};

/** Execute spec align suggest command. */
export const executeSpecAlignSuggest = async (): Promise<void> => {
  const paths = await pickSpecImplPaths();
  if (!paths) {
    return;
  }

  return runPlanCommand(
    "Spec Align: Suggest",
    "indexion: Generating spec improvement suggestions...",
    (client, _config, signal) =>
      runSpecAlignSuggest(client, { specPath: paths.specPath, implPath: paths.implPath, format: "md" }, signal),
  );
};

/** Execute spec align status command. */
export const executeSpecAlignStatus = async (): Promise<void> => {
  const paths = await pickSpecImplPaths();
  if (!paths) {
    return;
  }

  return runPlanCommand(
    "Spec Align: Status",
    "indexion: Checking spec alignment status...",
    (client, _config, signal) =>
      runSpecAlignStatus(client, { specPath: paths.specPath, implPath: paths.implPath, format: "md" }, signal),
  );
};
