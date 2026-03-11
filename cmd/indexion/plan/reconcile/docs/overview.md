## Overview

`indexion plan reconcile` detects drift candidates between implementation and documentation.

It builds a code graph from the target directory, extracts code symbols and inline docs, and matches them against external document fragments. Document extraction is KGF-based, so Markdown, plaintext, TOML, and other detectable document specs can participate in the same scan.

Direct symbol-name matches come from KGF feature metadata. Specs can declare `reference_token_kinds`, programming specs can declare `document_symbol_kinds`, and both code and document specs can declare `coverage_token_kinds` for module coverage, so `reconcile` does not need per-format token-kind guesses or command-local symbol-kind whitelists for supported languages.

Matching is symbol-first, then module-scoped. If a README or design section clearly covers a whole module, `reconcile` suppresses per-symbol `missing_doc` noise for that module and reports the coverage in the summary instead.

Code discovery respects KGF ignore patterns, so language-specific test files and generated artifacts can be excluded by the active spec set instead of by command-local suffix rules.

Cross-package behavior is regression-tested with the TypeScript fixture at `fixtures/project/typescript-reconcile`, so package-doc scans are validated against non-MoonBit inputs as well.

The command does not rewrite code or docs. Its job is to produce a mechanically derived report with timestamp evidence, mapping confidence, and a logical review queue for follow-up.

At a high level, the flow is:

1. Discover source files and document files under the target directory.
2. Extract code symbols and document fragments.
3. Match fragments to symbols with symbol-first heuristics and module-scope coverage fallback.
4. Compare git and mtime evidence to classify drift.
5. Persist manifest, report, and DB state to avoid rechecking unchanged candidates.
