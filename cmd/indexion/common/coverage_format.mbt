///|
/// Coverage-format dispatch — single place that maps a `--format=…` string
/// to the matching renderer under `src/formats/`.
///
/// Each plan CLI used to spell out the same `match` for the coverage
/// formats. Routing through `render_coverage_format` collapses that to one
/// call, and adding a future coverage format (e.g. SARIF) only touches
/// this file plus a new `src/formats/<name>/` package.
///
/// The dispatcher lives at the CLI-common layer (not in `src/coverage/`)
/// because depending on the format renderers from inside the coverage
/// package would introduce a cycle: each renderer imports `@coverage`.

///|
/// Coverage-format names recognised by the dispatcher. Listed so CLI help
/// text can stay in sync.
pub let coverage_format_names : Array[String] = ["lcov", "cobertura"]

///|
/// Returns `true` if the given `--format` value resolves to a coverage
/// writer. CLI commands can use this to short-circuit their own format
/// dispatch before falling back to markdown/json/text renderers.
pub fn is_coverage_format(format : String) -> Bool {
  for name in coverage_format_names {
    if name == format {
      return true
    }
  }
  false
}

///|
/// Render a `CoverageReport` in the requested format.
///
/// - `"lcov"`       → `@lcov.render_lcov`
/// - `"cobertura"`  → `@cobertura.render_cobertura`
/// - anything else  → `None`, so callers can fall back without a special
///                    case for "format string didn't match a known
///                    coverage format".
pub fn render_coverage_format(
  format : String,
  report : @coverage.CoverageReport,
) -> String? {
  match format {
    "lcov" => Some(@lcov.render_lcov(report))
    "cobertura" => Some(@cobertura.render_cobertura(report))
    _ => None
  }
}
