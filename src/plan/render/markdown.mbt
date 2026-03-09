///|
/// Markdown renderer for PlanDocument.

///|
/// Render PlanDocument to Markdown string.
pub fn render_markdown(doc : @types.PlanDocument) -> String {
  let buf = StringBuilder::new()
  let style = RenderStyle::markdown()
  // Title
  buf.write_string("# ")
  buf.write_string(doc.title)
  buf.write_string("\n\n")
  // Description
  if doc.description.length() > 0 {
    buf.write_string(doc.description)
    buf.write_string("\n\n")
  }
  // Sections
  for section in doc.sections {
    render_section_common(buf, section, 2, style)
  }
  buf.to_string()
}
