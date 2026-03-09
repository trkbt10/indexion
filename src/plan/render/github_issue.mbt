///|
/// GitHub Issue renderer for PlanDocument.

///|
/// GitHub Issue output format.
pub struct GitHubIssue {
  title : String
  body : String
  labels : Array[String]
}

///|
/// Render PlanDocument as GitHub Issue.
pub fn render_github_issue(doc : @types.PlanDocument) -> GitHubIssue {
  let buf = StringBuilder::new()
  let style = RenderStyle::github_issue()
  // Description as opening paragraph
  if doc.description.length() > 0 {
    buf.write_string(doc.description)
    buf.write_string("\n\n")
  }
  // Render sections
  for section in doc.sections {
    render_section_common(buf, section, 2, style)
  }
  // Extract labels from metadata
  let labels : Array[String] = []
  match doc.metadata.get("labels") {
    Some(label_str) => {
      let parts = split_by_comma(label_str)
      for part in parts {
        let trimmed = trim_string(part)
        if trimmed.length() > 0 {
          labels.push(trimmed)
        }
      }
    }
    None => ()
  }
  { title: doc.title, body: buf.to_string(), labels }
}

// String utilities

///|
fn split_by_comma(s : String) -> Array[String] {
  let result : Array[String] = []
  let chars = s.to_array()
  let current : Array[Char] = []
  for c in chars {
    if c == ',' {
      result.push(String::from_array(current))
      current.clear()
    } else {
      current.push(c)
    }
  }
  if current.length() > 0 {
    result.push(String::from_array(current))
  }
  result
}

///|
fn trim_string(s : String) -> String {
  let chars = s.to_array()
  let mut start = 0
  let mut end = chars.length()
  while start < end && (chars[start] == ' ' || chars[start] == '\t') {
    start = start + 1
  }
  while end > start && (chars[end - 1] == ' ' || chars[end - 1] == '\t') {
    end = end - 1
  }
  let result : Array[Char] = []
  for i = start; i < end; i = i + 1 {
    result.push(chars[i])
  }
  String::from_array(result)
}
