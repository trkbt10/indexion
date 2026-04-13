import path from "node:path";
import fs from "node:fs";
import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import tailwindcss from "@tailwindcss/vite";

const isStaticMode = !!process.env.VITE_STATIC_MODE;

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
  base: isStaticMode ? "/indexion/" : "/",
  plugins: [react(), tailwindcss()],
  root: "src/client",
  resolve: {
    conditions: ["bun", "module"],
    alias: kgfAlias,
  },
  build: {
    outDir: "../../dist/client",
    emptyOutDir: true,
    rollupOptions: {
      output: {
        manualChunks: {
          three: ["three"],
        },
      },
    },
  },
  server: {
    port: 5173,
    proxy: {
      "/api": "http://localhost:3741",
    },
  },
});
