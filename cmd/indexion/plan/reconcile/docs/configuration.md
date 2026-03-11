## Configuration

`reconcile` reads `.indexion.toml` first and falls back to `.indexion.json`.

Example TOML:

```toml
[reconcile]
doc_scope = "package-docs"
doc_paths = ["docs/**/*.md", "spec/**/*.toml", "notes/**/*.txt"]
doc_specs = ["markdown", "toml", "plaintext"]
index_dir = ".indexion/reconcile"
review_results_path = ".indexion/reconcile/reviews.json"
threshold_seconds = 60
max_candidates = 200

[reconcile.mapping]
allow_file_fallback = true

[reconcile.output]
default_format = "json"

[reconcile.time]
git_preferred = true
mtime_fallback = true

[reconcile.logical_review]
mode = "queue"
```

Notes:

- Relative `index_dir` and `review_results_path` values are resolved from the target directory or the config file location.
- `doc_scope` applies preset document filters. `package-docs` targets `README.md` and `docs/**/*.md`, `tree-docs` targets `**/README.md` and `**/docs/**/*.md`, and `custom` leaves discovery unconstrained.
- `doc_paths` filters files before fragment extraction. If it is left empty, `reconcile` considers every detectable document spec under the target directory.
- For package-level doc audits, a common setting is `doc_paths = ["README.md", "docs/**/*.md"]` with `doc_specs = ["markdown"]`.
- `doc_specs` filters by detected KGF spec after path filtering.
- `git_preferred = true` uses git history when available, with mtime as fallback.
- `--mtime-only` overrides the time strategy from config.

JSON config supports the same fields under the top-level `reconcile` object.
