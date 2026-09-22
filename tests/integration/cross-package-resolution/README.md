# tests/integration/cross-package-resolution

Snapshot-based integration tests that pin the observable output of
`indexion doc graph --format=codegraph` for each fixture project under
`fixtures/project/`.

## What these tests guard

1. **`moduleDependsOn` edge set** — every cross-package import that the
   analyzer produces, including canonicalization back to internal paths
   for workspace/internal packages.
2. **Structural completeness** — every edge of a built-in `EdgeKind`
   (`declares`, `moduleDependsOn`, `calls`, `references`, `imports`,
   `extends`, `implements`, `circularDependency`) must have both endpoints
   registered as modules or symbols in the final serialized graph. This is
   the invariant downstream consumers (the React viewer, IDE plugins) rely
   on when rendering the graph.

Custom edge kinds emitted by KGF specs for metadata (`projectName`,
`projectKeyword`, `packageVersion`, …) are intentionally excluded from the
structural completeness check because their `to` fields carry free-form
values like keywords or version strings, not module identities.

## Coverage

| Snapshot | Fixture | Ecosystem / constructs exercised |
| --- | --- | --- |
| `python.snapshot.json` | `fixtures/project/python` | pyproject.toml, src-layout, sub-packages, `from .X import Y` |
| `cargo.snapshot.json` | `fixtures/project/cargo` | Cargo single-crate, `use crate::..`, extern crates via Cargo.toml deps |
| `cargo-workspace.snapshot.json` | `fixtures/project/cargo-workspace` | Cargo `[workspace]` with multiple `crates/*` and path deps |
| `go.snapshot.json` | `fixtures/project/go` | go.mod modules, internal sub-packages, stdlib-shaped paths |
| `ruby.snapshot.json` | `fixtures/project/ruby` | Gemfile + `require_relative` module layout |
| `php.snapshot.json` | `fixtures/project/php` | composer.json PSR-4 + PSR-0, multi-prefix map with longest-key precedence (`App\Billing\` outranks `App\`), `use` namespaces |
| `swift.snapshot.json` | `fixtures/project/swift` | Package.swift with library + executable targets |
| `csharp.snapshot.json` | `fixtures/project/csharp` | .csproj with PackageReference, multi-file namespaces |
| `maven.snapshot.json` | `fixtures/project/maven` | pom.xml + Spring Boot layout |
| `gradle.snapshot.json` | `fixtures/project/gradle` | build.gradle.kts + Kotlin sources; a Kotlin file under `src/main/java` proves the second `source_roots` entry is probed |
| `gradle-multimodule.snapshot.json` | `fixtures/project/gradle-multimodule` | Multi-project Gradle (`settings.gradle.kts` + per-module `build.gradle.kts`); pins that `source_roots` anchors at the NEAREST manifest |
| `deno.snapshot.json` | `fixtures/project/deno` | deno.json imports + relative URLs |
| `npm.snapshot.json` | `fixtures/project/npm` | package.json single package + TS relative imports |
| `npm-circular.snapshot.json` | `fixtures/project/npm-circular` | Intentional circular TS import cycle |
| `npm-monorepo.snapshot.json` | `fixtures/project/npm-monorepo` | npm workspace with multiple packages + cross-workspace imports |
| `typescript-reconcile.snapshot.json` | `fixtures/project/typescript-reconcile` | TS project with internal-only imports (no cross-package deps) |
| `moonbit-with-web.snapshot.json` | `fixtures/project/moonbit-with-web` | MoonBit core + embedded npm web project |
| `moonbit.snapshot.json` | `fixtures/project/moonbit` | `moon.pkg` alias capture, source-file `@alias` scan, `projectSourceDir` resolution |
| `vcpkg.snapshot.json` | `fixtures/project/vcpkg` | vcpkg.json manifest + C/C++ sources: a `.h` included from both a `.c` and a `.cpp`, nested namespaces, out-of-line member definitions, typedef'd struct tags (deps only; source-level `#include` not yet parsed) |
| `tsconfig-paths.snapshot.json` | `fixtures/project/tsconfig-paths` | tsconfig `compilerOptions.paths` + `baseUrl` (`@app/*`, `@domain/*`, plain `shared/*`), plus a nested `scripts/` sub-project resolved through its own jsconfig.json |
| `spec-overlay.snapshot.json` | `fixtures/project/spec-overlay` | project-local `.indexion/kgfs/` overlay whose spec `extends:` a base spec and claims its own `sources:` extension |

## Running

```bash
moon test --target native tests/integration/cross-package-resolution
```

Each test analyzes its fixture and compares the normalized snapshot
(`snapshot_of(graph)`) against the committed JSON file.

## Updating snapshots

When the analyzer's behaviour changes legitimately (new edge kinds, smarter
canonicalization, grammar improvements), regenerate the snapshots:

```bash
INDEXION_UPDATE_SNAPSHOTS=1 moon test --target native tests/integration/cross-package-resolution
```

Review the resulting diff carefully — any change is a user-visible change
to the codegraph output that downstream consumers will see.

## Adding a new fixture

1. Add the fixture directory under `fixtures/project/<name>/` with a
   manifest file and representative source files (imports, sub-packages,
   external dependency references).
2. Create `<name>_test.mbt`:

   ```moonbit
   test "snapshot: fixtures/project/<name>" {
     let graph = analyze_fixture("fixtures/project/<name>")
     assert_snapshot_matches(
       "tests/integration/cross-package-resolution/<name>.snapshot.json",
       snapshot_of(graph),
     )
     assert_eq(count_unresolved_structural(graph), 0)
   }
   ```

3. Run with `INDEXION_UPDATE_SNAPSHOTS=1` to generate the initial snapshot.
4. Commit both the fixture files and the snapshot.

## Known limitations (will become apparent as snapshot diffs when fixed)

- Rust `use` statements emit one edge per `use` and do not yet fan out
  multi-item `use foo::{a, b, c}` groups. The first item's resolution
  stands for the group.
- C/C++ (`#include`) is not parsed; only the vcpkg/CMake manifest deps
  surface in the graph. `cpp.kgf` tokenizes `Include` but no semantics rule
  turns it into an import edge, so `fixtures/project/vcpkg` has an empty
  `moduleDependsOn` set despite its `#include "config.hpp"` lines.
- C/C++ `extern "C" { ... }` has no linkage-specification production in
  `cpp.kgf`, so declarations inside such a block are swallowed by the brace
  body and never extracted. `fixtures/project/vcpkg/include/buffer.h`
  parses cleanly but yields zero `declares` edges for that reason; the same
  declarations in `src/buffer.c` (the `c` spec, no `extern "C"` wrapper)
  are extracted normally.
- C/C++ out-of-line member definitions (`void Session::write() {}`) are
  extracted as bare top-level functions named `write`, losing both the
  `Session::` qualifier and the enclosing namespace; out-of-line
  constructors and destructors yield no edge at all.
- A Gradle `project(":core")` dependency is not followed: `source_roots`
  anchors each module at its own manifest by design, and no resolver step
  bridges to a sibling module's source root, so cross-module imports keep
  the `maven:` fallback (see `gradle-multimodule.snapshot.json`).
- Duplicate edges sometimes appear (same `(from, to)` pair recorded twice)
  when grammar alternatives both fire on the same input. These are
  deterministic and locked into the snapshot; collapsing them is a
  follow-up.
