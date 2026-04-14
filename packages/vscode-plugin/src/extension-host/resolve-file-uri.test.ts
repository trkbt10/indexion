/**
 * @file Tests for resolveFileUri.
 */

import { describe, it, expect, vi } from "vitest";
import { resolveFileUri } from "./resolve-file-uri.ts";

vi.mock("vscode", () => ({
  Uri: {
    joinPath: (base: { fsPath: string }, ...segments: ReadonlyArray<string>) => {
      const joined = `${base.fsPath}/${segments.join("/")}`;
      return { fsPath: joined, toString: () => joined };
    },
    file: (path: string) => ({ fsPath: path, toString: () => path }),
  },
  workspace: {
    workspaceFolders: [{ uri: { fsPath: "/workspace", toString: () => "/workspace" } }],
  },
}));

describe("resolveFileUri", () => {
  it("returns absolute path as-is", () => {
    const uri = resolveFileUri("/abs/path/file.ts");
    expect(uri.fsPath).toBe("/abs/path/file.ts");
  });

  it("resolves relative path against workspace root", () => {
    const uri = resolveFileUri("cmd/indexion/explore/cli.mbt");
    expect(uri.fsPath).toBe("/workspace/cmd/indexion/explore/cli.mbt");
  });

  it("resolves simple filename against workspace root", () => {
    const uri = resolveFileUri("README.md");
    expect(uri.fsPath).toBe("/workspace/README.md");
  });
});
