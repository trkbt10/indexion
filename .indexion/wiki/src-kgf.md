# src/kgf -- KGF Engine (Knowledge Graph Framework)

The KGF engine is the language-agnostic core of indexion. Instead of hard-coding language-specific parsing logic, indexion uses declarative KGF spec files (`.kgf`) that define tokens, grammar rules, semantic actions, and module resolution for each supported language. The engine processes these specs through a pipeline: **lexer** (tokenization via pattern matching), **PEG parser** (grammar-driven AST construction), **semantics evaluator** (CodeGraph generation), and **resolver** (module path resolution).

Supporting subsystems include the **registry** (maps file extensions to specs), **toolkit** (caches derived artifacts like lexers and feature sets per language), **features** (high-level language-agnostic queries like public declaration extraction and function extraction), **preprocess** (FST-based source transforms), **manage** (download/install KGF specs from remote), **CAS** (content-addressable storage for incremental builds), and **fixtures** (test helpers).

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
    registry_pkg --> toolkit_pkg["toolkit: LanguageToolkit cache"]
    lexer_pkg --> toolkit_pkg
    toolkit_pkg --> features_pkg

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
| `lexer/` | Tokenizer driven by `TokenDef` patterns. `Lexer::tokenize(input)` produces `Array[Tok]`. Includes `LexerBuilder` fluent API. Pattern matching (`MatchResult`, `CapturedMatch`, `CompiledPattern`) is provided by the `regexp` dependency. Utility functions: `compile_pattern()`, `match_pattern()`, `find_pattern_captures()`, `matches_at()`, `build_input_chars()` |
| `parser/` | Parses `.kgf` spec files into `KGFSpec`. Header-only fast parsing via `parse_kgf_header()`. Lex section parsing via `parse_lex()`. Types: `KGFHeader`, `LexResult` |
| `peg/` | PEG (Parsing Expression Grammar) engine. `Node` enum for AST, `CompiledNode` for optimized matching, `PEG::new()` / `build_peg(spec)`. Expression parser via `parse_expr(s)`. Iterator-based evaluation via `run_parse_iter()` / `run_parse_filtered_iter()` |
| `semantics/` | Evaluates semantic actions against parse trees to build `CodeGraph`. `eval_semantics()`, `eval_rule_semantics()`, `eval_attrs()`, `eval_rule_attrs()`. Uses `Env` (variable bindings) and `SemEvalCtx` (graph, scope stack, counters) |
| `resolver/` | Module path resolution using `ResolverSpec` chains. `resolve_module()`, `resolve_module_cached()`. Path utilities: `join_path()`, `dirname()`, `basename()`, `normalize_path()`, `relative_path()`. Alias support via `apply_aliases()` |
| `registry/` | `KGFRegistry` maps file extensions to `KGFSpec` instances. Supports loading from directory, extension lookup, language detection, project/package marker collection, and ignore pattern aggregation |
| `features/` | High-level language-agnostic API. `load_registry()`, `extract_pub_declarations()`, `count_pub_declarations()`, `tokenize_source()`, `extract_doc_map()`. Function extraction: `extract_functions()`, `extract_function_trees()`, `tokens_to_tree_node()` with `ExtractedFunction` type. Proxy function detection: `detect_proxy_functions()`, `detect_proxy_functions_from_file()`, `find_call_sites()`, `apply_edits()`, `delete_lines()` |
| `toolkit/` | Caching layer over KGFSpec-derived artifacts. `LanguageToolkit` eagerly builds a Lexer, identifier/vocabulary/keyword sets from a spec. `ToolkitRegistry` wraps a `KGFRegistry` and caches `LanguageToolkit` instances per language for zero-cost repeated access |
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
| `MatchResult` | `regexp` (re-exported via `lexer`) | Result of pattern matching: `success(end_pos, text)` or `failure()` |
| `KGFRegistry` | `registry` | Maps extensions to specs; provides language detection and marker queries |
| `Env` | `semantics` | Variable bindings environment for semantic evaluation |
| `SemEvalCtx` | `semantics` | Evaluation context: graph, scope stack, resolution cache, counters |
| `ScopeEntry` | `semantics` | Scope entry with value and type maps |
| `PubDeclaration` | `features` | Extracted public declaration with name, kind, line number |
| `ExtractedFunction` | `features` | Extracted function with token range (name, start, end, file, tokens) for similarity analysis |
| `ProxyFunction` | `features` | Detected proxy/wrapper function for unwrap analysis |
| `UnwrapEdit` | `features` | Edit instruction for removing proxy functions |
| `KGFHeader` | `parser` | Fast header-only parse result: language name and source extensions |
| `LexResult` | `parser` | Parsed lex section result: token definitions and keyword classification |
| `LanguageToolkit` | `toolkit` | Cached runtime artifacts derived from a KGFSpec (lexer, identifier/vocabulary/keyword sets) |
| `ToolkitRegistry` | `toolkit` | Wraps KGFRegistry and caches LanguageToolkit instances per language |
| `CapturedMatch` | `lexer` (via `regexp`) | Regex capture group match result with text and position |
| `CompiledPattern` | `regexp` | Pre-compiled regex pattern for repeated matching (`pub(all)` with private fields). Used by `compile_pattern()` for caching compiled regex state |
| `CaptureState` | `regexp` | Mutable capture group state for tracking during matching. Methods: `new(count)`, `set(index, start, end)`, `reset(index)`, `get_group_text(index, input_chars)` |
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
| `build_line_func_map(content, path, registry)` | Build a `Map[Int, String]` mapping line numbers to enclosing function names |
| `tokenize_files_with_kgf(files, registry)` | Tokenize multiple files using KGF registry, returning `(token_lists, total_tokens)` |
| `extract_functions(content, file, registry)` | Extract functions as `ExtractedFunction` via KGF grammar pipeline |
| `extract_function_trees(content, file, tokens, registry, spec~)` | Extract functions and convert to `TreeNode` for APTED comparison |
| `tokens_to_tree_node(tokens, start, end, spec~)` | Convert token slice to `TreeNode` using bracket structure |
| `ExtractedFunction::new(name, start, end, file, tokens)` | Construct an `ExtractedFunction` from name, line range, file path, and token slice |
| `ExtractedFunction::get_name(self)` | Get the function name |
| `ExtractedFunction::get_start(self)` | Get the start token index |
| `ExtractedFunction::get_end(self)` | Get the end token index (exclusive) |
| `ExtractedFunction::get_file(self)` | Get the source file path |
| `ExtractedFunction::token_count(self)` | Get the number of tokens in the function body |
| `ExtractedFunction::qualified_name(self)` | Get `file::name` qualified name for display |
| `detect_proxy_functions(content, path, registry)` | Detect trivial wrapper functions |
| `detect_proxy_functions_from_file(content, path, registry)` | Convenience variant: detect proxies from file content |
| `find_call_sites(wrapper_name, delegate_target, tokens, file, spec~)` | Find call sites of a wrapper and generate replacement edits |
| `apply_edits(content, edits)` | Apply character-offset edits to source content (back-to-front) |
| `delete_lines(content, start_line, end_line)` | Delete line range from content (1-indexed, inclusive) |

### Lexer

| Function | Description |
|----------|-------------|
| `Lexer::new(tokens)` | Create lexer from token definitions |
| `Lexer::tokenize(input)` | Tokenize input string |
| `lexer()` | Convenience function returning a new `LexerBuilder` |
| `LexerBuilder::new()` | Create a new fluent lexer builder |
| `LexerBuilder::token(name, pattern, skip~, flags~)` | Add a token definition to the builder |
| `LexerBuilder::skip(name, pattern)` | Add a skip token definition |
| `LexerBuilder::build()` | Build a `Lexer` from accumulated definitions |
| `compile_pattern(pattern, case_insensitive~)` | Compile a regex pattern into `CompiledPattern?` for repeated matching (from `regexp`) |
| `match_pattern(pattern, input, pos, case_insensitive~)` | Match a pattern at a position |
| `match_compiled_end_pos_with_chars(compiled, input_chars, pos)` | Match a compiled pattern against pre-built char array, returning end position (from `regexp`) |
| `find_pattern_captures(pattern, input, case_insensitive~)` | Find all regex capture group matches |
| `matches_at(pattern, input, pos, case_insensitive~)` | Check if pattern matches at a position (bool) |
| `build_input_chars(input)` | Convert input string to `Array[Char]` for compiled pattern matching (from `regexp`) |

### KGF Spec Parser

| Function | Description |
|----------|-------------|
| `parse_kgf(text)` | Parse a full KGF document into `KGFSpec?`. Eagerly parses header/features/resolver/ignore; defers heavy sections (lex, grammar, attrs, semantics, preprocess) for lazy parsing |
| `parse_kgf_header(text)` | Fast header-only parsing returning `KGFHeader` (language + sources) for filtering without full parse |
| `parse_lex(text)` | Parse a lex section into `LexResult` (token definitions + keyword classification) |
| `parse_attrs(text)` | Parse an attrs section into `Map[String, Array[AttrAction]]` |
| `parse_rules(text)` | Parse a grammar section into `Map[String, RuleDef]` |
| `parse_semantics(text)` | Parse a semantics section into `Map[String, Array[SemOnBlock]]?` |
| `parse_resolver(text)` | Parse a resolver section into `ResolverSpec` |
| `parse_resolver_with_sources(text)` | Parse resolver with pre-supplied source extensions |
| `parse_preprocess_fst(text)` | Parse a preprocess section into `Array[PreprocessFstSpec]?` |
| `KGFHeader::get_language(self)` | Get the language name from the header |
| `KGFHeader::get_sources(self)` | Get the source file extensions from the header |
| `LexResult::get_tokens(self)` | Get the parsed token definitions |
| `LexResult::get_keyword_kinds(self)` | Get the keyword classification map (token kind to `Bool`) |

#### Parser Utilities (`parser/utils.mbt`)

| Function | Description |
|----------|-------------|
| `split_lines(text)` | Split text by newlines |
| `is_whitespace(c)` | Check if character is whitespace |
| `is_digit(c)` | Check if character is a digit |
| `is_ident_start(c)` | Check if character can start an identifier |
| `is_ident_char(c)` | Check if character is valid in an identifier |
| `find_substring(text, needle)` | Find first occurrence of needle in text |
| `find_char(text, start, c)` | Find first occurrence of character from position |
| `starts_with(text, prefix)` | Check if text starts with prefix |
| `starts_with_at(text, pos, prefix)` | Check if text starts with prefix at position |
| `trim_str(text)` | Trim leading and trailing whitespace |
| `parse_list(s)` | Parse comma-separated list into array |
| `substr(text, start, end)` | Extract substring by index range |
| `substr_from(text, start)` | Extract substring from position to end |
| `char_at(text, pos)` | Get character at position |

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

### Toolkit

| Function | Description |
|----------|-------------|
| `LanguageToolkit::from_spec(spec)` | Build a toolkit from a KGFSpec; eagerly computes all derived artifacts |
| `LanguageToolkit::get_spec()` | Access the underlying KGFSpec |
| `LanguageToolkit::get_lexer()` | The compiled lexer (built once from spec tokens) |
| `LanguageToolkit::get_identifier_set()` | Token kinds that represent identifiers (e.g. Ident, TypeIdent) |
| `LanguageToolkit::get_vocabulary_set()` | Token kinds for vocabulary sub-tokenization (doc comments, strings) |
| `LanguageToolkit::get_allowed_keywords()` | Keywords allowed in proxy function bodies (function_keyword + self_keyword) |
| `LanguageToolkit::get_qualifier_separators()` | Qualifier separator token kinds (DOT, DCOLON, SCOPE, etc.) |
| `LanguageToolkit::get_self_keywords()` | Self-keyword token kinds (KW_self, KW_this, etc.) |
| `LanguageToolkit::tokenize(content)` | Tokenize source content using the cached lexer |
| `LanguageToolkit::preprocess_and_tokenize(content)` | Apply spec preprocessing then tokenize |
| `LanguageToolkit::preprocess(content)` | Apply spec preprocessing only (returns unchanged if no preprocess section) |
| `LanguageToolkit::is_identifier(kind)` | Check if a token kind is an identifier |
| `LanguageToolkit::is_keyword(kind)` | Check if a token kind is a keyword |
| `ToolkitRegistry::new(registry)` | Create a ToolkitRegistry from a KGFRegistry |
| `ToolkitRegistry::get_registry()` | Access the underlying KGFRegistry |
| `ToolkitRegistry::get(lang)` | Get the LanguageToolkit for a language name (builds and caches on first access) |
| `ToolkitRegistry::for_path(path)` | Detect language from file path and return the corresponding toolkit |
| `ToolkitRegistry::tokenize(content, path)` | Tokenize source content for a file path (preprocess + tokenize) |

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
