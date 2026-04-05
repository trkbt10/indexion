///|
/// Section extraction from document files using KGF tokenization.

///|
/// Extract specified sections from content.
/// Returns content of matching sections joined together.
pub fn extract_sections(
  content : String,
  section_names : Array[String],
) -> String {
  if section_names.is_empty() {
    return content
  }
  let normalized_names = normalize_section_names(section_names)
  let headings = tokenize_and_extract_headings(content)
  let lines = split_content_lines(content)
  let heading_map = build_heading_line_map(headings)
  let result = StringBuilder::new()
  let mut in_matching_section = false
  let mut first_output = true
  for i, line in lines {
    let line_num = i + 1
    match heading_map.get(line_num) {
      Some(heading) => {
        let normalized = normalize_section_name(heading.text)
        in_matching_section = contains_section_name(
          normalized_names, normalized,
        )
        if in_matching_section {
          if !first_output {
            result.write_string("\n")
          }
          first_output = false
        }
      }
      None => ()
    }
    if in_matching_section {
      result.write_string(line)
      result.write_char('\n')
    }
  }
  result.to_string()
}

///|
/// Extract overview/summary section (content before first level-2 heading).
pub fn extract_overview(content : String) -> String {
  let headings = tokenize_and_extract_headings(content)
  let lines = split_content_lines(content)
  let result = StringBuilder::new()
  let mut skipped_title = false
  // Find line of first level-2 heading
  let mut first_h2_line = lines.length() + 1
  for h in headings {
    if h.level == 2 {
      first_h2_line = h.line
      break
    }
  }
  // Find title heading (level 1)
  let mut title_line = -1
  for h in headings {
    if h.level == 1 {
      title_line = h.line
      break
    }
  }
  for i, line in lines {
    let line_num = i + 1
    if !skipped_title && line_num == title_line {
      skipped_title = true
      continue
    }
    if line_num >= first_h2_line {
      break
    }
    if skipped_title || title_line < 0 {
      result.write_string(line)
      result.write_char('\n')
    }
  }
  @common.trim_ascii_spaces(result.to_string())
}

///|
fn normalize_section_names(names : Array[String]) -> Array[String] {
  let result : Array[String] = []
  for name in names {
    result.push(normalize_section_name(name))
  }
  result
}

///|
fn normalize_section_name(name : String) -> String {
  let chars = name.to_array()
  let result : Array[Char] = []
  for ch in chars {
    if is_alpha_char(ch) || is_digit_char(ch) {
      result.push(to_lower_char(ch))
    }
  }
  String::from_array(result)
}

///|
fn contains_section_name(names : Array[String], name : String) -> Bool {
  for n in names {
    if n == name {
      return true
    }
  }
  false
}

///|
fn split_content_lines(content : String) -> Array[String] {
  let lines : Array[String] = []
  let current : Array[Char] = []
  for ch in content.to_array() {
    if ch == '\n' {
      lines.push(String::from_array(current))
      current.clear()
    } else {
      current.push(ch)
    }
  }
  if current.length() > 0 {
    lines.push(String::from_array(current))
  }
  lines
}

///|
/// Collect lines into a trimmed text block.
fn lines_to_text(lines : Array[String]) -> String {
  let buf = StringBuilder::new()
  for i, line in lines {
    if i > 0 {
      buf.write_char('\n')
    }
    buf.write_string(line)
  }
  @common.trim_ascii_spaces(buf.to_string())
}

///|
/// Parse content into a hierarchical array of PlanSections using KGF headings.
pub fn parse_markdown_to_sections(
  content : String,
) -> Array[@plan_types.PlanSection] {
  let headings = tokenize_and_extract_headings(content)
  let lines = split_content_lines(content)
  let heading_map = build_heading_line_map(headings)
  let result : Array[@plan_types.PlanSection] = []
  if headings.is_empty() {
    let text = @common.trim_ascii_spaces(content)
    if text.length() > 0 {
      result.push(
        @plan_types.PlanSection::new(
          "",
          "",
          @plan_types.SectionContent::text(text),
        ),
      )
    }
    return result
  }
  // Find minimum heading level
  let mut min_level = 99
  for h in headings {
    if h.level < min_level {
      min_level = h.level
    }
  }
  // Build flat section list: (level, heading_text, content_lines)
  let flat : Array[(Int, String, Array[String])] = []
  let mut current_lines : Array[String] = []
  let mut current_heading = ""
  let mut current_level = 0
  for i, line in lines {
    let line_num = i + 1
    match heading_map.get(line_num) {
      Some(heading) => {
        if current_heading.length() > 0 || current_lines.length() > 0 {
          flat.push((current_level, current_heading, current_lines))
        }
        current_heading = heading.text
        current_level = heading.level
        current_lines = []
      }
      None => current_lines.push(line)
    }
  }
  if current_heading.length() > 0 || current_lines.length() > 0 {
    flat.push((current_level, current_heading, current_lines))
  }
  build_nested_sections(flat, 0, flat.length(), min_level)
}

///|
/// Build nested PlanSections from a flat section list.
fn build_nested_sections(
  flat : Array[(Int, String, Array[String])],
  start : Int,
  end : Int,
  base_level : Int,
) -> Array[@plan_types.PlanSection] {
  let result : Array[@plan_types.PlanSection] = []
  let mut i = start
  while i < end {
    let (level, heading, lines) = flat[i]
    if level == 0 {
      let text = lines_to_text(lines)
      if text.length() > 0 {
        result.push(
          @plan_types.PlanSection::new(
            "",
            "",
            @plan_types.SectionContent::text(text),
          ),
        )
      }
      i = i + 1
    } else if level == base_level {
      let mut section_end = i + 1
      while section_end < end {
        let (next_level, _, _) = flat[section_end]
        if next_level > 0 && next_level <= base_level {
          break
        }
        section_end = section_end + 1
      }
      let own_text = lines_to_text(lines)
      let children = build_nested_sections(
        flat,
        i + 1,
        section_end,
        base_level + 1,
      )
      let id = normalize_section_name(heading)
      if children.length() == 0 {
        result.push(
          @plan_types.PlanSection::new(
            id,
            heading,
            @plan_types.SectionContent::text(own_text),
          ),
        )
      } else {
        let nested : Array[@plan_types.PlanSection] = []
        if own_text.length() > 0 {
          nested.push(
            @plan_types.PlanSection::new(
              "",
              "",
              @plan_types.SectionContent::text(own_text),
            ),
          )
        }
        for child in children {
          nested.push(child)
        }
        result.push(
          @plan_types.PlanSection::new(
            id,
            heading,
            @plan_types.SectionContent::nested(nested),
          ),
        )
      }
      i = section_end
    } else {
      i = i + 1
    }
  }
  result
}

///|
/// Filter parsed PlanSections by section names.
pub fn filter_parsed_sections(
  sections : Array[@plan_types.PlanSection],
  names : Array[String],
) -> Array[@plan_types.PlanSection] {
  if names.is_empty() {
    return sections
  }
  let normalized = normalize_section_names(names)
  let result : Array[@plan_types.PlanSection] = []
  let include_overview = contains_section_name(normalized, "overview")
  for section in sections {
    if section.heading.length() == 0 {
      if include_overview {
        result.push(section)
      }
    } else {
      let name = normalize_section_name(section.heading)
      if contains_section_name(normalized, name) {
        result.push(section)
      }
    }
  }
  result
}

// --- KGF tokenization helpers ---

///|
/// Tokenize content and extract headings using KGF.
fn tokenize_and_extract_headings(
  content : String,
) -> Array[@kgf_features.Heading] {
  let registry = @kgf_features.load_registry(specs_dir="kgfs", target_dir=".")
  let reg = match registry {
    Some(r) => r
    None => return []
  }
  let spec = match reg.detect_from_path("doc.md") {
    Some(lang) => reg.get_spec(lang)
    None => None
  }
  let tokens = @kgf_features.tokenize_source(content, "doc.md", registry)
  match tokens {
    Some(toks) => @kgf_features.extract_headings(toks, spec~, source=content)
    None => []
  }
}

///|
/// Build a map from line number to Heading for fast lookup.
fn build_heading_line_map(
  headings : Array[@kgf_features.Heading],
) -> Map[Int, @kgf_features.Heading] {
  let map : Map[Int, @kgf_features.Heading] = {}
  for h in headings {
    map[h.line] = h
  }
  map
}

// --- Character helpers ---

///|
fn is_alpha_char(ch : Char) -> Bool {
  (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z')
}

///|
fn is_digit_char(ch : Char) -> Bool {
  ch >= '0' && ch <= '9'
}

///|
fn to_lower_char(ch : Char) -> Char {
  if ch >= 'A' && ch <= 'Z' {
    Int::unsafe_to_char(ch.to_int() + 32)
  } else {
    ch
  }
}
