/// Render a StoryReport as human-readable text or structured JSON.
///
/// JSON serialization is delegated to `derive(ToJson)` on the report
/// types and the standard `Json::stringify(indent=2)` from the
/// `moonbitlang/core/json` package. We do not hand-roll JSON: hand-
/// rolled construction tends to disagree with the standard library on
/// edge cases (escaping, number formatting, optional fields) and adds
/// maintenance cost without buying anything.

///|
/// Output format selector for story reports.
pub enum StoryFormat {
  Text
  Json
} derive(Eq, Show)

///|
pub fn StoryFormat::parse(s : String) -> StoryFormat {
  match s {
    "json" => Json
    "text" => Text
    _ => Text
  }
}

///|
pub fn render_report(report : StoryReport, format : StoryFormat) -> String {
  match format {
    Text => render_text(report)
    Json => report.to_json().stringify(indent=2) + "\n"
  }
}

///|
fn render_text(report : StoryReport) -> String {
  let buf = StringBuilder::new()
  buf.write_string("=== indexion story analyze ===\n")
  buf.write_string(
    "Spec docs: " +
    report.spec_count.to_string() +
    "  Impl docs: " +
    report.impl_count.to_string() +
    "\n",
  )
  buf.write_string(
    "Overall vocabulary distance (spec → impl): " +
    format_score(report.overall_distance) +
    "\n",
  )
  buf.write_string("\n")

  // Per-impl attribution.
  buf.write_string("== Impl attribution ==\n")
  if report.attributions.is_empty() {
    buf.write_string("(no impl documents loaded)\n")
  } else {
    for attr in report.attributions {
      buf.write_string("\n")
      buf.write_string("[Impl] " + attr.impl_path + "\n")
      buf.write_string(
        "  combined similarity vs spec: " +
        format_score(attr.combined_similarity) +
        "\n",
      )
      let top = take_first(attr.by_spec, 5)
      if top.is_empty() {
        buf.write_string("  (no spec docs to attribute against)\n")
      } else {
        for ps in top {
          buf.write_string(
            "  " +
            format_score(ps.similarity) +
            "  ← " +
            ps.spec_path +
            "\n",
          )
        }
        if attr.by_spec.length() > top.length() {
          let rest = attr.by_spec.length() - top.length()
          buf.write_string(
            "  (+" + rest.to_string() + " more spec doc(s))\n",
          )
        }
      }
    }
  }
  buf.write_string("\n")

  // Under-coverage: in spec but not in impl.
  buf.write_string("== Under-coverage (in spec, missing from impl) ==\n")
  if report.under_coverage.is_empty() {
    buf.write_string(
      "(none — spec is fully reflected in impl, or noise threshold filtered all candidates)\n",
    )
  } else {
    for u in report.under_coverage {
      buf.write_string("  " + format_weight(u.weight) + "  " + u.value)
      let origins = compress_origins(u.origin_paths)
      if origins.length() > 0 {
        buf.write_string("  ← " + origins)
      }
      buf.write_string("\n")
    }
  }
  buf.write_string("\n")

  // Out-of-source: in impl but not in spec.
  buf.write_string("== Out-of-source (in impl, no spec provenance) ==\n")
  if report.out_of_source.is_empty() {
    buf.write_string(
      "(none — impl contains nothing beyond the spec vocabulary)\n",
    )
  } else {
    for o in report.out_of_source {
      buf.write_string("  " + format_weight(o.weight) + "  " + o.value)
      let origins = compress_origins(o.origin_paths)
      if origins.length() > 0 {
        buf.write_string("  → " + origins)
      }
      buf.write_string("\n")
    }
  }
  buf.to_string()
}

///|
/// Compact display of similarity/distance score.
fn format_score(value : Double) -> String {
  let pct = (value * 100.0 + 0.5).to_int()
  pct.to_string() + "%"
}

///|
fn format_weight(w : Double) -> String {
  let scaled = (w * 1000.0 + 0.5).to_int()
  let int_part = scaled / 1000
  let frac_part = scaled % 1000
  let mut frac = frac_part.to_string()
  while frac.length() < 3 {
    frac = "0" + frac
  }
  int_part.to_string() + "." + frac
}

///|
fn take_first(arr : Array[PairSimilarity], n : Int) -> Array[PairSimilarity] {
  let result : Array[PairSimilarity] = []
  let limit = if n < arr.length() { n } else { arr.length() }
  for i = 0; i < limit; i = i + 1 {
    result.push(arr[i])
  }
  result
}

///|
/// Render origin paths as a compact display: at most 3, then "(+N more)".
fn compress_origins(paths : Array[String]) -> String {
  if paths.is_empty() {
    return ""
  }
  let buf = StringBuilder::new()
  let visible = if paths.length() > 3 { 3 } else { paths.length() }
  for i = 0; i < visible; i = i + 1 {
    if i > 0 {
      buf.write_string(", ")
    }
    buf.write_string(paths[i])
  }
  if paths.length() > visible {
    buf.write_string(" (+")
    buf.write_string((paths.length() - visible).to_string())
    buf.write_string(" more)")
  }
  buf.to_string()
}
