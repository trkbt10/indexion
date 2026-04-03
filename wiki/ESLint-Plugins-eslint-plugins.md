<!-- indexion:sources eslint/plugins/ -->
# eslint/plugins -- ESLint Plugins

The `eslint/plugins/` directory contains a custom ESLint plugin with 9 project-specific rules for the indexion TypeScript codebase (used by the VS Code plugin). These rules enforce coding standards that go beyond what built-in ESLint rules provide, covering type safety, module boundaries, and code style constraints.

## Contents

```
eslint/plugins/
└── custom/
    ├── index.js                              # Plugin entry point (exports all rules)
    └── rules/
        ├── ternary-length.js                 # Ternary must be single-line, <=120 chars
        ├── prefer-node-protocol.js           # Require `node:` protocol for core imports
        ├── no-empty-jsdoc.js                 # Disallow empty JSDoc block comments
        ├── no-as-outside-guard.js            # Disallow `as any`/`as unknown` except in type guards
        ├── no-nested-try.js                  # Disallow nested try-catch statements
        ├── no-iife-in-anonymous.js           # Disallow IIFE inside anonymous functions
        ├── no-cross-boundary-export.js       # Disallow re-exports traversing parent dirs
        ├── no-reexport-outside-entry.js      # Disallow re-exports outside entry points
        ├── enforce-index-import.js           # Enforce imports through index.ts
        ├── enforce-index-import.spec.ts      # Tests
        ├── no-iife-in-anonymous.spec.ts      # Tests
        ├── no-cross-boundary-export.spec.ts  # Tests
        ├── no-reexport-outside-entry.spec.ts # Tests
        └── README.md                         # Auto-generated API reference
```

### Rule Descriptions

| Rule | Type | Description |
|------|------|-------------|
| `ternary-length` | problem | Ternary expressions must be single-line and within 120 characters |
| `prefer-node-protocol` | -- | Require `node:` prefix for Node.js core module imports (e.g. `node:fs`) |
| `no-empty-jsdoc` | -- | Disallow empty JSDoc block comments (whitespace-only `/** */`) |
| `no-as-outside-guard` | problem | Disallow `as any` and `as unknown` except in type guard cast patterns |
| `no-nested-try` | problem | Disallow nested try-catch statements |
| `no-iife-in-anonymous` | problem | Disallow IIFE inside anonymous functions |
| `no-cross-boundary-export` | problem | Disallow re-export declarations with parent directory traversal (`../`) |
| `no-reexport-outside-entry` | problem | Disallow re-exports outside designated entry points (`src/index.ts` or package.json `exports`) |
| `enforce-index-import` | problem | Enforce imports through `index.ts` when a directory has one (prevents reaching into internals) |

## Usage

The plugin is registered in the ESLint configuration as a local plugin:

```javascript
import customPlugin from "./eslint/plugins/custom/index.js";

export default [
  {
    plugins: { custom: customPlugin },
    rules: {
      "custom/ternary-length": "error",
      "custom/prefer-node-protocol": "error",
      "custom/no-empty-jsdoc": "error",
      "custom/no-as-outside-guard": "error",
      "custom/no-nested-try": "error",
      "custom/no-iife-in-anonymous": "error",
      "custom/no-cross-boundary-export": "error",
      "custom/no-reexport-outside-entry": "error",
      "custom/enforce-index-import": "error",
    },
  },
];
```

> Source: `eslint/plugins/`
