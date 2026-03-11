## Output

The primary output is a `ReconcileReport` with `config`, `summary`, `aggregate_suggestions`, `candidates`, `logical_reviews`, `skipped`, `used_specs`, and `cache_state`.

Rendered formats:

- `json`: full machine-readable report with config, summary, aggregate review groups, candidates, logical review queue, cache state, and used specs.
- `md`: compact review document for humans.
- `github-issue`: checklist-style issue body for manual follow-up.

Candidate statuses currently emitted are:

- `missing_doc`: no external document fragment matched a symbol, and no higher-level module documentation covered its source file.
- `stale_doc`: implementation appears newer than the mapped document fragment.
- `review_mapping`: only a weak heuristic match was found.
- `review_both`: a weak or ambiguous match still requires manual judgment. Strong direct matches are not escalated just because the document is newer.

These statuses are suggestion classes. They drive review prioritization and queue reuse; they do not prove semantic truth.

Notable summary fields:

- `module_covered_symbols`: symbols that were not matched directly, but were suppressed from `missing_doc` because the surrounding module was covered by higher-level documentation.
- `total_aggregate_suggestions`, `module_suggestions`, `project_suggestions`: grouped review entry points that compress many symbol candidates into a smaller set of module and project review tasks.
- Aggregate suggestions are computed from the full mechanical candidate set before `max_candidates` trimming, so high-volume packages still surface accurate hotspots.
- If project/package docs already exist but symbol-level matching is too weak, `reconcile` may emit only aggregate `missing_doc` suggestions for that project instead of repeating helper-level symbol rows.

Index state is persisted under the reconcile index directory:

- `manifest.json`: source fingerprint, review hash, and indexed record metadata.
- `report.json`: cached last report for cache hits.
- `records.db`: VCDB-backed candidate and logical review index.

`index.json` is treated as stale leftover output and is cleaned up during save.
