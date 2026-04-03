<!-- indexion:sources eslint/rules/ -->
# eslint/rules -- ESLint Rule Groups

The `eslint/rules/` directory contains ESLint rule group configurations, each exported as a default object of rule settings. These modules organize related rules into logical groups that are composed into the final ESLint flat config. Each file is a standalone module exporting rule entries to be spread into a config's `rules` field.

## Contents

```
eslint/rules/
├── rules-curly.js              # Block statement enforcement
├── rules-jsdoc.js              # JSDoc and documentation rules
├── rules-no-mocks.js           # Mock API prohibition
├── rules-no-test-imports.js    # Test library import prohibition
└── rules-restricted-syntax.js  # Syntax restrictions and style enforcement
```

### rules-curly.js

Enforces block braces (`{}`) on all `if`/`else`/`for`/`while` statements via `curly: ["warn", "all"]`.

### rules-jsdoc.js

Documentation quality rules:
- `no-empty`: Disallow empty blocks (including empty catch)
- `custom/no-empty-jsdoc`: Error on empty JSDoc comments
- `jsdoc/require-file-overview`: Warn on missing file overview
- `jsdoc/require-jsdoc`: Warn on missing JSDoc for public API (function and class declarations)

### rules-no-mocks.js

Prohibits mocking APIs from Jest and Vitest. Bans global access to `jest` and `vi` objects, and blocks specific mocking methods (`mock`, `fn`, `spyOn`). Enforces the project convention of preferring dependency injection and simple fakes over mocks.

### rules-no-test-imports.js

Prohibits importing test libraries (`bun:test`, `vitest`, `@jest/globals`, `jest`, `mocha`) via both ES module imports and CommonJS requires. The project convention is to use test runner globals (`describe`, `it`, `expect`) injected by the runner rather than explicit imports.

### rules-restricted-syntax.js

The most comprehensive rule group, enforcing several project conventions:
- Prohibit dynamic `import()` and `TSImportType`
- Prohibit `interface` declarations (use `type` instead)
- Prohibit `export * as` and `export type *`
- Prohibit `class` declarations (except extending `Error`)
- Prohibit `let` (except in `for` loops) -- prefer separate functions with return values
- Prohibit `as any` / `as unknown` without proper type guards
- Prohibit mock APIs via AST selectors (redundant with rules-no-mocks for defense in depth)
- Require descriptions on eslint-disable comments

## Usage

These rule groups are imported and spread into ESLint flat config entries:

```javascript
import rulesCurly from "./eslint/rules/rules-curly.js";
import rulesJsdoc from "./eslint/rules/rules-jsdoc.js";

export default [
  {
    rules: {
      ...rulesCurly,
      ...rulesJsdoc,
    },
  },
];
```

> Source: `eslint/rules/`
