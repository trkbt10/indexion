///|
/// Convert unwrap analysis results to the `@coverage` IR.
///
/// Semantics — what "covered" means for `plan unwrap`:
///
/// - Each function inside the scanned set is one ScanUnit.
/// - A function `passes` (hits=1) iff it is *not* flagged as a wrapper.
/// - A flagged wrapper `fails` (hits=0) — it is a finding the developer
///   should address by removing the wrapper.
///
/// This gives a meaningful coverage rate: `(clean functions) / (all
/// functions)`. As wrappers are removed, the rate climbs to 100%.

///|
/// Build a CoverageReport from the unwrap scan.
pub fn to_coverage_report(
  source_root : String,
  files : Array[(String, String)],
  wrappers : Array[@kgf_features.ProxyFunction],
  registry : @kgf_registry.KGFRegistry?,
) -> @coverage.CoverageReport {
  // Index wrappers by file → (line → name). Indexing is what lets us
  // mark a function "failed" without re-iterating wrappers per function.
  let wrappers_by_file : Map[String, Map[Int, String]] = {}
  for w in wrappers {
    let line_map = match wrappers_by_file.get(w.file) {
      Some(m) => m
      None => {
        let m : Map[Int, String] = {}
        wrappers_by_file.set(w.file, m)
        m
      }
    }
    line_map.set(w.line, w.name)
  }
  let b = @coverage.ScanBuilder::new()
  for file in files {
    let (path, content) = file
    // Always create the ScanFile so clean files appear in the report.
    ignore(b.ensure_file(path))
    // Extract every function declaration in the file (visibility=All so
    // private wrappers count too). PubDeclaration carries source `line`
    // directly, no token-to-line bookkeeping needed.
    let (decls, _) = @kgf_declarations.extract_declarations(
      content,
      path,
      registry,
      visibility=All,
    )
    let line_map = wrappers_by_file.get(path).unwrap_or({})
    for d in decls {
      if d.category != "function" {
        continue
      }
      let is_wrapper = line_map.contains(d.line)
      b.add_unit(
        path,
        @coverage.ScanUnit::new(
          d.line,
          !is_wrapper,
          name=d.name,
          is_function=true,
        ),
      )
    }
  }
  b.to_coverage_report("indexion-plan-unwrap", source_root)
}
