<!-- indexion:sources src/kgf/lexer/, src/kgf/parser/, src/kgf/registry/, src/kgf/semantics/, kgfs/ -->
# KGF (Knowledge Graph Framework)

KGF is indexion's unified specification language for programming languages. Rather than writing custom parsers for every language, indexion uses declarative `.kgf` spec files that describe how to tokenize, parse, and extract semantic relationships from source code. A single spec file -- typically 100-300 lines -- is enough to teach indexion a new language. The project ships 63 specs covering programming languages, DSLs, project manifests, natural languages, and even binary format decoders.

## Why KGF Exists

Traditional code analysis tools hard-wire language knowledge into their implementation. Adding a new language means writing thousands of lines of parser code. KGF inverts this: the analysis engine is language-agnostic, and all language-specific knowledge lives in spec files. The engine reads a spec at runtime, constructs a lexer and PEG parser from it, and uses semantic actions to build a knowledge graph. This design means that supporting a new language is a data problem, not a code problem.

## Spec File Structure

Every KGF file begins with a header and is divided into named sections separated by `=== section_name` markers. The parser splits the file by these markers and delegates each section to a specialized sub-parser `[src/kgf/parser/parse_kgf.mbt:76-87]`.

```
kgf 0.6
language: typescript
sources: .ts, .d.ts

=== lex
...token definitions...

=== grammar
...PEG rules...

=== attrs
...attribute annotations...

=== features
...consumer metadata...

=== semantics
...graph construction rules...

=== resolver
...module resolution config...

=== ignore
...file patterns to skip...
```

The header declares the language name and the file extensions it covers. When the registry loads specs, it uses `sources` to build the extension-to-language mapping that drives automatic language detection `[src/kgf/registry/registry.mbt]`.

### Spec Inheritance (`extends:`)

Several specs describe a dialect of another: `Cargo.toml` and `pyproject.toml` are TOML, a wiki page is Markdown, TSX is TypeScript. Before `extends:` these were maintained as copies of their base, which meant every lexer or grammar bug had to be fixed once per copy. The optional `extends:` header field lets a spec inherit instead.

```kgf
kgf 0.6
language: sdd-user-story
sources: .md
extends: markdown

=== semantics
...only what differs from markdown...
```

`extends:` names the base by its `language`, not by a file path, so the base may live in any subdirectory of the same spec set. Merging is **section-level override**: for every `=== section`, the derived spec's text wins whole if the derived spec declares that section at all, and the base's is used otherwise. Nothing is merged *within* a section — a derived `=== grammar` replaces the base grammar entirely rather than adding rules to it, and a derived `=== semantics` replaces every `on` block of the base, not just the ones with the same rule name. A section declared with an empty body is still a declaration, and overrides the inherited one with nothing.

`language:` and `sources:` are never inherited: they identify the derived spec and decide which files it claims. Chains (`A extends B extends C`) are allowed, and each section is taken from the nearest ancestor that declares it.

Because a base may live in a subdirectory the loader has not walked yet, inheritance is resolved by the registry **after** the whole spec directory is loaded, not by the parser `[src/kgf/registry/registry.mbt]`. Loading splits each file into its raw section texts (`KGFSpecSource`), merges them along the `extends:` chain, and only then constructs the `KGFSpec`. Every spec the registry hands out is therefore fully resolved, so no consumer — toolkit, features, check, CLI — has to know that `extends:` exists. Merging the raw section texts rather than the parsed sections also keeps `KGFSpec`'s lazy parsing intact: a resolved spec still compiles its lexer patterns only on first use.

A missing base or an `extends:` cycle cannot fail the load — it runs on the hot path of every command — so loading falls back to the spec's own sections and `indexion kgf check <name>` reports the problem:

```
$ indexion kgf check cycle-a
cycle-a: 1 error(s), 0 warning(s)
  ERROR [extends] Spec inheritance cycle: cycle-a -> cycle-b -> cycle-a
```

`kgf check` on a derived spec validates the **resolved** spec, so a semantics block written against the inherited grammar checks clean, while a genuinely unbound reference in that same block is still reported. `indexion kgf list` shows each spec's base in an `Extends` column.

### === lex (Lexical Analysis)

The lex section defines token rules using regex patterns. Tokens are matched in declaration order -- first match wins -- so more specific patterns (keywords) must appear before general ones (identifiers). There are three kinds of rules `[src/kgf/parser/parse_lex.mbt:5-30]`:

- **SKIP** rules match text that is consumed but not emitted (whitespace, comments)
- **TOKEN** rules match text and emit a named token into the stream
- **LAYOUT** is a directive rather than a pattern: it declares how the engine should derive indentation depth after lexing (see below)

```kgf
=== lex
SKIP /[ \t]+/
TOKEN NL /\r?\n/
TOKEN KW_fn       /fn\b/
TOKEN Ident       /[a-zA-Z_][a-zA-Z0-9_]*/
TOKEN String      /"([^"\\]|\\.)*"/
TOKEN LBRACE      /\{/
```

Patterns use JavaScript-compatible regular expression syntax with support for character classes, quantifiers, groups, and lookahead. The lexer compiles each pattern once at construction time into a `CompiledPattern` for efficient matching `[src/kgf/lexer/lexer.mbt:3-11]`. Capture groups in patterns can extract sub-matches -- for example, a doc comment pattern `/(\/\/\/(.*))/` captures just the content after the `///` prefix. The special `skip_value` flag on a token makes it act as a marker without carrying text content.

#### LAYOUT (indentation-sensitive languages)

A regex cannot compare one line's indentation with the previous line's -- that comparison needs memory across matches -- so a regex-only lexer cannot tell a nested block from a sibling one. In Python, YAML, Haskell and every other layout-sensitive language, that is the whole of the nesting structure. `LAYOUT` declares how the engine should recover it, and a post-lex pass `[src/kgf/lexer/layout.mbt]` then maintains an indentation stack and injects synthetic INDENT / DEDENT tokens between the lexer's tokens, so a grammar rule can bracket a body exactly:

```kgf
=== lex
TOKEN NL_INDENT /\r?\n[ \t]+/
TOKEN NL        /\r?\n/
SKIP  /[ \t]+/
TOKEN Comment   /#[^\r\n]*/
TOKEN LPAREN    /\(/
...
LAYOUT newline=NL_INDENT,NL indent=INDENT dedent=DEDENT comment=Comment open=LPAREN,LBRACKET,LBRACE close=RPAREN,RBRACKET,RBRACE
```

```kgf
=== grammar
# A suite is exactly one INDENT...DEDENT pair, at any depth.
FunctionDef -> KW_def id:Ident Params COLON ( SuiteOpen doc:Docstring? BodyItem* DEDENT / SimpleBody )
SuiteOpen   -> ( LineBreak / Comment )* INDENT
```

The directive names token kinds, never literal syntax:

| Field | Required | Meaning |
|-------|----------|---------|
| `newline` | yes | the kind(s) whose text is a line break plus the *next* line's leading whitespace. Everything after the line break characters is that line's indentation. Several kinds may be listed when a spec splits indented from column-0 line breaks, as Python's `NL_INDENT` / `NL` do |
| `indent` | yes | the synthetic kind to emit when a line is indented deeper than the enclosing one |
| `dedent` | yes | the synthetic kind to emit once per level a shallower line closes |
| `comment` | no | the comment token kind. A line whose only token is a comment carries no layout, matching Python and YAML, where a comment may sit at any column |
| `open` / `close` | no | bracket kinds. While a bracket is open, layout is suppressed entirely: flow collections, multi-line calls and parameter lists may be laid out freely |

The pass ignores blank lines (a newline token followed directly by another newline token) and comment-only lines, closes every level still open at end of input, and tolerates a dedent to a column that is on no open level -- it emits the DEDENTs it can and adopts the new column, because indexion analyses files that do not compile. Indentation is compared as the raw whitespace string's **length in characters**, so one tab counts as one space; this is exact for the consistently-indented files real code consists of and needs no per-language tab width.

`indent` and `dedent` are *synthetic* kinds: they must not have a `TOKEN` definition, since no source text matches them, but they are valid grammar symbols. `kgf check` enforces both halves of that rule, reports a `LAYOUT` field naming a token kind the lex section does not define, and includes the synthetic kinds in the unreachable-token-kind check -- the pass injects them into every stream, so a grammar that ignores them would stop at the first indented line. `kgf tokens` shows them in the stream like any other token, with an empty text.

Because the pass lives inside `Lexer::tokenize`, every tokenization entry point gets it: `LanguageToolkit::tokenize` / `preprocess_and_tokenize`, the CLI's `kgf` subcommands, `check_source`, the declarations extractor and the graph pipeline all build their lexer with `Lexer::for_spec(spec)`, which carries the spec's layout declaration.

### === grammar (PEG Parsing)

The grammar section defines a Parsing Expression Grammar (PEG). Each rule maps a name to an expression composed of sequences, ordered choices, quantifiers, and labeled captures `[src/kgf/parser/parse_rules.mbt:1-63]`:

```kgf
=== grammar
Module -> ModuleDoc? Item*

Item -> FnDecl
     | StructDecl
     | LetDecl
     | Other

FnDecl -> fn_doc:DocBlock? Visibility? KW_fn fn_id:Ident LPAREN ParamList? RPAREN Body?
```

Labels like `fn_id:Ident` capture the matched token's text into a named variable that semantic actions can reference later. The PEG engine compiles rules into a `PEG` struct containing both an AST representation and a pre-compiled fast-evaluation form with integer IDs for token and rule references `[src/kgf/peg/peg.mbt:1-14]`. For small files, parsing uses a fast recursive evaluator; for large files, it switches to an iterative evaluator to avoid stack overflow `[src/kgf/peg/eval.mbt:66-96]`.

### === attrs (Attribute Annotations)

The attrs section provides shorthand annotations for common patterns. Each line declares what a matched rule represents:

```kgf
=== attrs
on FnDecl:      def fn_id kind=Function doc=fn_doc
on StructDecl:  def struct_id kind=Struct doc=struct_doc
on StructField: def field_id kind=Field doc=field_doc
```

The `def` annotation tells the system that this rule declares a symbol with the given identifier label, kind, and optional documentation label. These are evaluated before the full semantics blocks `[src/kgf/semantics/eval_semantics.mbt:35-47]`.

### === features (Consumer Metadata)

The features section exposes metadata that downstream consumers can query. Each line is a key mapping to a comma-separated list of values:

```kgf
=== features
document_symbol_kinds: Function, Struct, Enum, Type, Trait
coverage_token_kinds: Ident, TypeIdent, PackageRef
reference_token_kinds: INLINE_CODE
```

These inform consumers like documentation coverage analysis which token or symbol kinds are relevant, without hard-coding that knowledge into the analysis engine `[src/kgf/parser/parse_kgf.mbt:215-239]`.

### === semantics (Graph Construction)

The semantics section is where the knowledge graph is actually built. Each `on` block fires when a grammar rule matches and has access to all labeled captures from the parse:

```kgf
=== semantics
on FnDecl {
  let sym_id = concat($file, "::", $fn_id)
  edge declares from $file to sym_id attrs obj("name", $fn_id, "kind", "Function")
}

on StructField when $scope("value", "current_struct") {
  let parent = $scope("value", "current_struct")
  let sym_id = concat(parent, ".", $field_id)
  edge declares from parent to sym_id attrs obj("name", $field_id, "kind", "Field")
}

on ImportDecl {
  edge moduleDependsOn from $file to $resolve($path)
}
```

The semantics DSL supports eight statement types `[src/kgf/semantics/eval_stmt.mbt:3-15]`:

| Statement | Purpose |
|-----------|---------|
| `edge kind from X to Y` | Add a typed edge to the graph |
| `bind ns N name K to V` | Set a scoped variable (e.g., current class context) |
| `let var = expr` | Local variable assignment |
| `note type payload expr` | Emit metadata events (e.g., module documentation) |
| `for var in expr { ... }` | Iterate over arrays |
| `module id file expr` | Register a module node |
| `scope push` | Open a new lexical scope frame |
| `scope pop` | Close the innermost lexical scope frame |

Built-in functions like `$file` (current file path), `$resolve(path)` (module resolution), `$scope(ns, name)` (scope lookup), and `concat(...)` / `obj(...)` allow specs to construct node IDs and edge attributes without any language-specific code in the engine. The evaluation context (`SemEvalCtx`) maintains a stack of scope frames: `bind` writes into the innermost frame and `$scope` searches frames innermost-first, so a struct's fields can reference their parent struct `[src/kgf/semantics/context.mbt:75-91]`.

#### Lexical scoping with `scope push` / `scope pop`

Without explicit frame management every `bind` in a spec shares one flat frame, so a nested declaration permanently clobbers its parent's bindings. After `class Outer { class Inner { ... } fn m() }`, `current_class` would still point at `Inner` when `m` fires, and `m` would be attributed to the wrong class. `scope push` and `scope pop` fix this by bracketing a declaration's members in their own frame. `scope pop` on the root frame is a no-op, so an unbalanced spec degrades to the old flat behaviour rather than corrupting the stack.

Semantics events fire **bottom-up**: a rule's `on` block runs only after its entire body has been parsed, so children fire before their enclosing declaration. The frame must therefore be opened by a sub-rule that completes *before* the body — the declaration header — and closed by the enclosing declaration rule itself:

1. A **header** sub-rule (e.g. `ClassHeader -> KW_class id:Ident`) fires first: `scope push`, then `bind` the context the members will read.
2. **Member** rules fire next, inside that frame, and read it via `$scope`.
3. The **enclosing declaration** rule (e.g. `ClassDecl -> ClassHeader Body`) fires last: it emits its own edges — still inside the frame, so it can read its own binding — and ends with `scope pop`.

Statements run in source order within a block, so a block may freely read the frame before popping it; put `scope pop` last.

```kgf
on ClassHeader {
  scope push
  bind ns "value" name "current_class" to concat($file, "::", $id)
}

on Method when $scope("value", "current_class") {
  edge declares from $scope("value", "current_class") to concat($scope("value", "current_class"), ".", $id)
}

on ClassDecl {
  edge declares from $file to $scope("value", "current_class")
  scope pop
}
```

Symbols registered by `attrs def` also land in the innermost frame, so a member stops being resolvable by bare name once its class frame is popped — the intended lexical-visibility semantics. The symbol node itself is permanent: it lives in the graph, and only the name binding is scoped.

`kgf check` reports a warning when a spec uses `scope push` but never `scope pop` anywhere (or vice versa). The balance is checked spec-wide rather than per block, because the intended pattern deliberately splits the two halves across a header rule and its enclosing declaration rule `[src/kgf/check/check.mbt]`.

### === resolver (Module Resolution)

The resolver section configures how import paths map to files. It uses a YAML-like syntax `[src/kgf/parser/parse_resolver.mbt:1-57]`:

```kgf
=== resolver
sources: .ts, .tsx
relative_prefixes: ./, ../, /
bare_prefix: npm:
module_path_style: slash
exts: .ts, .tsx, .d.ts, .js
indexes: index.ts, index.js

aliases:
  -
    pattern: ^@/(.*)$
    replace: src/\1

resolve:
  - namespace_map: tsconfig.json @ compilerOptions.paths + compilerOptions.baseUrl
  - manifest: package.json @ dependencies
  - ext: .ts, .tsx
  - index: index.ts
  - fallback: npm:
```

The `resolve:` block defines a chain of resolution steps tried in order. The resolver implementation `[src/kgf/resolver/resolver.mbt]` applies aliases first, determines whether the import is relative or bare, walks the resolve chain, and only when every file probe has missed applies the prefix fallbacks. This means language ecosystems with very different module systems (npm, pip, Go modules, MoonBit packages) are all handled by the same engine configured through data.

#### Namespace and path mapping

A module path rarely maps onto the directory tree one-to-one from a single
base. Real projects **declare** the mapping in their manifest, and two step
types read that declaration instead of building the knowledge into the engine:

| Step | Value | Meaning |
|------|-------|---------|
| `namespace_map` | `file @ query [+ base_query] [? cond]` | Read an *object* field out of the nearest ancestor `file` and treat it as a map from a namespace/alias prefix to a directory |
| `source_roots` | `dir, dir [@ marker, marker]` | Use fixed, spec-declared source roots, anchored at the nearest ancestor directory holding one of the markers |

Both are evaluated relative to the **nearest ancestor manifest of the importing
file**, not the project root, so each package of a monorepo follows its own
mapping. Both end by running the chain's own `exact`/`index`/`ext`/`sibling`
probes against the rewritten path, so a mapping changes only *where* the
resolver looks, never *how* it decides a file is there.

For `namespace_map`, the **longest matching key wins**: with
`{"App\\": "src/", "App\\Dto\\": "custom/dto/"}` an `App\Dto\UserDto` takes the
second entry. A key may carry a `*` wildcard (`@app/*`), in which case the text
the wildcard stands for is appended to the value's own pre-wildcard directory
(`src/*` → `src/`); a key without one is a plain prefix, which is what PSR-4
uses. A value may be a string or an array of strings, and an array is probed in
the order the manifest lists it. `+ base_query` names a second manifest field
the values are themselves relative to — tsconfig's `baseUrl`.

When **no mapping matches** — or a mapping matches but no file is behind it —
the step contributes nothing and the chain simply continues. A declared mapping
narrows resolution; it never blocks it.

The object-valued read goes through the same manifest query helpers as the
string-valued `manifest` step, so `autoload.psr-4` and `exports["."].types` are
parsed by one path grammar.

```kgf
# composer: `{"App\\": "src/"}` makes App\Dto\UserDto into src/Dto/UserDto.php
- namespace_map: composer.json @ autoload.psr-4

# tsconfig: `{"@app/*": ["src/*"]}`, values relative to baseUrl
- namespace_map: tsconfig.json @ compilerOptions.paths + compilerOptions.baseUrl

# Java/Kotlin: the layout is conventional rather than declared
- source_roots: src/main/kotlin, src/main/java @ build.gradle.kts, build.gradle
```

#### Prefix fallbacks come last

`bare_prefix` and `ns_prefix` name a module that resolution could **not** find
on disk, so both are consulted only after every probe in the chain has missed.
`ns_prefix` is the more specific of the two — for a spec that declares it, a
backslash-namespaced identifier names a package in the ecosystem's vendor tree,
identified by its first `ns_segments` segments (`Vendor\Package\Thing` →
`vendor/Vendor\Package`) — so it is tried before `bare_prefix`.

Ordering matters here: deciding `ns_prefix` up front, as the resolver once did,
meant any identifier containing a backslash was declared external before a
single file was looked at, so a project's own namespaced classes could never
resolve to their files.

### === ignore

The ignore section lists glob patterns for files that should be excluded from analysis, similar to `.gitignore` syntax:

```kgf
=== ignore
_build/
target/
*_test.mbt
```

## The Pipeline

The processing pipeline transforms source code into a knowledge graph through three stages:

```mermaid
graph LR
    A[Source File] --> B[Lexer]
    B -->|Token Stream| C[PEG Parser]
    C -->|Rule Matches + Labels| D[Semantics Evaluator]
    D -->|Edges & Nodes| E[CodeGraph]

    S[.kgf Spec] --> B
    S --> C
    S --> D
```

1. **Lexing**: The `Lexer` struct takes token definitions from the `=== lex` section and transforms source text into a flat array of `Tok` values. Each token carries its kind (e.g., `KW_fn`, `Ident`), matched text, position, and optionally an extracted value. Skip tokens are consumed but not emitted `[src/kgf/lexer/lexer.mbt:30-60]`.

2. **Parsing**: The `PEG` engine takes grammar rules from `=== grammar` and matches them against the token stream. PEG parsing is deterministic -- ordered choice means the first matching alternative wins. When a rule matches, its labeled captures (like `fn_id:Ident`) are collected into a `labels` map. The parser emits events for each successfully matched rule.

3. **Semantic Evaluation**: For each matched rule, `eval_rule_semantics` fires `[src/kgf/semantics/eval_semantics.mbt:35-47]`. It first processes `attrs` annotations, then executes `semantics` blocks. These blocks add edges (`declares`, `calls`, `imports`, `moduleDependsOn`) and nodes to the `CodeGraph`, building the knowledge graph that powers all of indexion's analysis features.

## The Registry

The `KGFRegistry` is the runtime container that loads and indexes all spec files `[src/kgf/registry/registry.mbt:7-14]`. It maintains three maps:

- **specs**: language name to full `KGFSpec` object
- **ext_to_lang**: file extension to language name (e.g., `.ts` -> `typescript`)
- **lang_to_doc_spec**: language to its documentation-specific spec variant (e.g., `typescript` -> `typescript-doc`)

Loading is recursive -- `KGFRegistry::load_from_dir` walks the `kgfs/` directory tree, parses every `.kgf` file, and registers it `[src/kgf/registry/registry.mbt:24-55]`. When indexion encounters a source file, it calls `detect_from_path` which tries filename-based patterns first (e.g., `moon.pkg`), then falls back to extension matching `[src/kgf/registry/registry.mbt:167-190]`.

The registry also aggregates cross-spec information: `get_external_prefixes()` collects all `bare_prefix` values (`npm:`, `pkg:`, `pip:`) so the engine knows which imports are external without hard-coding ecosystem names `[src/kgf/registry/registry.mbt:213-234]`. Similarly, `get_project_markers()` and `get_package_markers()` gather manifest filenames from all specs for project root and package boundary detection `[src/kgf/registry/registry.mbt:241-283]`.

## Supported Languages

The `kgfs/` directory is organized by category:

| Category | Count | Examples |
|----------|-------|---------|
| `programming/` | 25 | C, C++, C#, Dart, Go, Haskell, Java, JavaScript, Kotlin, Lua, MoonBit, OCaml, PHP, Python, Ruby, Rust, Scala, Swift, TypeScript, Zig |
| `project/` | 13 | `package.json`, `Cargo.toml`, `go.mod`, `moon.mod.json`, `pyproject.toml`, `pom.xml` |
| `toy/` | 11 | Base64, JPEG/PNG binary formats, relational text |
| `dsl/` | 9 | CSS, HTML, Markdown, SQL, TOML, `moon.pkg` |
| `natural/` | 4 | English, Japanese, Chinese, Korean |
| `universal.kgf` | 1 | Fallback spec for unknown file types |

In total, 63 spec files cover source code, configuration files, documentation formats, and even binary data. Each programming language spec defines lexer tokens for that language's syntax, grammar rules for its declarations and imports, semantic actions for graph construction, and resolver configuration for its module system.

## Adding a New Language

To add support for a new language, create a `.kgf` file in the appropriate `kgfs/` subdirectory. No engine code changes are required. Here is a minimal template:

```kgf
kgf 0.6
language: mylang
sources: .mylang

=== lex
SKIP /\s+/
TOKEN KW_import  /import\b/
TOKEN KW_fn      /fn\b/
TOKEN Ident      /[a-zA-Z_][a-zA-Z0-9_]*/
TOKEN String     /"([^"\\]|\\.)*"/
TOKEN LBRACE     /\{/
TOKEN RBRACE     /\}/
TOKEN LPAREN     /\(/
TOKEN RPAREN     /\)/
TOKEN SEMI       /;/
TOKEN DOT        /\./

=== grammar
Module -> Item*
Item -> ImportDecl | FnDecl | Other

ImportDecl -> KW_import path:String SEMI?
FnDecl -> KW_fn fn_id:Ident LPAREN RPAREN Body?
Body -> LBRACE BodyContent* RBRACE
BodyContent -> LBRACE BodyContent* RBRACE | Atom
Atom -> Ident | String | KW_fn | KW_import | LPAREN | RPAREN | SEMI | DOT
Other -> Atom

=== attrs
on FnDecl: def fn_id kind=Function

=== semantics
on FnDecl {
  let sym_id = concat($file, "::", $fn_id)
  edge declares from $file to sym_id attrs obj("name", $fn_id, "kind", "Function")
}

on ImportDecl {
  module $path
  edge moduleDependsOn from $file to $resolve($path)
}

=== resolver
relative_prefixes: ./
module_path_style: slash
resolve:
  - ext: .mylang
  - fallback: external:
```

The key steps are:

1. **Define tokens** in the lex section. Put keywords before identifiers. Use SKIP for whitespace and comments.
2. **Write grammar rules** starting from `Module`. Use labeled captures (`fn_id:Ident`) for any value you need in semantic actions.
3. **Add attrs** for declaration shorthand.
4. **Write semantic actions** to emit `declares` edges for definitions and `moduleDependsOn` edges for imports.
5. **Configure the resolver** so import paths can be mapped to files.

Drop the file into `kgfs/programming/` (or `dsl/`, `project/`, etc.) and it will be picked up automatically by the registry on next load. No recompilation needed -- KGF specs are loaded at runtime from the filesystem.

## Architecture Summary

The KGF system achieves language-agnostic code analysis through a clean separation of concerns. The spec files are pure data -- they declare *what* to match and *what graph edges to emit*. The engine code in `src/kgf/` provides the *how*:

- `src/kgf/lexer/` -- regex-based tokenizer
- `src/kgf/peg/` -- PEG parser with recursive and iterative evaluators
- `src/kgf/parser/` -- KGF spec file parser (reads the `.kgf` format itself)
- `src/kgf/semantics/` -- graph construction from parse results
- `src/kgf/resolver/` -- module path resolution
- `src/kgf/registry/` -- spec loading and language detection
- `src/kgf/features/` -- KGF-based feature extraction for downstream consumers

This architecture means that the engine code changes only when new *capabilities* are needed (a new statement type, a new resolution strategy). Adding or improving language support is entirely a matter of editing `.kgf` files.

## See Also

- [[KGF Specifications (kgfs)]] -- the bundled spec files for 63 languages and formats
- [[KGF Engine (src/kgf)]] -- implementation internals of the parsing pipeline
