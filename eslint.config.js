/**
 * @file Unified ESLint flat config for the entire monorepo.
 *
 * packages/vscode-plugin has stricter rules (jsdoc, mock prohibition,
 * custom AST rules) applied via scoped overrides below.
 */

import eslint from "@eslint/js";
import tseslint from "typescript-eslint";
import eslintConfigPrettier from "eslint-config-prettier";
import eslintPluginPrettier from "eslint-plugin-prettier";
import reactHooks from "eslint-plugin-react-hooks";
import importPlugin from "eslint-plugin-import";
import jsdocPlugin from "eslint-plugin-jsdoc";
import eslintCommentsPlugin from "@eslint-community/eslint-plugin-eslint-comments";

// vscode-plugin custom rules (now at repo root)
import customPlugin from "./eslint/plugins/custom/index.js";
import rulesJSDoc from "./eslint/rules/rules-jsdoc.js";
import rulesRestrictedSyntax from "./eslint/rules/rules-restricted-syntax.js";
import rulesCurly from "./eslint/rules/rules-curly.js";
import rulesNoTestImports from "./eslint/rules/rules-no-test-imports.js";
import rulesNoMocks from "./eslint/rules/rules-no-mocks.js";

export default tseslint.config(
  eslint.configs.recommended,
  ...tseslint.configs.recommended,
  eslintConfigPrettier,

  // ── Global ignores ────────────────────────────────────────
  {
    ignores: [
      "**/node_modules/**",
      "**/dist/**",
      "**/.vite/**",
      "**/coverage/**",
      ".mooncakes/**",
      "_build/**",
      "target/**",
      "fixtures/**",
      "eslint/**",
      "**/vitest.config.*",
      "**/vite.*.config.*",
      "**/.vscode-test/**",
      "**/*.d.ts",
    ],
  },

  // ── Shared rules (all TS/TSX) ─────────────────────────────
  {
    files: ["**/*.ts", "**/*.tsx"],
    plugins: {
      prettier: eslintPluginPrettier,
      custom: customPlugin,
    },
    rules: {
      "prettier/prettier": "error",
      "@typescript-eslint/consistent-type-definitions": ["error", "type"],
      curly: ["error", "all"],
      "custom/no-as-outside-guard": "error",
      "no-restricted-syntax": [
        "error",
        {
          selector: "TryStatement TryStatement",
          message:
            "try-catchのネストは禁止されています。処理を分割してください。",
        },
        {
          selector: "CatchClause:not([param])",
          message:
            "catch節には必ずエラー引数を指定し、適切に処理してください。",
        },
        {
          selector: "IfStatement > IfStatement.alternate",
          message:
            "else if は禁止されています。switch-case または object の key-value で解決してください。",
        },
        {
          selector:
            "CallExpression[callee.name='useEffect'] :function > BlockStatement > ExpressionStatement > CallExpression[callee.name=/^set[A-Z]/]",
          message:
            "useEffect内でsetState (set*) を呼ばないでください。useSyncExternalStoreや外部ストア経由で状態を更新してください。",
        },
      ],
      "no-empty": ["error", { allowEmptyCatch: false }],
      "@typescript-eslint/no-unused-vars": [
        "error",
        {
          argsIgnorePattern: "^_",
          caughtErrors: "all",
        },
      ],
      "max-params": ["warn", { max: 3 }],
      "no-nested-ternary": "error",
    },
  },

  // ── Test files (any package): allow cast escape hatches ──
  {
    files: [
      "**/*.test.ts",
      "**/*.test.tsx",
      "**/*.spec.ts",
      "**/*.spec.tsx",
      "**/test-utils/**",
      "**/test-helpers.*",
    ],
    rules: {
      "custom/no-as-outside-guard": "off",
    },
  },

  // ── React hooks (TSX only) ────────────────────────────────
  {
    files: ["**/*.tsx"],
    plugins: {
      "react-hooks": reactHooks,
    },
    rules: {
      "react-hooks/rules-of-hooks": "error",
      "react-hooks/exhaustive-deps": "warn",
    },
  },


  // ── vscode-plugin: strict rules ───────────────────────────
  {
    files: ["packages/vscode-plugin/**/*.ts", "packages/vscode-plugin/**/*.tsx"],
    plugins: {
      import: importPlugin,
      jsdoc: jsdocPlugin,
      "@eslint-community/eslint-comments": eslintCommentsPlugin,
      custom: customPlugin,
    },
    settings: {
      jsdoc: { mode: "typescript" },
    },
    rules: {
      "custom/ternary-length": "error",
      "custom/prefer-node-protocol": "error",
      "custom/no-as-outside-guard": "error",
      "custom/no-nested-try": "error",
      "custom/no-iife-in-anonymous": "error",
      "custom/no-cross-boundary-export": "error",
      "custom/no-reexport-outside-entry": "error",
      "custom/enforce-index-import": "error",
      ...rulesJSDoc,
      ...rulesRestrictedSyntax,
      ...rulesCurly,
      ...rulesNoTestImports,
      ...rulesNoMocks,
    },
  },

  // ── vscode-plugin: test files — allow test globals ────────
  {
    files: [
      "packages/vscode-plugin/**/*.spec.ts",
      "packages/vscode-plugin/**/*.spec.tsx",
      "packages/vscode-plugin/**/*.test.ts",
      "packages/vscode-plugin/**/*.test.tsx",
    ],
    languageOptions: {
      globals: {
        describe: "readonly",
        it: "readonly",
        test: "readonly",
        expect: "readonly",
        beforeAll: "readonly",
        afterAll: "readonly",
        beforeEach: "readonly",
        afterEach: "readonly",
        suite: "readonly",
        bench: "readonly",
        vi: "readonly",
      },
    },
    rules: {
      // Allow vitest globals, mocks, and test-specific patterns in test files
      "no-restricted-globals": "off",
      "no-restricted-imports": "off",
      "no-restricted-properties": "off",
      "no-restricted-syntax": "off",
      "custom/no-as-outside-guard": "off",
    },
  },

  // ── vscode-plugin: test utilities — relax mock-related rules ──
  {
    files: [
      "packages/vscode-plugin/src/test-utils/**",
      "packages/vscode-plugin/src/**/test-helpers.*",
    ],
    rules: {
      "custom/no-as-outside-guard": "off",
    },
  },

  // ── vscode-plugin: eslint plugin source — disable custom on itself ──
  {
    files: ["eslint/**"],
    rules: {
      "custom/ternary-length": "off",
      "custom/no-as-outside-guard": "off",
      "custom/no-nested-try": "off",
      "custom/no-iife-in-anonymous": "off",
      "custom/no-cross-boundary-export": "off",
      "custom/no-reexport-outside-entry": "off",
      "custom/enforce-index-import": "off",
    },
  },
);
