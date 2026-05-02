/// Extract `PlotAct` records from spec-side documents.
///
/// Earlier drafts of this module assumed the spec side had a designated
/// `Plot` sub-classification ("act extraction only runs on documents in
/// `sources/plot/`"). That convention is gone — the user picks which
/// documents go on the spec side via globs, and indexion does not
/// re-classify. So this extractor simply walks every spec document,
/// pulls headings from each, and emits one act per heading.
///
/// Heading conventions recognised, in priority order:
///
/// 1. **Markdown ATX headings** — `#`, `##`, `###`, `####` at the start
///    of a line. Most plot files use these.
/// 2. *(Future: bracketed enumerators / numeric prefixes can be added by
///    extending the heading scanner. For now we rely on writers using
///    markdown headings, which is overwhelmingly the common case.)*
///
/// We pick the *dominant* heading level inside each document (the level
/// with the most headings) and emit one act per heading at that level. A
/// document with no markdown headings becomes a single act named after
/// the document's basename.

///|
/// Extract acts from a single document. `path` is used as the
/// `source_path` of every emitted act so the user can trace a candidate
/// back to its origin.
pub fn extract_acts_from_doc(doc : @story.StoryDocument) -> Array[PlotAct] {
  let body = doc.get_content()
  let path = doc.get_path()
  let lines = split_lines(body)
  let headings = collect_markdown_headings(lines)
  if headings.length() == 0 {
    return [whole_doc_as_act(doc)]
  }
  let level = dominant_level(headings)
  let acts = build_acts_from_headings(headings, lines, path, level)
  if acts.length() == 0 {
    [whole_doc_as_act(doc)]
  } else {
    acts
  }
}

///|
/// Split text into lines preserving empty lines but discarding terminators.
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
    if k < chars.length() && chars[k] != ' ' && chars[k] != '\t' {
      continue
    }
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
/// title (markdown allows `## Title ##`).
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
/// Most frequent heading level among the candidates.
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
/// Build acts from headings filtered to the dominant level.
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
/// Title is the path basename via @config_paths.basename (SoT).
fn whole_doc_as_act(doc : @story.StoryDocument) -> PlotAct {
  let title = @config_paths.basename(doc.get_path())
  {
    source_path: doc.get_path(),
    level: 1,
    index: 1,
    title,
    body: doc.get_content(),
  }
}

///|
/// Extract all acts from every spec document in a `StoryGroups`, in
/// document order. Multiple spec documents (e.g. v1 and v2 plots) are
/// concatenated; downstream ranking distinguishes them via source_path.
pub fn extract_acts(groups : @story.StoryGroups) -> Array[PlotAct] {
  let result : Array[PlotAct] = []
  for s in groups.get_spec() {
    let acts = extract_acts_from_doc(s)
    for a in acts {
      result.push(a)
    }
  }
  result
}
