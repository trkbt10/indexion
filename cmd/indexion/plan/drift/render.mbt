///|
/// Render a DriftReport as text, markdown, or JSON.
/// The JSON shape is whatever `DriftReport`'s derived `ToJson` produces.
pub fn render_output(report : DriftReport, format : String) -> String {
  match format {
    "json" => report.to_json().stringify(indent=2)
    "md" => render_markdown(report)
    _ => render_text(report)
  }
}

///|
fn render_text(report : DriftReport) -> String {
  let buf = StringBuilder::new()
  buf.write_string("Strategy: drift (KGF tokenize → @vocab.measure_divergence, natural-language mode)\n")
  buf.write_string("File 1: ")
  buf.write_string(report.file_a)
  buf.write_string(" (spec=")
  buf.write_string(report.spec_a)
  buf.write_string(", ")
  buf.write_string(report.feature_token_count_a.to_string())
  buf.write_string(" feature tokens)\n")
  buf.write_string("File 2: ")
  buf.write_string(report.file_b)
  buf.write_string(" (spec=")
  buf.write_string(report.spec_b)
  buf.write_string(", ")
  buf.write_string(report.feature_token_count_b.to_string())
  buf.write_string(" feature tokens)\n")
  buf.write_string("\n")
  buf.write_string("Cosine distance:   ")
  buf.write_string(format_double(report.cosine_distance))
  buf.write_string("\n")
  buf.write_string("Cosine similarity: ")
  buf.write_string(format_double(1.0 - report.cosine_distance))
  buf.write_string("\n")
  match (report.threshold, report.threshold_passed) {
    (Some(t), Some(passed)) => {
      buf.write_string("Threshold:         ")
      buf.write_string(format_double(t))
      buf.write_string(" (")
      buf.write_string(if passed { "passed" } else { "exceeded" })
      buf.write_string(")\n")
    }
    _ => ()
  }
  buf.write_string("\n")
  write_text_section(buf, "Drift terms in " + report.file_a +
    " (missing on the other side):", report.a_to_b.gap_terms)
  buf.write_string("\n")
  write_text_section(buf, "Drift terms in " + report.file_b +
    " (missing on the other side):", report.b_to_a.gap_terms)
  buf.to_string()
}

///|
fn write_text_section(
  buf : StringBuilder,
  header : String,
  terms : Array[DriftGapTerm],
) -> Unit {
  buf.write_string(header)
  buf.write_string("\n")
  if terms.length() == 0 {
    buf.write_string("  (none)\n")
    return
  }
  for term in terms {
    buf.write_string("  - ")
    buf.write_string(term.value)
    buf.write_string("  [")
    buf.write_string(term.kind)
    buf.write_string(", w=")
    buf.write_string(format_double(term.weight))
    buf.write_string("]\n")
  }
}

///|
fn render_markdown(report : DriftReport) -> String {
  let buf = StringBuilder::new()
  buf.write_string("# Drift report\n\n")
  buf.write_string("- **File A**: `")
  buf.write_string(report.file_a)
  buf.write_string("` (spec: ")
  buf.write_string(report.spec_a)
  buf.write_string(", ")
  buf.write_string(report.feature_token_count_a.to_string())
  buf.write_string(" feature tokens)\n")
  buf.write_string("- **File B**: `")
  buf.write_string(report.file_b)
  buf.write_string("` (spec: ")
  buf.write_string(report.spec_b)
  buf.write_string(", ")
  buf.write_string(report.feature_token_count_b.to_string())
  buf.write_string(" feature tokens)\n")
  buf.write_string("- **Cosine distance**: ")
  buf.write_string(format_double(report.cosine_distance))
  buf.write_string("\n")
  buf.write_string("- **Cosine similarity**: ")
  buf.write_string(format_double(1.0 - report.cosine_distance))
  buf.write_string("\n")
  match (report.threshold, report.threshold_passed) {
    (Some(t), Some(passed)) => {
      buf.write_string("- **Threshold**: ")
      buf.write_string(format_double(t))
      buf.write_string(" — ")
      buf.write_string(if passed { "passed" } else { "**exceeded**" })
      buf.write_string("\n")
    }
    _ => ()
  }
  buf.write_string("\n")
  write_md_section(buf, "A → B drift", report.a_to_b)
  write_md_section(buf, "B → A drift", report.b_to_a)
  buf.to_string()
}

///|
fn write_md_section(
  buf : StringBuilder,
  title : String,
  dir : DriftDirection,
) -> Unit {
  buf.write_string("## ")
  buf.write_string(title)
  buf.write_string("\n\n")
  buf.write_string("Terms in `")
  buf.write_string(dir.source_path)
  buf.write_string("` missing from `")
  buf.write_string(dir.target_path)
  buf.write_string("`:\n\n")
  if dir.gap_terms.length() == 0 {
    buf.write_string("_None_\n\n")
    return
  }
  buf.write_string("| Value | Kind | Weight |\n")
  buf.write_string("|---|---|---:|\n")
  for term in dir.gap_terms {
    buf.write_string("| `")
    buf.write_string(term.value)
    buf.write_string("` | ")
    buf.write_string(term.kind)
    buf.write_string(" | ")
    buf.write_string(format_double(term.weight))
    buf.write_string(" |\n")
  }
  buf.write_string("\n")
}

///|
fn format_double(d : Double) -> String {
  let negative = d < 0.0
  let abs_val = if negative { -d } else { d }
  let int_part = abs_val.to_int()
  let frac_part = ((abs_val - int_part.to_double()) * 1000000.0).to_int()
  let prefix = if negative { "-" } else { "" }
  let frac_str = pad_left(frac_part.to_string(), 6, '0')
  prefix + int_part.to_string() + "." + frac_str
}

///|
fn pad_left(s : String, width : Int, pad_char : Char) -> String {
  let chars = s.to_array()
  if chars.length() >= width {
    return s
  }
  let result : Array[Char] = []
  let pad_count = width - chars.length()
  for i = 0; i < pad_count; i = i + 1 {
    result.push(pad_char)
  }
  for c in chars {
    result.push(c)
  }
  String::from_array(result)
}
