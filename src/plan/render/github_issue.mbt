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
  // Extract labels from metadata (use @parser.parse_list for comma-separated)
  let labels : Array[String] = []
  match doc.metadata.get("labels") {
    Some(label_str) => {
      let parts = @parser.parse_list(label_str)
      for part in parts {
        labels.push(part)
      }
    }
    None => ()
  }
  { title: doc.title, body: buf.to_string(), labels }
}

///|
/// Format GitHubIssue as a full Markdown document with title, labels, and body.
pub fn GitHubIssue::format(self : GitHubIssue) -> String {
  let buf = StringBuilder::new()
  buf.write_string("# ")
  buf.write_string(self.title)
  buf.write_string("\n\n")
  if self.labels.length() > 0 {
    buf.write_string("**Labels:** ")
    for i, label in self.labels {
      if i > 0 {
        buf.write_string(", ")
      }
      buf.write_string("`")
      buf.write_string(label)
      buf.write_string("`")
    }
    buf.write_string("\n\n")
  }
  buf.write_string("---\n\n")
  buf.write_string(self.body)
  buf.to_string()
}
