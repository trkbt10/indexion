# coverage

Coverage-report **IR** for indexion's `plan` commands.

This package holds the data shapes only — it does not produce any output
format itself. Format renderers live in their own packages under
`src/formats/`:

| Format     | Package                  | Renderer            |
|------------|--------------------------|---------------------|
| lcov.info  | `src/formats/lcov`       | `render_lcov`       |
| coverage.xml (Cobertura) | `src/formats/cobertura` | `render_cobertura` |

CLI dispatch (mapping a `--format=…` string to the right renderer) lives
in `cmd/indexion/common/coverage_format.mbt` — keeping that helper at the
CLI layer avoids a cycle (each renderer imports `@coverage`).

## IR

- **`CoverageReport`** — top-level report (`test_name`, `source_root`, `files`, `timestamp`).
- **`FileCoverage`** — one source file (`path`, `pkg`, `lines`, `functions`, `branches`).
- **`LineHit`** — `{ line, hits }`. `hits == 0` means uncovered.
- **`FunctionHit`** — `{ line, name, hits }`.
- **`BranchHit`** — `{ line, block, branch, taken }`. `taken == -1` renders as lcov's `-`.
- **`CoverageTotals`** — aggregated stats; produced via `FileCoverage::totals`, `CoverageReport::totals`, or `aggregate_totals(files)`.

## ScanResult — measurement-plan bridge

For plan commands whose semantics is "for each scanned unit, pass or
fail", build a `ScanResult` instead of a raw `CoverageReport`. The
projection rules (max-hits dedup per line, FunctionHit emission, etc.)
live in one place:

```moonbit
let scan = @coverage.ScanResult::new("indexion-plan-unwrap", "/repo")
let sf = @coverage.ScanFile::new("src/foo.mbt", pkg="src")
sf.add(@coverage.ScanUnit::new(42, passed=true, name="bar", is_function=true))
sf.add(@coverage.ScanUnit::new(50, passed=false, name="wrap", is_function=true))
scan.add_file(sf)
let report = scan.to_coverage_report()
```

## Producers

- `plan documentation --format=lcov|cobertura`
  Each public declaration → ScanUnit; `passed = item.has_doc`.
- `plan unwrap --format=lcov|cobertura`
  Each function → ScanUnit; `passed = !is_wrapper`.
- `plan refactor --format=lcov|cobertura`
  Findings (duplicate blocks, function duplicates, magic strings) →
  failing ScanUnits.

## TODO

The `plan` commands currently keep their markdown / json / text / github-
issue renderers inline (`cmd/indexion/plan/<plan>/render*.mbt`). Once
those renderers grow shared IR (or duplicate logic across plans), they
should migrate into per-format packages alongside `lcov` and `cobertura`:

- `src/formats/markdown/`
- `src/formats/json/`
- `src/formats/text/`
- `src/formats/github_issue/`

This keeps `src/formats/[format]` as a strict one-package-per-output-
format directory.
