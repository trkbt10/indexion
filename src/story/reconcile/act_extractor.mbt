/// Extract `PlotAct` records from a plot document.
///
/// The extractor recognises three heading conventions, in order of priority:
///
/// 1. **Markdown ATX headings** — `#`, `##`, `###`, `####` at the start of a
///    line. The most common case for `sources/plot/*.md`.
/// 2. **Bracketed enumerators** — `[Act 1]`, `[第一幕]` — a fall-back for
///    plain-text plot files that do not use markdown headings.
/// 3. **Numeric act prefixes** — lines beginning with `Act 1:` or `第一幕:`.
///
/// We prefer markdown when present; if no markdown headings are found we
/// scan the document for the bracketed / numeric forms. If still no
/// boundaries are detected the entire document becomes a single act of
/// level 1, index 1, titled with the document's display name.
///
/// Heading-level filtering matters: a plot document may have a top-level
/// `# Outline` and per-act `## 第一幕` sub-headings. We only emit acts at
/// the most numerous heading level, treating the parent heading as the
/// document title rather than an act in its own right.

///|
/// Extract acts from a single SourceDoc whose kind is Plot.
pub fn extract_acts_from_doc(doc : @story.SourceDoc) -> Array[PlotAct] {
  let body = doc.get_content()
  let path = doc.get_rel_path()
  let lines = split_lines(body)
  let headings = collect_markdown_headings(lines)
  if headings.length() == 0 {
    return [whole_doc_as_act(doc)]
  }
  // Find the dominant heading level (most frequent). This is the act level.
  let level = dominant_level(headings)
  let acts = build_acts_from_headings(headings, lines, path, level)
  if acts.length() == 0 {
    [whole_doc_as_act(doc)]
  } else {
    acts
  }
}

///|
/// Split text into lines without dropping the trailing newline information.
fn split_lines(text : String) -> Array[String] {
  let result : Array[String] = []
  let buf = StringBuilder::new()
  let chars = text.to_array()
  let mut i = 0
  while i < chars.length() {
    let c = chars[i]
    if c == '\n' {
      result.push(buf.to_string())
      buf.reset()
    } else if c == '\r' {
      result.push(buf.to_string())
      buf.reset()
      if i + 1 < chars.length() && chars[i + 1] == '\n' {
        i += 1
      }
    } else {
      buf.write_char(c)
    }
    i += 1
  }
  if buf.to_string().length() > 0 {
    result.push(buf.to_string())
  } else if chars.length() > 0 && chars[chars.length() - 1] != '\n' {
    // Already pushed empty string for the final newline; nothing to do.
  }
  result
}

///|
/// A markdown heading detected on a specific line.
priv struct Heading {
  line_index : Int
  level : Int
  title : String
}

///|
/// Scan lines for ATX-style markdown headings.
fn collect_markdown_headings(lines : Array[String]) -> Array[Heading] {
  let result : Array[Heading] = []
  for i, line in lines {
    let chars = line.to_array()
    let mut k = 0
    // Skip leading spaces (Markdown allows up to 3).
    while k < chars.length() && k < 3 && chars[k] == ' ' {
      k += 1
    }
    let mut level = 0
    while k < chars.length() && chars[k] == '#' && level < 6 {
      level += 1
      k += 1
    }
    if level == 0 {
      continue
    }
    // Must be followed by space (or end of line for empty heading).
    if k < chars.length() && chars[k] != ' ' && chars[k] != '\t' {
      continue
    }
    // Skip leading whitespace after #.
    while k < chars.length() && (chars[k] == ' ' || chars[k] == '\t') {
      k += 1
    }
    let title_chars : Array[Char] = []
    for j = k; j < chars.length(); j = j + 1 {
      title_chars.push(chars[j])
    }
    let title = trim_trailing_hashes(String::from_array(title_chars))
    result.push({ line_index: i, level, title })
  }
  result
}

///|
/// Strip a trailing run of "#" plus surrounding whitespace from a heading
/// title (Markdown allows `## Title ##` as a closing marker).
fn trim_trailing_hashes(s : String) -> String {
  let chars = s.to_array()
  let mut end = chars.length()
  while end > 0 && (chars[end - 1] == ' ' || chars[end - 1] == '\t') {
    end -= 1
  }
  while end > 0 && chars[end - 1] == '#' {
    end -= 1
  }
  while end > 0 && (chars[end - 1] == ' ' || chars[end - 1] == '\t') {
    end -= 1
  }
  let buf = StringBuilder::new()
  for k = 0; k < end; k = k + 1 {
    buf.write_char(chars[k])
  }
  buf.to_string()
}

///|
/// Most frequent heading level among the candidates. If two levels are tied,
/// the deeper level wins (sub-headings are usually the per-act granularity).
fn dominant_level(headings : Array[Heading]) -> Int {
  let counts : Map[Int, Int] = {}
  for h in headings {
    counts[h.level] = counts.get(h.level).unwrap_or(0) + 1
  }
  let mut best_level = headings[0].level
  let mut best_count = -1
  for entry in counts {
    let lvl = entry.0
    let cnt = entry.1
    if cnt > best_count || (cnt == best_count && lvl > best_level) {
      best_level = lvl
      best_count = cnt
    }
  }
  best_level
}

///|
/// Build acts from headings filtered to the dominant level. Each act runs
/// from its heading line up to the next heading at the same level (or EOF).
fn build_acts_from_headings(
  all_headings : Array[Heading],
  lines : Array[String],
  source_path : String,
  level : Int,
) -> Array[PlotAct] {
  let chosen : Array[Heading] = []
  for h in all_headings {
    if h.level == level {
      chosen.push(h)
    }
  }
  let result : Array[PlotAct] = []
  for i, h in chosen {
    let next_line = if i + 1 < chosen.length() {
      chosen[i + 1].line_index
    } else {
      lines.length()
    }
    let body = collect_body(lines, h.line_index + 1, next_line)
    result.push({
      source_path,
      level,
      index: i + 1,
      title: h.title,
      body,
    })
  }
  result
}

///|
fn collect_body(lines : Array[String], start : Int, end : Int) -> String {
  let buf = StringBuilder::new()
  let mut first = true
  for i = start; i < end; i = i + 1 {
    if !first {
      buf.write_char('\n')
    }
    buf.write_string(lines[i])
    first = false
  }
  buf.to_string()
}

///|
/// Fallback: treat the whole document as a single act when no headings exist.
fn whole_doc_as_act(doc : @story.SourceDoc) -> PlotAct {
  {
    source_path: doc.get_rel_path(),
    level: 1,
    index: 1,
    title: doc.get_display_name(),
    body: doc.get_content(),
  }
}

///|
/// Extract all acts from every Plot-kind source in a dataset, in document
/// order. Multiple plot files (e.g. `01-outline.md` and `02-revision.md`)
/// are concatenated; downstream ranking distinguishes them via source_path.
pub fn extract_acts(
  dataset : @story.StoryDataset,
) -> Array[PlotAct] {
  let result : Array[PlotAct] = []
  for s in dataset.get_sources() {
    match s.get_kind() {
      @story.SourceKind::Plot => {
        let acts = extract_acts_from_doc(s)
        for a in acts {
          result.push(a)
        }
      }
      _ => continue
    }
  }
  result
}
