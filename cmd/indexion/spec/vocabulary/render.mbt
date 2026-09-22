///|
fn render_output(report : VocabularyReport, format : String) -> String {
  match format {
    format if format == output_format_json =>
      report.to_json().stringify(indent=2)
    format if format == output_format_markdown => render_markdown(report)
    _ => render_text(report)
  }
}

///|
fn render_text(report : VocabularyReport) -> String {
  let buf = StringBuilder()
  buf.write_string("sources                  : ")
  buf.write_string(report.source_file_count.to_string())
  buf.write_string("\n")
  buf.write_string("targets                  : ")
  buf.write_string(report.target_file_count.to_string())
  buf.write_string("\n")
  buf.write_string("direction                : ")
  buf.write_string(report.direction)
  buf.write_string("\n")
  buf.write_string("required source terms    : ")
  buf.write_string(report.source_required_count.to_string())
  buf.write_string("\n")
  buf.write_string("allowed source terms     : ")
  buf.write_string(report.source_allowed_count.to_string())
  buf.write_string("\n")
  buf.write_string("observed target terms    : ")
  buf.write_string(report.target_observed_count.to_string())
  buf.write_string("\n")
  buf.write_string("report precision issues  : ")
  buf.write_string(report.report_precision_candidate_count.to_string())
  buf.write_string("\n")
  buf.write_string("output noise candidates  : ")
  buf.write_string(report.output_noise_candidate_count.to_string())
  buf.write_string("\n")
  buf.write_string("unresolved raw issues    : ")
  buf.write_string(report.unresolved_issue_count.to_string())
  buf.write_string("\n")
  buf.write_string("missing source terms     : ")
  if direction_checks_missing(report.direction) {
    write_terms_or_none(buf, report.missing_source_terms)
  } else {
    buf.write_string("not checked")
  }
  buf.write_string("\n")
  buf.write_string("target drift terms       : ")
  if direction_checks_drift(report.direction) {
    write_terms_or_none(buf, report.target_drift_terms)
  } else {
    buf.write_string("not checked")
  }
  buf.write_string("\n\n")
  if direction_checks_missing(report.direction) {
    write_assessments(
      buf,
      "missing source assessment",
      report.missing_source_assessments,
    )
  }
  if direction_checks_drift(report.direction) {
    write_assessments(
      buf,
      "target drift assessment",
      report.target_drift_assessments,
    )
  }
  buf.write_string("VOCABULARY CHECK: ")
  buf.write_string(if report.passed { "PASS" } else { "FAIL" })
  buf.write_string("\n")
  buf.to_string()
}

///|
fn render_markdown(report : VocabularyReport) -> String {
  let buf = StringBuilder()
  buf.write_string("# Vocabulary Check\n\n")
  buf.write_string("- Direction: `")
  buf.write_string(report.direction)
  buf.write_string("`\n")
  buf.write_string("- Sources: ")
  buf.write_string(report.source_file_count.to_string())
  buf.write_string("\n")
  buf.write_string("- Targets: ")
  buf.write_string(report.target_file_count.to_string())
  buf.write_string("\n")
  buf.write_string("- Required source terms: ")
  buf.write_string(report.source_required_count.to_string())
  buf.write_string("\n")
  buf.write_string("- Allowed source terms: ")
  buf.write_string(report.source_allowed_count.to_string())
  buf.write_string("\n")
  buf.write_string("- Observed target terms: ")
  buf.write_string(report.target_observed_count.to_string())
  buf.write_string("\n")
  buf.write_string("- Report precision candidates: ")
  buf.write_string(report.report_precision_candidate_count.to_string())
  buf.write_string("\n")
  buf.write_string("- Output noise candidates: ")
  buf.write_string(report.output_noise_candidate_count.to_string())
  buf.write_string("\n")
  buf.write_string("- Unresolved raw issues: ")
  buf.write_string(report.unresolved_issue_count.to_string())
  buf.write_string("\n")
  buf.write_string("- Status: **")
  buf.write_string(if report.passed { "PASS" } else { "FAIL" })
  buf.write_string("**\n\n")
  if direction_checks_missing(report.direction) {
    write_md_terms(buf, "Missing Source Terms", report.missing_source_terms)
    write_md_assessments(
      buf,
      "Missing Source Assessment",
      report.missing_source_assessments,
    )
  }
  if direction_checks_drift(report.direction) {
    write_md_terms(buf, "Target Drift Terms", report.target_drift_terms)
    write_md_assessments(
      buf,
      "Target Drift Assessment",
      report.target_drift_assessments,
    )
  }
  buf.to_string()
}

///|
fn write_terms_or_none(
  buf : StringBuilder,
  values : Array[VocabularyTerm],
) -> Unit {
  if values.length() == 0 {
    buf.write_string("none")
    return
  }
  buf.write_string("[")
  for i, value in values {
    if i > 0 {
      buf.write_string(", ")
    }
    buf.write_string(value.key)
  }
  buf.write_string("]")
}

///|
fn write_assessments(
  buf : StringBuilder,
  title : String,
  values : Array[VocabularyIssueAssessment],
) -> Unit {
  if values.length() == 0 {
    return
  }
  buf.write_string(title)
  buf.write_string(":\n")
  for item in values {
    buf.write_string("  ")
    buf.write_string(item.term.key)
    buf.write_string(" => ")
    buf.write_string(item.classification)
    buf.write_string(" (")
    buf.write_string(item.reason)
    buf.write_string(")")
    if item.evidence_terms.length() > 0 {
      buf.write_string(" via ")
      write_terms_or_none(buf, item.evidence_terms)
    }
    buf.write_string("\n")
  }
  buf.write_string("\n")
}

///|
fn write_md_terms(
  buf : StringBuilder,
  title : String,
  values : Array[VocabularyTerm],
) -> Unit {
  buf.write_string("## ")
  buf.write_string(title)
  buf.write_string("\n\n")
  if values.length() == 0 {
    buf.write_string("_None_\n\n")
    return
  }
  for value in values {
    buf.write_string("- `")
    buf.write_string(value.key)
    buf.write_string("` from `")
    buf.write_string(value.origin)
    buf.write_string("`\n")
  }
  buf.write_string("\n")
}

///|
fn write_md_assessments(
  buf : StringBuilder,
  title : String,
  values : Array[VocabularyIssueAssessment],
) -> Unit {
  buf.write_string("## ")
  buf.write_string(title)
  buf.write_string("\n\n")
  if values.length() == 0 {
    buf.write_string("_None_\n\n")
    return
  }
  for item in values {
    buf.write_string("- `")
    buf.write_string(item.term.key)
    buf.write_string("`: ")
    buf.write_string(item.classification)
    buf.write_string(" / ")
    buf.write_string(item.reason)
    if item.evidence_terms.length() > 0 {
      buf.write_string(" via ")
      for i, evidence in item.evidence_terms {
        if i > 0 {
          buf.write_string(", ")
        }
        buf.write_string("`")
        buf.write_string(evidence.key)
        buf.write_string("`")
      }
    }
    buf.write_string("\n")
  }
  buf.write_string("\n")
}
