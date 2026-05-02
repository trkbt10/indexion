/// Render a `ReconcileReport` as text or JSON.
///
/// JSON serialization is delegated to `derive(ToJson)` on the report
/// types and the standard `Json::stringify(indent=2)` from
/// `moonbitlang/core/json`. Hand-rolled JSON construction is avoided —
/// it tends to subtly disagree with the standard library on edge cases
/// (escaping, number formatting, optional fields) and adds maintenance
/// cost without buying anything.

///|
pub enum ReconcileFormat {
  Text
  Json
} derive(Eq, Show)

///|
pub fn ReconcileFormat::parse(s : String) -> ReconcileFormat {
  match s {
    "json" => Json
    _ => Text
  }
}

///|
pub fn render_report(
  report : ReconcileReport,
  format : ReconcileFormat,
) -> String {
  match format {
    Text => render_text(report)
    Json => report.to_json().stringify(indent=2) + "\n"
  }
}

///|
fn render_text(report : ReconcileReport) -> String {
  let buf = StringBuilder::new()
  buf.write_string("=== indexion story reconcile ===\n")
  buf.write_string(
    "Acts: " +
    report.acts.length().to_string() +
    "  Impl docs: " +
    report.impl_paths.length().to_string() +
    "\n",
  )
  buf.write_string("\n")
  buf.write_string("== Acts (extracted from spec docs) ==\n")
  if report.acts.is_empty() {
    buf.write_string("(no acts extracted)\n")
  } else {
    for a in report.acts {
      buf.write_string(
        "  [" +
        a.source_path +
        " #" +
        a.index.to_string() +
        "] " +
        a.title +
        "\n",
      )
    }
  }
  buf.write_string("\n")
  buf.write_string("== Reconcile candidates ==\n")
  if report.candidates.is_empty() {
    buf.write_string("(no candidates)\n")
  } else {
    for c in report.candidates {
      buf.write_string("\n")
      buf.write_string(
        "Act " + c.act.index.to_string() + ": " + c.act.title + "\n",
      )
      buf.write_string("  source: " + c.act.source_path + "\n")
      match c.best_match {
        Some(m) =>
          buf.write_string(
            "  best:   " +
            m.impl_path +
            " (" +
            format_pct(m.similarity) +
            ")\n",
          )
        None => buf.write_string("  best:   (none above floor)\n")
      }
      if c.runner_ups.length() > 0 {
        buf.write_string("  also:   ")
        for i, r in c.runner_ups {
          if i > 0 {
            buf.write_string(", ")
          }
          buf.write_string(
            r.impl_path + " (" + format_pct(r.similarity) + ")",
          )
        }
        buf.write_string("\n")
      }
      if c.missing_terms.length() > 0 {
        buf.write_string(
          "  missing in impl: " + join_terms(c.missing_terms) + "\n",
        )
      }
      if c.extra_terms.length() > 0 {
        buf.write_string(
          "  extra in impl:   " + join_terms(c.extra_terms) + "\n",
        )
      }
      buf.write_string("  action: " + c.rationale + "\n")
    }
  }
  buf.write_string("\n")
  buf.write_string("== Orphan impl docs (no act anchor) ==\n")
  if report.orphan_impl.is_empty() {
    buf.write_string("(none)\n")
  } else {
    for p in report.orphan_impl {
      buf.write_string("  " + p + "\n")
    }
  }
  buf.to_string()
}

///|
fn format_pct(v : Double) -> String {
  let pct = (v * 100.0 + 0.5).to_int()
  pct.to_string() + "%"
}

///|
fn join_terms(arr : Array[String]) -> String {
  let buf = StringBuilder::new()
  for i, s in arr {
    if i > 0 {
      buf.write_string(", ")
    }
    buf.write_string(s)
  }
  buf.to_string()
}
