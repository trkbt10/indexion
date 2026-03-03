///|
/// Extracted documentation from a source file.
pub struct ExtractedDoc {
  title : String?
  content : String
  source_path : String
}

///|
pub fn ExtractedDoc::new(
  title : String?,
  content : String,
  source_path : String,
) -> ExtractedDoc {
  { title, content, source_path }
}

///|
/// Extract documentation from a MoonBit file.
/// Returns the first `///` block that starts with `# `.
pub fn extract_doc_from_file(path : String) -> ExtractedDoc? {
  try {
    let content = @fs.read_file_to_string(path)
    match extract_doc_block(content) {
      Some((title, doc)) => Some(ExtractedDoc::new(title, doc, path))
      None => None
    }
  } catch {
    _ => None
  }
}

///|
/// Extract the main documentation block from content.
/// Returns (title, full_content) if found.
fn extract_doc_block(content : String) -> (String?, String)? {
  let lines = split_lines(content)
  let doc_lines : Array[String] = []
  let mut in_doc = false
  let mut found_header = false
  let mut title : String? = None
  for line in lines {
    if line.has_prefix("///") {
      let doc_content = if line.length() > 3 {
        let chars = line.to_array()
        let result : Array[Char] = []
        // Skip "/// " or "///"
        let start = if chars.length() > 4 && chars[3] == ' ' { 4 } else { 3 }
        for i = start; i < chars.length(); i = i + 1 {
          result.push(chars[i])
        }
        String::from_array(result)
      } else {
        ""
      }
      // Check if this is a header line (starts with #)
      if doc_content.has_prefix("# ") && not(found_header) {
        found_header = true
        in_doc = true
        // Extract title from "# title"
        let title_chars = doc_content.to_array()
        let title_result : Array[Char] = []
        for i = 2; i < title_chars.length(); i = i + 1 {
          title_result.push(title_chars[i])
        }
        title = Some(String::from_array(title_result))
      }
      if in_doc {
        doc_lines.push(doc_content)
      }
    } else if in_doc && found_header {
      // End of doc block
      break
    }
  }
  if doc_lines.length() > 0 {
    Some((title, join_lines(doc_lines)))
  } else {
    None
  }
}

///|
fn split_lines(s : String) -> Array[String] {
  let lines : Array[String] = []
  let chars = s.to_array()
  let current : Array[Char] = []
  for c in chars {
    if c == '\n' {
      lines.push(String::from_array(current.copy()))
      current.clear()
    } else if c != '\r' {
      current.push(c)
    }
  }
  if current.length() > 0 {
    lines.push(String::from_array(current))
  }
  lines
}

///|
fn join_lines(lines : Array[String]) -> String {
  let buf = StringBuilder::new()
  for i, line in lines {
    if i > 0 {
      buf.write_char('\n')
    }
    buf.write_string(line)
  }
  buf.to_string()
}

///|
/// Find main source file in a package directory.
/// Priority: cli.mbt, main.mbt, then any .mbt file (excluding tests).
pub fn find_main_source(dir : String) -> String? {
  try {
    let candidates = ["cli.mbt", "main.mbt"]
    for candidate in candidates {
      let path = dir + "/" + candidate
      if @fs.is_file(path) {
        return Some(path)
      }
    }
    // Fallback to first .mbt file
    let entries = @fs.read_dir(dir)
    for entry in entries {
      if entry.has_suffix(".mbt") && not(entry.has_suffix("_wbtest.mbt")) {
        return Some(dir + "/" + entry)
      }
    }
    None
  } catch {
    _ => None
  }
}

///|
/// Extract summary (Overview section) from doc content.
pub fn extract_summary(content : String) -> String {
  let lines = split_lines(content)
  let result : Array[String] = []
  let mut in_overview = false
  let mut section_count = 0
  for line in lines {
    if line.has_prefix("## Overview") {
      in_overview = true
      continue
    }
    if in_overview {
      if line.has_prefix("## ") {
        section_count = section_count + 1
        if section_count > 1 {
          break
        }
        // Include Usage section too
        if line.has_prefix("## Usage") {
          result.push(line)
        } else {
          break
        }
      } else {
        result.push(line)
      }
    }
  }
  join_lines(result)
}
