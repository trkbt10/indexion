///|
/// Convert reconcile results to the `@coverage` IR.
///
/// Semantics — what "covered" means for `plan reconcile`:
///
/// - Each `ReconcileCandidate` → finding anchored at the candidate's
///   `code_anchor.module_path` (used as the file path) with the symbol
///   name attached. The candidate represents a code symbol whose
///   documentation is out of date or missing, so it fails the check.
/// - Each `VocabularyDivergence` → finding anchored at the divergence's
///   `module_path`, with the gap-term count exposed via the name.
///
/// Line numbers are not carried on either of those records; we anchor at
/// line 1 as the conventional "file-level finding" marker, the same way
/// `plan refactor`'s function-duplicate path does.
///
/// Files with no findings do not appear — this is the static-analysis
/// convention (findings = uncovered).
pub fn to_coverage_report(
  source_root : String,
  report : ReconcileReport,
) -> @coverage.CoverageReport {
  let b = @coverage.ScanBuilder::new()
  for candidate in report.candidates {
    b.record(
      candidate.code_anchor.module_path,
      1,
      name=candidate.code_anchor.name,
      is_function=candidate.code_anchor.name.length() > 0,
    )
  }
  for d in report.vocabulary_divergences {
    b.record(d.module_path, 1)
  }
  b.to_coverage_report("indexion-plan-reconcile", source_root)
}
