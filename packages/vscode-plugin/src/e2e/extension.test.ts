/**
 * @file E2E tests for the indexion VSCode extension.
 *
 * Runs inside a real VSCode instance via @vscode/test-electron.
 * The workspace folder is set to the indexion project root by .vscode-test.mjs.
 */

import * as assert from "node:assert";
import * as vscode from "vscode";
import { fetchKgfList, type HttpClient } from "@indexion/api-client";

/** Find the indexion extension regardless of its ID format. */
const findExtension = () =>
  vscode.extensions.all.find((e) => e.id.includes("indexion") || e.packageJSON?.displayName === "indexion");

/** Activate extension and return its exports. */
const activateExtension = async () => {
  const ext = findExtension();
  assert.ok(
    ext,
    `indexion extension not found. Available non-builtin: ${vscode.extensions.all
      .map((e) => e.id)
      .filter((id) => !id.startsWith("vscode."))
      .join(", ")}`,
  );
  if (!ext.isActive) {
    await ext.activate();
  }
  return ext;
};

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

suite("Extension E2E", () => {
  test("workspace folder is the project root", () => {
    const folders = vscode.workspace.workspaceFolders;
    assert.ok(folders, "workspaceFolders should be defined");
    assert.strictEqual(folders.length, 1);
    const folder = folders[0]!.uri.fsPath;
    assert.ok(
      folder.endsWith("/indexion") || folder.endsWith("\\indexion"),
      `workspace should be the indexion project root, got: ${folder}`,
    );
  });

  test("extension activates and exports API", async () => {
    const ext = await activateExtension();
    assert.ok(ext.isActive, "extension should be active");
    assert.ok(typeof ext.exports?.isServerReady === "function", "should export isServerReady()");
    assert.ok(typeof ext.exports?.getClient === "function", "should export getClient()");
  });

  test("all commands from package.json are registered", async () => {
    const ext = await activateExtension();
    assert.ok(ext);
    const commands = await vscode.commands.getCommands(true);

    // Read expected commands directly from package.json — single source of truth.
    const declared: ReadonlyArray<string> = ext.packageJSON.contributes.commands.map(
      (c: { command: string }) => c.command,
    );
    assert.ok(declared.length > 0, "package.json should declare at least one command");
    for (const cmd of declared) {
      assert.ok(commands.includes(cmd), `command ${cmd} should be registered`);
    }
    console.log(`[e2e] all ${declared.length} commands registered`);
  });

  test("server starts within 60 seconds", async function () {
    this.timeout(90_000);
    const ext = await activateExtension();

    for (let i = 0; i < 60; i++) {
      if (ext.exports?.isServerReady?.()) {
        return; // success
      }
      await sleep(1000);
    }
    assert.fail("server did not become ready within 60 seconds");
  });

  test("KGF list auto-refreshes after server ready", async function () {
    this.timeout(90_000);
    const ext = await activateExtension();

    // Wait for server to be ready
    for (let i = 0; i < 60; i++) {
      if (ext.exports?.isServerReady?.()) {
        break;
      }
      await sleep(1000);
    }
    assert.ok(ext.exports?.isServerReady?.(), "server should be ready");

    // After server ready, onReady should have fired refresh().
    // getChildren is async, so give it a moment to complete the fetch.
    let specCount = 0;
    for (let i = 0; i < 10; i++) {
      specCount = ext.exports.getKgfSpecCount();
      if (specCount > 0) {
        break;
      }
      await sleep(500);
    }

    console.log(`[e2e] auto-refresh spec count: ${specCount}`);
    assert.ok(specCount > 0, `KGF specs should be auto-loaded after server ready, got ${specCount}`);
  });

  test("KGF list returns specs via API client", async function () {
    this.timeout(90_000);
    const ext = await activateExtension();

    // Wait for server
    for (let i = 0; i < 60; i++) {
      if (ext.exports?.isServerReady?.()) {
        break;
      }
      await sleep(1000);
    }
    assert.ok(ext.exports?.isServerReady?.(), "server should be ready");

    const client: HttpClient = ext.exports.getClient();
    assert.ok(client, "HTTP client should be available");

    const result = await fetchKgfList(client);
    assert.ok(result.ok, `fetchKgfList should succeed, got error: ${!result.ok ? result.error : ""}`);
    assert.ok(result.ok);

    console.log(`[e2e] KGF specs: ${result.data.length} total`);
    assert.ok(result.data.length > 0, `should have specs, got ${result.data.length}`);

    // Verify known categories exist
    const categories = new Set(result.data.map((s) => s.category));
    console.log(`[e2e] categories: ${[...categories].join(", ")}`);
    assert.ok(categories.has("programming"), `should have programming category, got: ${[...categories].join(", ")}`);
    assert.ok(categories.has("dsl"), `should have dsl category, got: ${[...categories].join(", ")}`);

    // Verify known specs exist
    const names = new Set(result.data.map((s) => s.name));
    assert.ok(names.has("typescript"), `should have typescript spec`);
    assert.ok(names.has("moonbit"), `should have moonbit spec`);
    console.log(`[e2e] KGF list verified: ${result.data.length} specs, ${categories.size} categories`);
  });

  test("exploreSimilar command opens explore panel without error", async function () {
    this.timeout(90_000);
    const ext = await activateExtension();

    for (let i = 0; i < 60; i++) {
      if (ext.exports?.isServerReady?.()) {
        break;
      }
      await sleep(1000);
    }
    assert.ok(ext.exports?.isServerReady?.(), "server should be ready");

    const folders = vscode.workspace.workspaceFolders;
    assert.ok(folders);
    const targetUri = vscode.Uri.joinPath(folders[0]!.uri, "packages", "vscode-plugin", "src", "views", "search");

    await vscode.commands.executeCommand("indexion.exploreSimilar", targetUri);
    await sleep(2000);

    console.log("[e2e] exploreSimilar command executed without error");
  });
});
