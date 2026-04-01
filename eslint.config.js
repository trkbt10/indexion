import eslint from "@eslint/js";
import tseslint from "typescript-eslint";
import eslintConfigPrettier from "eslint-config-prettier";
import eslintPluginPrettier from "eslint-plugin-prettier";
import reactHooks from "eslint-plugin-react-hooks";

export default tseslint.config(
  eslint.configs.recommended,
  ...tseslint.configs.recommended,
  eslintConfigPrettier,
  {
    ignores: [
      "**/node_modules/**",
      "**/dist/**",
      "**/.vite/**",
      ".mooncakes/**",
      "_build/**",
      "target/**",
      "packages/vscode-plugin/**",
      "fixtures/**",
    ],
  },
  {
    files: ["**/*.ts", "**/*.tsx"],
    plugins: {
      prettier: eslintPluginPrettier,
    },
    rules: {
      "prettier/prettier": "error",
      "@typescript-eslint/consistent-type-definitions": ["error", "type"],
      curly: ["error", "all"],
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
  {
    files: ["**/*.d.ts"],
    rules: {
      "@typescript-eslint/consistent-type-definitions": "off",
    },
  },
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
);
