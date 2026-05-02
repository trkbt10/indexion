/// Render a StoryReport as human-readable text or structured JSON.
///
/// The text format is the default — a layered overview suitable for terminal
/// inspection by a writer. JSON is intended for machine consumption (further
/// tooling, reconcile-style integrations later).

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
    Json => render_json(report)
  }
}

///|
fn render_text(report : StoryReport) -> String {
  let buf = StringBuilder::new()
  buf.write_string("=== indexion story analyze ===\n")
  buf.write_string("Root: " + report.root + "\n")
  buf.write_string(
    "Sources: " +
    report.source_count.to_string() +
    "  Prose: " +
    report.prose_count.to_string() +
    "\n",
  )
  buf.write_string(
    "Overall vocabulary distance (sources → prose): " +
    format_score(report.overall_distance) +
    "\n",
  )
  buf.write_string("\n")

  // Per-chapter attribution.
  buf.write_string("== Chapter attribution ==\n")
  if report.attributions.is_empty() {
    buf.write_string("(no prose chapters loaded)\n")
  } else {
    for attr in report.attributions {
      buf.write_string("\n")
      buf.write_string("[Prose] " + attr.prose_path + "\n")
      buf.write_string(
        "  combined similarity vs sources: " +
        format_score(attr.combined_similarity) +
        "\n",
      )
      let top = take_first(attr.by_source, 5)
      if top.is_empty() {
        buf.write_string("  (no sources to attribute against)\n")
      } else {
        for ps in top {
          buf.write_string(
            "  " +
            format_score(ps.similarity) +
            "  ← " +
            ps.source_path +
            "\n",
          )
        }
        if attr.by_source.length() > top.length() {
          let rest = attr.by_source.length() - top.length()
          buf.write_string(
            "  (+" + rest.to_string() + " more source(s))\n",
          )
        }
      }
    }
  }
  buf.write_string("\n")

  // Under-coverage: in sources but not in prose.
  buf.write_string("== Under-coverage (in sources, missing from prose) ==\n")
  if report.under_coverage.is_empty() {
    buf.write_string(
      "(none — sources are fully reflected in prose, or noise threshold filtered all candidates)\n",
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

  // Out-of-source: in prose but not in sources.
  buf.write_string("== Out-of-source (in prose, no source provenance) ==\n")
  if report.out_of_source.is_empty() {
    buf.write_string(
      "(none — prose contains nothing beyond the source vocabulary)\n",
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
fn render_json(report : StoryReport) -> String {
  let buf = StringBuilder::new()
  buf.write_string("{\n")
  buf.write_string("  \"root\": " + json_string(report.root) + ",\n")
  buf.write_string(
    "  \"source_count\": " + report.source_count.to_string() + ",\n",
  )
  buf.write_string(
    "  \"prose_count\": " + report.prose_count.to_string() + ",\n",
  )
  buf.write_string(
    "  \"overall_distance\": " +
    format_double(report.overall_distance) +
    ",\n",
  )
  buf.write_string("  \"attributions\": [\n")
  for i, attr in report.attributions {
    buf.write_string("    {\n")
    buf.write_string(
      "      \"prose_path\": " + json_string(attr.prose_path) + ",\n",
    )
    buf.write_string(
      "      \"combined_similarity\": " +
      format_double(attr.combined_similarity) +
      ",\n",
    )
    buf.write_string("      \"by_source\": [\n")
    for j, ps in attr.by_source {
      buf.write_string("        {\n")
      buf.write_string(
        "          \"source_path\": " + json_string(ps.source_path) + ",\n",
      )
      buf.write_string(
        "          \"similarity\": " + format_double(ps.similarity) + "\n",
      )
      buf.write_string("        }")
      if j < attr.by_source.length() - 1 {
        buf.write_string(",")
      }
      buf.write_string("\n")
    }
    buf.write_string("      ]\n")
    buf.write_string("    }")
    if i < report.attributions.length() - 1 {
      buf.write_string(",")
    }
    buf.write_string("\n")
  }
  buf.write_string("  ],\n")
  buf.write_string("  \"under_coverage\": [\n")
  for i, u in report.under_coverage {
    buf.write_string("    {\n")
    buf.write_string(
      "      \"value\": " + json_string(u.value) + ",\n",
    )
    buf.write_string(
      "      \"weight\": " + format_double(u.weight) + ",\n",
    )
    buf.write_string(
      "      \"origin_paths\": " + json_string_array(u.origin_paths) + "\n",
    )
    buf.write_string("    }")
    if i < report.under_coverage.length() - 1 {
      buf.write_string(",")
    }
    buf.write_string("\n")
  }
  buf.write_string("  ],\n")
  buf.write_string("  \"out_of_source\": [\n")
  for i, o in report.out_of_source {
    buf.write_string("    {\n")
    buf.write_string(
      "      \"value\": " + json_string(o.value) + ",\n",
    )
    buf.write_string(
      "      \"weight\": " + format_double(o.weight) + ",\n",
    )
    buf.write_string(
      "      \"origin_paths\": " + json_string_array(o.origin_paths) + "\n",
    )
    buf.write_string("    }")
    if i < report.out_of_source.length() - 1 {
      buf.write_string(",")
    }
    buf.write_string("\n")
  }
  buf.write_string("  ]\n")
  buf.write_string("}\n")
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
  // Three significant decimal digits.
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
fn format_double(d : Double) -> String {
  // Stable representation for JSON. Use 6-digit fixed-point.
  let scaled = (d * 1000000.0 + 0.5).to_int()
  let int_part = scaled / 1000000
  let frac_part = scaled % 1000000
  if frac_part == 0 {
    int_part.to_string() + ".0"
  } else {
    let mut frac = frac_part.to_string()
    while frac.length() < 6 {
      frac = "0" + frac
    }
    // Strip trailing zeros for readability while keeping at least one digit.
    let chars = frac.to_array()
    let mut end = chars.length()
    while end > 1 && chars[end - 1] == '0' {
      end -= 1
    }
    let trimmed = StringBuilder::new()
    for k = 0; k < end; k = k + 1 {
      trimmed.write_char(chars[k])
    }
    int_part.to_string() + "." + trimmed.to_string()
  }
}

///|
fn json_string(s : String) -> String {
  let buf = StringBuilder::new()
  buf.write_char('"')
  for c in s {
    match c {
      '"' => buf.write_string("\\\"")
      '\\' => buf.write_string("\\\\")
      '\n' => buf.write_string("\\n")
      '\r' => buf.write_string("\\r")
      '\t' => buf.write_string("\\t")
      _ => buf.write_char(c)
    }
  }
  buf.write_char('"')
  buf.to_string()
}

///|
fn json_string_array(arr : Array[String]) -> String {
  let buf = StringBuilder::new()
  buf.write_char('[')
  for i, s in arr {
    if i > 0 {
      buf.write_string(", ")
    }
    buf.write_string(json_string(s))
  }
  buf.write_char(']')
  buf.to_string()
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
