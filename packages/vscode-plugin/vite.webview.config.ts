/**
 * @file Vite build configuration for React webview panels.
 */

import path from "node:path";
import fs from "node:fs";
import { defineConfig } from "vite";
import tailwindcss from "@tailwindcss/vite";

/**
 * When `moon build --target js` has been run, the MoonBit-compiled
 * tokenizer is available. Alias @indexion/kgf-tokenizer to it for
 * real syntax highlighting. Otherwise the package's default stub
 * export is used (returns empty tokens → plain text rendering).
 */
const artifactPath = path.resolve(
  __dirname,
  "../../_build/js/debug/build/cmd/kgf-tokenizer/kgf-tokenizer.js",
);

const kgfAlias = fs.existsSync(artifactPath)
  ? { "@indexion/kgf-tokenizer": artifactPath }
  : {};

export default defineConfig({
  plugins: [tailwindcss()],
  resolve: {
    alias: kgfAlias,
  },
  optimizeDeps: {
    exclude: ["@indexion/kgf-tokenizer"],
  },
  build: {
    outDir: "dist/webview",
    rollupOptions: {
      input: {
        settings: "src/webview/settings/app.tsx",
        "plan-results": "src/webview/plan-results/app.tsx",
        search: "src/webview/search/app.tsx",
        explore: "src/webview/explore/app.tsx",
        "wiki-viewer": "src/webview/wiki-viewer/app.tsx",
      },
      output: {
        entryFileNames: "[name].js",
        assetFileNames: "[name][extname]",
      },
    },
    sourcemap: true,
    minify: false,
    cssCodeSplit: false,
  },
  css: {
    modules: {
      localsConvention: "camelCase",
    },
  },
});
