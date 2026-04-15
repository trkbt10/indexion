# toolkit

## API

- **`LanguageToolkit`** (Struct) — LanguageToolkit caches all runtime artifacts derived from a KGFSpec.
- **`ToolkitRegistry`** (Struct) — ToolkitRegistry wraps a KGFRegistry and caches LanguageToolkit instances
- **`for_path`** (Function) — Detect language from file path and return the corresponding toolkit.
- **`get_vocabulary_set`** (Function) — Token kinds whose text content should be sub-tokenized for vocabulary
- **`preprocess`** (Function) — Apply preprocessing steps from the spec to content.
- **`get`** (Function) — Get the LanguageToolkit for a language name.
- **`get_allowed_keywords`** (Function) — Keywords allowed in proxy function bodies (function_keyword + self_keyword).
- **`get_lexer`** (Function) — The compiled lexer for this language (built once from spec tokens).
- **`preprocess_and_tokenize`** (Function) — Apply preprocessing steps from the spec to content, then tokenize.
- **`get_identifier_set`** (Function) — Token kinds that represent identifiers (e.g. Ident, TypeIdent).
- **`get_qualifier_separators`** (Function) — Qualifier separator token kinds (DOT, DCOLON, SCOPE, etc.).
- **`get_self_keywords`** (Function) — Self-keyword token kinds (KW_self, KW_this, etc.).
- **`tokenize`** (Function) — Tokenize source content using the cached lexer.
- **`is_identifier`** (Function) — Check if a token kind is an identifier.
- **`is_keyword`** (Function) — Check if a token kind is a keyword.
- **`get_registry`** (Function) — Access the underlying KGFRegistry.
- **`get_spec`** (Function) — Access the underlying KGFSpec.
