/// Render a `ReconcileReport` as text or JSON.

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
    Json => render_json(report)
  }
}

///|
fn render_text(report : ReconcileReport) -> String {
  let buf = StringBuilder::new()
  buf.write_string("=== indexion story reconcile ===\n")
  buf.write_string("Root: " + report.root + "\n")
  buf.write_string(
    "Acts: " +
    report.acts.length().to_string() +
    "  Prose chapters: " +
    report.prose_paths.length().to_string() +
    "\n",
  )
  buf.write_string("\n")
  buf.write_string("== Plot acts ==\n")
  if report.acts.is_empty() {
    buf.write_string("(no acts extracted)\n")
  } else {
    for a in report.acts {
      buf.write_string(
        "  [" + a.source_path + " #" + a.index.to_string() + "] " +
        a.title + "\n",
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
            "  best:   " + m.prose_path + " (" + format_pct(m.similarity) +
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
          buf.write_string(r.prose_path + " (" + format_pct(r.similarity) + ")")
        }
        buf.write_string("\n")
      }
      if c.missing_terms.length() > 0 {
        buf.write_string("  missing in prose: " + join_terms(c.missing_terms) + "\n")
      }
      if c.extra_terms.length() > 0 {
        buf.write_string("  extra in prose:   " + join_terms(c.extra_terms) + "\n")
      }
      buf.write_string("  action: " + c.rationale + "\n")
    }
  }
  buf.write_string("\n")
  buf.write_string("== Orphan chapters (no act anchor) ==\n")
  if report.orphan_chapters.is_empty() {
    buf.write_string("(none)\n")
  } else {
    for p in report.orphan_chapters {
      buf.write_string("  " + p + "\n")
    }
  }
  buf.to_string()
}

///|
fn render_json(report : ReconcileReport) -> String {
  let buf = StringBuilder::new()
  buf.write_string("{\n")
  buf.write_string("  \"root\": " + json_string(report.root) + ",\n")
  buf.write_string("  \"acts\": [\n")
  for i, a in report.acts {
    buf.write_string("    {\n")
    buf.write_string(
      "      \"source_path\": " + json_string(a.source_path) + ",\n",
    )
    buf.write_string("      \"level\": " + a.level.to_string() + ",\n")
    buf.write_string("      \"index\": " + a.index.to_string() + ",\n")
    buf.write_string("      \"title\": " + json_string(a.title) + "\n")
    buf.write_string("    }")
    if i < report.acts.length() - 1 {
      buf.write_string(",")
    }
    buf.write_string("\n")
  }
  buf.write_string("  ],\n")
  buf.write_string("  \"prose_paths\": " + json_string_array(report.prose_paths) + ",\n")
  buf.write_string("  \"candidates\": [\n")
  for i, c in report.candidates {
    buf.write_string("    {\n")
    buf.write_string(
      "      \"act_source\": " + json_string(c.act.source_path) + ",\n",
    )
    buf.write_string(
      "      \"act_index\": " + c.act.index.to_string() + ",\n",
    )
    buf.write_string(
      "      \"act_title\": " + json_string(c.act.title) + ",\n",
    )
    match c.best_match {
      Some(m) => {
        buf.write_string(
          "      \"best_match\": {\"prose_path\": " +
          json_string(m.prose_path) + ", \"similarity\": " +
          format_double(m.similarity) + "},\n",
        )
      }
      None => buf.write_string("      \"best_match\": null,\n")
    }
    buf.write_string("      \"runner_ups\": [")
    for j, r in c.runner_ups {
      if j > 0 {
        buf.write_string(", ")
      }
      buf.write_string(
        "{\"prose_path\": " + json_string(r.prose_path) +
        ", \"similarity\": " + format_double(r.similarity) + "}",
      )
    }
    buf.write_string("],\n")
    buf.write_string(
      "      \"missing_terms\": " + json_string_array(c.missing_terms) + ",\n",
    )
    buf.write_string(
      "      \"extra_terms\": " + json_string_array(c.extra_terms) + ",\n",
    )
    buf.write_string(
      "      \"action\": " + json_string(c.action.label()) + ",\n",
    )
    buf.write_string(
      "      \"rationale\": " + json_string(c.rationale) + "\n",
    )
    buf.write_string("    }")
    if i < report.candidates.length() - 1 {
      buf.write_string(",")
    }
    buf.write_string("\n")
  }
  buf.write_string("  ],\n")
  buf.write_string(
    "  \"orphan_chapters\": " + json_string_array(report.orphan_chapters) + "\n",
  )
  buf.write_string("}\n")
  buf.to_string()
}

///|
fn format_pct(v : Double) -> String {
  let pct = (v * 100.0 + 0.5).to_int()
  pct.to_string() + "%"
}

///|
fn format_double(d : Double) -> String {
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
