# src/kgf -- KGF Engine (Knowledge Graph Framework)

The KGF engine is the language-agnostic core of indexion. Instead of hard-coding language-specific parsing logic, indexion uses declarative KGF spec files (`.kgf`) that define tokens, grammar rules, semantic actions, and module resolution for each supported language. The engine processes these specs through a pipeline: **lexer** (tokenization via pattern matching), **PEG parser** (grammar-driven AST construction), **semantics evaluator** (CodeGraph generation), and **resolver** (module path resolution).

Supporting subsystems include the **registry** (maps file extensions to specs), **features** (high-level language-agnostic queries like public declaration extraction), **preprocess** (FST-based source transforms), **manage** (download/install KGF specs from remote), **CAS** (content-addressable storage for incremental builds), and **fixtures** (test helpers).

## Architecture

```mermaid
graph TD
    spec[".kgf spec file"] --> parser_pkg["parser: parse spec"]
    parser_pkg --> types_pkg["types: KGFSpec"]

    types_pkg --> lexer_pkg["lexer: tokenize source"]
    types_pkg --> peg_pkg["peg: PEG parser"]
    types_pkg --> semantics_pkg["semantics: eval to CodeGraph"]
    types_pkg --> resolver_pkg["resolver: module resolution"]
    types_pkg --> preprocess_pkg["preprocess: FST transforms"]

    lexer_pkg -->|tokens| peg_pkg
    peg_pkg -->|parse tree| semantics_pkg
    semantics_pkg -->|CodeGraph| graph["graph.CodeGraph"]
    resolver_pkg -->|file paths| semantics_pkg

    types_pkg --> registry_pkg["registry: KGFRegistry"]
    registry_pkg --> features_pkg["features: high-level API"]
    registry_pkg --> manage_pkg["manage: install/update"]

    features_pkg -->|"extract_pub_declarations()"| consumer[CLI commands]

    subgraph cas
        hash["cas/hash"]
        cas_types["cas/types"]
        manifest["cas/manifest"]
        assembler["cas/assembler"]
        store["cas/store"]
    end
```

## Subpackages

| Subpackage | Description |
|------------|-------------|
| `types/` | Core type definitions: `KGFSpec`, `TokenDef`, `Tok`, `RuleDef`, `AttrAction`, `ResolverSpec`, `SemExpr`, `SemStmt`, `SemOnBlock`, `PreprocessFstSpec` |
| `lexer/` | Tokenizer driven by `TokenDef` patterns. `Lexer::tokenize(input)` produces `Array[Tok]`. Includes `LexerBuilder` fluent API and `MatchResult`-based pattern matcher |
| `parser/` | Parses `.kgf` spec files into `KGFSpec`. Functions: `parse_rules(text)`, `parse_attrs(text)` |
| `peg/` | PEG (Parsing Expression Grammar) engine. `Node` enum for AST, `CompiledNode` for optimized matching, `PEG::new()` / `build_peg(spec)`. Expression parser via `parse_expr(s)`. Iterator-based evaluation via `run_parse_iter()` / `run_parse_filtered_iter()` |
| `semantics/` | Evaluates semantic actions against parse trees to build `CodeGraph`. `eval_semantics()`, `eval_rule_semantics()`, `eval_attrs()`, `eval_rule_attrs()`. Uses `Env` (variable bindings) and `SemEvalCtx` (graph, scope stack, counters) |
| `resolver/` | Module path resolution using `ResolverSpec` chains. `resolve_module()`, `resolve_module_cached()`. Path utilities: `join_path()`, `dirname()`, `basename()`, `normalize_path()`, `relative_path()`. Alias support via `apply_aliases()` |
| `registry/` | `KGFRegistry` maps file extensions to `KGFSpec` instances. Supports loading from directory, extension lookup, language detection, project/package marker collection, and ignore pattern aggregation |
| `features/` | High-level language-agnostic API. `load_registry()`, `extract_pub_declarations()`, `count_pub_declarations()`, `tokenize_source()`, `extract_doc_map()`. Also proxy function detection: `detect_proxy_functions()`, `apply_edits()` |
| `preprocess/` | FST-based source preprocessing. `compile_fst(spec)` compiles an FST spec, `run_fst(fst, input)` transforms source text. `apply_preprocess()` chains multiple FSTs |
| `manage/` | KGF spec lifecycle management. `install_kgfs_from_dir()`, `install_single_kgf()`, `update_kgfs()`, `add_kgf()`. Native-only (stub for wasm/js) |
| `fixtures/` | Test helpers for locating fixture and KGF spec directories |
| `cas/` | Content-addressable storage for incremental analysis (types, hashing, manifests, assembly, storage) |

## Key Types

| Type | Subpackage | Description |
|------|------------|-------------|
| `KGFSpec` | `types` | Complete spec: language, tokens, rules, attrs, resolver, semantics, preprocess, features |
| `TokenDef` | `types` | Token definition with name, pattern, skip flag, and optional flags |
| `Tok` | `types` | A produced token with kind, text, value, and position |
| `RuleDef` | `types` | Grammar rule with name and PEG expression string |
| `AttrAction` | `types` | Attribute action with kind and parameters |
| `ResolverSpec` | `types` | Module resolution config: sources, prefixes, resolve chain, markers |
| `ResolveStep` | `types` | Single step in a resolve chain (exact, manifest, marker, index, ext, sibling, ancestors, fallback) |
| `ResolutionCache` | `types` | Caching layer for resolved module paths with circular dependency detection |
| `ModulePathStyle` | `types` | Enum: `Slash`, `Dot`, `ColonColon` |
| `SemExpr` | `types` | Semantic expression: Str, Num, Bool, Null, Variable, Call, Func |
| `SemStmt` | `types` | Semantic statement: Edge, Bind, Note, Let, For, Mod |
| `SemOnBlock` | `types` | Semantic "on" block: rule name, when condition, then/else statements |
| `PreprocessFstSpec` | `types` | FST specification: states, transitions, character classes |
| `FstAction` | `types` | FST actions: EmitInput, Emit(String), Buf, Flush(Int) |
| `Node` | `peg` | PEG AST node: Sym, Seq, Choice, Star, Plus, Optional, Label, And, Not, Empty |
| `CompiledNode` | `peg` | Optimized PEG node for fast matching |
| `PEG` | `peg` | Compiled PEG grammar with tokens, AST map, and attributes |
| `Lexer` | `lexer` | Tokenizer instance built from `TokenDef` array |
| `LexerBuilder` | `lexer` | Fluent builder for constructing a Lexer |
| `MatchResult` | `lexer` | Result of pattern matching: success with end position, or failure |
| `KGFRegistry` | `registry` | Maps extensions to specs; provides language detection and marker queries |
| `Env` | `semantics` | Variable bindings environment for semantic evaluation |
| `SemEvalCtx` | `semantics` | Evaluation context: graph, scope stack, resolution cache, counters |
| `ScopeEntry` | `semantics` | Scope entry with value and type maps |
| `PubDeclaration` | `features` | Extracted public declaration with name, kind, line number |
| `ProxyFunction` | `features` | Detected proxy/wrapper function for unwrap analysis |
| `UnwrapEdit` | `features` | Edit instruction for removing proxy functions |
| `ContentHash` | `cas/types` | Content-addressable hash wrapper |
| `ModuleChunk` | `cas/types` | Chunk of a module for incremental storage |
| `CASManifest` | `cas/types` | Manifest mapping modules to content hashes |
| `KgfManageError` | `manage` | Error type for KGF management operations |
| `KgfSpecInfo` | `manage` | Metadata about a KGF spec |
| `CompiledFst` | `preprocess` | Compiled FST ready for execution |

## Public API (Selected)

### Registry

| Function | Description |
|----------|-------------|
| `KGFRegistry::load_from_dir(dir)` | Load all specs from a directory |
| `KGFRegistry::get_spec(lang)` | Get spec by language name |
| `KGFRegistry::get_lang_from_ext(ext)` | Map file extension to language |
| `KGFRegistry::detect_from_path(path)` | Detect language spec from file path |
| `KGFRegistry::get_external_prefixes()` | Get all external package prefixes |
| `KGFRegistry::get_project_markers()` | Get all project marker patterns |
| `KGFRegistry::get_package_markers()` | Get all package marker patterns |
| `KGFRegistry::collect_ignore_patterns()` | Collect ignore patterns from all specs |

### Features (High-Level API)

| Function | Description |
|----------|-------------|
| `load_registry(specs_dir~, target_dir~, target_dirs~)` | Load KGF registry (SoT). `specs_dir="kgfs"` triggers auto-detection |
| `load_registry_or_empty(...)` | Non-Optional version, falls back to empty registry |
| `extract_pub_declarations(content, path, registry)` | Extract public declarations from source |
| `count_pub_declarations(content, path, registry)` | Count public declarations |
| `tokenize_source(content, path, registry)` | Tokenize source file using matched KGF spec |
| `extract_doc_map(tokens)` | Build line-number-to-docstring map from tokens |
| `detect_proxy_functions(content, path, registry)` | Detect trivial wrapper functions |
| `apply_edits(content, edits)` | Apply unwrap edits to source content |

### Lexer

| Function | Description |
|----------|-------------|
| `Lexer::new(tokens)` | Create lexer from token definitions |
| `Lexer::tokenize(input)` | Tokenize input string |
| `match_pattern(pattern, input, pos)` | Match a pattern at a position |

### PEG Parser

| Function | Description |
|----------|-------------|
| `build_peg(spec)` | Build a PEG grammar from a KGFSpec |
| `parse_expr(s)` | Parse a PEG expression string into a Node |
| `run_parse_iter(tokens, peg, start_rule)` | Run PEG parser with iterator-based evaluation |
| `collect_active_rules(spec)` | Collect rules reachable from the start rule |

### Semantics

| Function | Description |
|----------|-------------|
| `eval_semantics(spec, tokens, file_path, ctx)` | Evaluate semantics to build CodeGraph |
| `eval_rule_semantics(rule, labels, ctx)` | Evaluate semantics for a single rule match |
| `eval_expr(expr, env, ctx)` | Evaluate a semantic expression |
| `eval_stmt(stmt, env, ctx)` | Evaluate a semantic statement |

### Resolver

| Function | Description |
|----------|-------------|
| `resolve_module(specifier, from_file, spec, file_resolver)` | Resolve module path from import specifier |
| `resolve_module_cached(specifier, from_file, spec, file_resolver, cache)` | Cached version with circular dependency detection |

## Dependencies (top-level subpackages)

| Package | Used by | Purpose |
|---------|---------|---------|
| `src/core/graph` | `peg`, `semantics`, `cas`, `fixtures` | CodeGraph data model |
| `src/config` | `registry`, `features`, `manage`, `fixtures`, `resolver` | Path resolution, directory detection |
| `src/similarity/apted` | `features` | APTED tree distance (proxy detection) |
| `src/platform` | `manage` | Platform detection for downloads |
| `src/http` | `manage` | HTTP client for spec downloads |
| `moonbitlang/core/json` | `parser`, `peg`, `semantics`, `resolver` | JSON operations |
| `moonbitlang/x/fs` | `registry`, `manage`, `peg`, `fixtures` | Filesystem access |

## See Also

- [Core Concepts](wiki://core-concepts) -- how KGF fits into the overall architecture
- [KGF System](wiki://kgf-system) -- user-facing guide to writing and using KGF specs

> Source: `src/kgf/`
