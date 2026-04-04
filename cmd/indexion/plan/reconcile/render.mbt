///|
fn report_config(config : ReconcileConfig) -> ReconcileReportConfig {
  {
    target_dir: config.target_dir,
    specs_dir: config.specs_dir,
    index_dir: config.index_dir,
    review_results_path: config.review_results_path,
    doc_scope: config.documents.scope_name,
    doc_paths: config.documents.doc_paths,
    doc_specs: config.documents.doc_specs,
    threshold_seconds: config.threshold_seconds,
    max_candidates: config.max_candidates,
    allow_file_fallback: config.allow_file_fallback,
    git_preferred: config.git_preferred,
    mtime_fallback: config.mtime_fallback,
    logical_review_mode: config.logical_review_mode,
  }
}

///|
fn render_aggregate_suggestions(
  buf : StringBuilder,
  report : ReconcileReport,
) -> Unit {
  if report.aggregate_suggestions.length() == 0 {
    return
  }
  buf.write_string("## Suggested Review Groups\n\n")
  for group in report.aggregate_suggestions {
    buf.write_string("### ")
    buf.write_string(group.scope)
    buf.write_string(": `")
    buf.write_string(group.path)
    buf.write_string("` (`")
    buf.write_string(group.status)
    buf.write_string("`)\n\n")
    buf.write_string("- Candidates: ")
    buf.write_string(group.candidate_count.to_string())
    buf.write_string("\n")
    buf.write_string("- Action: `")
    buf.write_string(group.recommended_action)
    buf.write_string("`\n")
    buf.write_string("- Pending logical review: ")
    buf.write_string(group.logical_review_count.to_string())
    buf.write_string("\n")
    buf.write_string("- Symbols: `")
    buf.write_string(group.symbol_names.join("`, `"))
    buf.write_string("`\n")
    if group.doc_paths.length() > 0 {
      buf.write_string("- Docs: `")
      buf.write_string(group.doc_paths.join("`, `"))
      buf.write_string("`\n")
    }
    buf.write_string("\n")
  }
}

///|
fn render_markdown(report : ReconcileReport) -> String {
  let buf = StringBuilder::new()
  buf.write_string("# Reconcile Report\n\n")
  buf.write_string("- Target: `")
  buf.write_string(report.config.target_dir)
  buf.write_string("`\n")
  buf.write_string("- Doc scope: `")
  buf.write_string(report.config.doc_scope)
  buf.write_string("`\n")
  buf.write_string("- Cache hit: `")
  buf.write_string(report.cache_state.cache_hit.to_string())
  buf.write_string("`\n")
  buf.write_string("- Reused candidates: ")
  buf.write_string(report.cache_state.reused_candidates.to_string())
  buf.write_string("\n")
  buf.write_string("- New logical reviews: ")
  buf.write_string(report.summary.new_logical_reviews.to_string())
  buf.write_string("\n")
  buf.write_string("- Symbols: ")
  buf.write_string(report.summary.total_symbols.to_string())
  buf.write_string("\n")
  buf.write_string("- Module-covered symbols: ")
  buf.write_string(report.summary.module_covered_symbols.to_string())
  buf.write_string("\n")
  buf.write_string("- Doc fragments: ")
  buf.write_string(report.summary.total_doc_fragments.to_string())
  buf.write_string("\n")
  buf.write_string("- Candidates: ")
  buf.write_string(report.summary.total_candidates.to_string())
  buf.write_string("\n\n")
  buf.write_string("- Suggested review groups: ")
  buf.write_string(report.summary.total_aggregate_suggestions.to_string())
  buf.write_string(" (module ")
  buf.write_string(report.summary.module_suggestions.to_string())
  buf.write_string(", project ")
  buf.write_string(report.summary.project_suggestions.to_string())
  buf.write_string(")\n")
  buf.write_string("- Vocabulary divergences: ")
  buf.write_string(report.summary.vocabulary_divergence_count.to_string())
  buf.write_string("\n\n")
  render_vocabulary_divergences_md(buf, report)
  if report.candidates.length() == 0 {
    if report.vocabulary_divergences.length() == 0 {
      buf.write_string("No suggestion candidates found.\n")
    }
    return buf.to_string()
  }
  render_aggregate_suggestions(buf, report)
  buf.write_string("## Candidates\n\n")
  for candidate in report.candidates {
    buf.write_string("### ")
    buf.write_string(candidate.code_anchor.name)
    buf.write_string(" (`")
    buf.write_string(candidate.status)
    buf.write_string("`)\n\n")
    buf.write_string("- Symbol: `")
    buf.write_string(candidate.symbol_id)
    buf.write_string("`\n")
    buf.write_string("- Code: `")
    buf.write_string(candidate.code_anchor.module_path)
    buf.write_string("`\n")
    match candidate.doc_anchor {
      Some(doc_anchor) => {
        buf.write_string("- Doc: `")
        buf.write_string(doc_anchor.path)
        buf.write_string("` (`")
        buf.write_string(doc_anchor.spec)
        buf.write_string("`)\n")
        buf.write_string("- Fragment: ")
        buf.write_string(doc_anchor.preview)
        buf.write_string("\n")
      }
      None => ()
    }
    buf.write_string("- Relation: `")
    buf.write_string(candidate.time_relation)
    buf.write_string("`\n")
    buf.write_string("- Action: `")
    buf.write_string(candidate.recommended_action)
    buf.write_string("`\n")
    buf.write_string("- Logical review: `")
    buf.write_string(candidate.logical_review_status)
    buf.write_string("`\n")
    buf.write_string("- Match: `")
    buf.write_string(candidate.evidence.match_kind)
    buf.write_string("`")
    if candidate.evidence.matched_terms.length() > 0 {
      buf.write_string(" via `")
      buf.write_string(candidate.evidence.matched_terms.join("`, `"))
      buf.write_string("`")
    }
    buf.write_string("\n\n")
  }
  if report.logical_reviews.length() > 0 {
    buf.write_string("## Logical Review Queue\n\n")
    for task in report.logical_reviews {
      buf.write_string("- `")
      buf.write_string(task.review_key)
      buf.write_string("` -> `")
      buf.write_string(task.candidate_id)
      buf.write_string("` (`")
      buf.write_string(task.recommended_action)
      buf.write_string("`)")
      if task.reused {
        buf.write_string(" reused")
      }
      buf.write_string("\n")
    }
    buf.write_string("\n")
  }
  buf.to_string()
}

///|
fn render_github_issue(report : ReconcileReport) -> String {
  let buf = StringBuilder::new()
  buf.write_string("# Reconcile drift report\n\n")
  buf.write_string("Detected ")
  buf.write_string(report.summary.total_candidates.to_string())
  buf.write_string(" suggestion candidates requiring review.\n\n")
  if report.aggregate_suggestions.length() > 0 {
    buf.write_string("## Suggested review groups\n\n")
    for group in report.aggregate_suggestions {
      buf.write_string("- [ ] ")
      buf.write_string(group.scope)
      buf.write_string(" `")
      buf.write_string(group.path)
      buf.write_string("` -> `")
      buf.write_string(group.recommended_action)
      buf.write_string("` (")
      buf.write_string(group.candidate_count.to_string())
      buf.write_string(" symbols)\n")
    }
    buf.write_string("\n")
  }
  for candidate in report.candidates {
    buf.write_string("- [ ] `")
    buf.write_string(candidate.code_anchor.name)
    buf.write_string("` in `")
    buf.write_string(candidate.code_anchor.module_path)
    buf.write_string("` -> `")
    buf.write_string(candidate.recommended_action)
    buf.write_string("`")
    match candidate.doc_anchor {
      Some(anchor) => {
        buf.write_string(" (`")
        buf.write_string(anchor.path)
        buf.write_string("`)")
      }
      None => ()
    }
    buf.write_string("\n")
  }
  buf.write_string("\n")
  render_vocabulary_divergences_issue(buf, report)
  buf.to_string()
}

///|
fn render_vocabulary_divergences_md(
  buf : StringBuilder,
  report : ReconcileReport,
) -> Unit {
  if report.vocabulary_divergences.length() == 0 {
    return
  }
  buf.write_string("## Vocabulary Divergence\n\n")
  buf.write_string(
    "Source code contains terms not found in co-located documentation.\n\n",
  )
  buf.write_string("| Module | Document | Distance | Gap Terms |\n")
  buf.write_string("|--------|----------|----------|----------|\n")
  for d in report.vocabulary_divergences {
    buf.write_string("| `")
    buf.write_string(d.module_path)
    buf.write_string("` | `")
    buf.write_string(d.doc_path)
    buf.write_string("` | ")
    buf.write_string(@common.format_percent(d.cosine_distance))
    buf.write_string(" | `")
    let limit = if d.gap_terms.length() < 5 { d.gap_terms.length() } else { 5 }
    let shown : Array[String] = []
    for i = 0; i < limit; i = i + 1 {
      shown.push(d.gap_terms[i])
    }
    buf.write_string(shown.join("`, `"))
    buf.write_string("`")
    if d.gap_terms.length() > 5 {
      buf.write_string(" (+")
      buf.write_string((d.gap_terms.length() - 5).to_string())
      buf.write_string(")")
    }
    buf.write_string(" |\n")
  }
  buf.write_string("\n")
}

///|
fn render_vocabulary_divergences_issue(
  buf : StringBuilder,
  report : ReconcileReport,
) -> Unit {
  if report.vocabulary_divergences.length() == 0 {
    return
  }
  buf.write_string("## Vocabulary divergence\n\n")
  for d in report.vocabulary_divergences {
    buf.write_string("- [ ] `")
    buf.write_string(d.module_path)
    buf.write_string("` (distance: ")
    buf.write_string(@common.format_percent(d.cosine_distance))
    buf.write_string(") -- missing: `")
    let limit = if d.gap_terms.length() < 5 { d.gap_terms.length() } else { 5 }
    let shown : Array[String] = []
    for i = 0; i < limit; i = i + 1 {
      shown.push(d.gap_terms[i])
    }
    buf.write_string(shown.join("`, `"))
    buf.write_string("`\n")
  }
  buf.write_string("\n")
}

///|
fn render_output(report : ReconcileReport, format : String) -> String {
  match format {
    "json" => report.to_json().stringify(indent=2)
    "github-issue" => render_github_issue(report)
    _ => render_markdown(report)
  }
}
