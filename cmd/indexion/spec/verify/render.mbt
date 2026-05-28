///|
/// Render the verify report in the requested format.
fn render_output(report : VerifyReport, format : String) -> String {
  if @common.is_coverage_format(format) {
    let coverage_report = verify_to_coverage_report(
      report.config.target_dir, report,
    )
    match @common.render_coverage_format(format, coverage_report) {
      Some(s) => return s
      None => ()
    }
  }
  match format {
    "json" => report.to_json().stringify(indent=2)
    "github-issue" => render_github_issue(report)
    _ => render_markdown(report)
  }
}

///|
/// Convert spec-verify results to the `@coverage` IR.
///
/// Semantics — what "covered" means for `spec verify`:
///
/// - Each `VerifyItem` is one ScanUnit anchored at `spec_symbol.source_path`
///   with the spec's `source_line`.
/// - `status == "matched"` → the spec symbol is found in the
///   implementation → `passed = true` (hits=1).
/// - Any other status (`missing`, `dead`, `drift`) → `passed = false`.
///
/// Unlike the static-analysis-style converters used elsewhere, spec verify
/// has real per-symbol line numbers and a clear pass/fail status on each
/// item, so the coverage rate it produces is a true rate:
/// `matched / spec_symbols`.
fn verify_to_coverage_report(
  source_root : String,
  report : VerifyReport,
) -> @coverage.CoverageReport {
  let b = @coverage.ScanBuilder::new()
  for item in report.items {
    let line = if item.spec_symbol.source_line > 0 {
      item.spec_symbol.source_line
    } else {
      1
    }
    let passed = item.status == "matched"
    let is_ident_kind = item.spec_symbol.kind == "ident"
    b.add_unit(
      item.spec_symbol.source_path,
      @coverage.ScanUnit::new(
        line,
        passed,
        name=item.spec_symbol.identifier,
        is_function=is_ident_kind && item.spec_symbol.identifier.length() > 0,
      ),
    )
  }
  b.to_coverage_report("indexion-spec-verify", source_root)
}

///|
/// Render as markdown.
fn render_markdown(report : VerifyReport) -> String {
  let buf = StringBuilder::new()
  buf.write_string("# Spec Verify Report\n\n")
  buf.write_string("- Spec: ")
  buf.write_string(report.summary.spec_files.to_string())
  buf.write_string(" files\n")
  buf.write_string("- Target: `")
  buf.write_string(report.config.target_dir)
  buf.write_string("` (")
  buf.write_string(report.summary.impl_files.to_string())
  buf.write_string(" files)\n")
  buf.write_string("- Vocabulary distance: ")
  buf.write_string(@common.format_percent(report.summary.cosine_distance))
  buf.write_string("\n")
  buf.write_string("- Gap terms: ")
  buf.write_string(report.summary.gap_count.to_string())
  buf.write_string("\n\n")
  if report.items.length() == 0 {
    buf.write_string("No spec-implementation gaps found.\n")
    return buf.to_string()
  }
  // Group items by kind
  let kinds = collect_unique_kinds(report.items)
  for kind in kinds {
    let kind_items = filter_by_kind(report.items, kind)
    if kind_items.length() == 0 {
      continue
    }
    buf.write_string("## Gap Terms (")
    buf.write_string(kind)
    buf.write_string(")\n\n")
    buf.write_string("| Term | Kind | Evidence |\n")
    buf.write_string("|------|------|----------|\n")
    for item in kind_items {
      buf.write_string("| `")
      buf.write_string(item.spec_symbol.identifier)
      buf.write_string("` | ")
      buf.write_string(item.spec_symbol.kind)
      buf.write_string(" | ")
      buf.write_string(item.evidence.note)
      buf.write_string(" |\n")
    }
    buf.write_string("\n")
  }
  buf.to_string()
}

///|
/// Render as GitHub issue format with checkboxes.
fn render_github_issue(report : VerifyReport) -> String {
  let buf = StringBuilder::new()
  buf.write_string("# Spec Verify Report\n\n")
  buf.write_string("Vocabulary distance: ")
  buf.write_string(@common.format_percent(report.summary.cosine_distance))
  buf.write_string(" — ")
  buf.write_string(report.summary.gap_count.to_string())
  buf.write_string(" spec terms not found in implementation.\n\n")
  if report.items.length() == 0 {
    return buf.to_string()
  }
  buf.write_string("## Gap Terms\n\n")
  for item in report.items {
    buf.write_string("- [ ] **")
    buf.write_string(item.spec_symbol.kind)
    buf.write_string("** `")
    buf.write_string(item.spec_symbol.identifier)
    buf.write_string("` — ")
    buf.write_string(item.evidence.note)
    buf.write_string("\n")
  }
  buf.write_string("\n")
  buf.to_string()
}

///|
/// Filter items by kind.
fn filter_by_kind(
  items : Array[VerifyItem],
  kind : String,
) -> Array[VerifyItem] {
  items.filter(fn(item) { item.spec_symbol.kind == kind })
}

///|
/// Collect unique kind values from items.
fn collect_unique_kinds(items : Array[VerifyItem]) -> Array[String] {
  let seen : Map[String, Bool] = {}
  let result : Array[String] = []
  for item in items {
    let kind = item.spec_symbol.kind
    if !seen.contains(kind) {
      seen[kind] = true
      result.push(kind)
    }
  }
  result
}
