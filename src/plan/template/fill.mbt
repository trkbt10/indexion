///|
/// Fill GitHub Issue Form templates with PlanDocument data.

///|
/// Fill an issue form template with data from PlanDocument.
/// Returns the filled body content as a string.
pub fn fill_issue_form(
  template : IssueFormTemplate,
  doc : @types.PlanDocument
) -> String {
  let buf = StringBuilder::new()
  let style = @render.RenderStyle::markdown()
  // Map section IDs to content
  let section_map : Map[String, @types.PlanSection] = Map::new()
  for section in doc.sections {
    section_map.set(section.id, section)
  }
  // Process each field in the template
  for field in template.body {
    match field {
      FormField::Markdown(md) => {
        // Static markdown, include as-is
        if md.value.length() > 0 {
          buf.write_string(md.value)
          buf.write_string("\n\n")
        }
      }
      FormField::Textarea(ta) => {
        // Find matching section by id
        buf.write_string("### ")
        buf.write_string(ta.label)
        buf.write_string("\n\n")
        match section_map.get(ta.id) {
          Some(section) => {
            @render.render_content_common(buf, section.content, 4, style)
          }
          None => {
            // Use default value or placeholder
            if ta.value.length() > 0 {
              buf.write_string(ta.value)
              buf.write_string("\n\n")
            } else if ta.placeholder.length() > 0 {
              buf.write_string("_")
              buf.write_string(ta.placeholder)
              buf.write_string("_\n\n")
            }
          }
        }
      }
      FormField::Input(inp) => {
        // Single line input - use metadata or section
        buf.write_string("**")
        buf.write_string(inp.label)
        buf.write_string(":** ")
        match doc.metadata.get(inp.id) {
          Some(val) => buf.write_string(val)
          None =>
            match section_map.get(inp.id) {
              Some(section) => {
                match section.content {
                  @types.SectionContent::Text(t) => buf.write_string(t)
                  _ => buf.write_string(inp.value)
                }
              }
              None => buf.write_string(inp.value)
            }
        }
        buf.write_string("\n\n")
      }
      FormField::Dropdown(dd) => {
        buf.write_string("**")
        buf.write_string(dd.label)
        buf.write_string(":** ")
        // Use metadata or default
        match doc.metadata.get(dd.id) {
          Some(val) => buf.write_string(val)
          None =>
            if dd.default_index >= 0 && dd.default_index < dd.options.length() {
              buf.write_string(dd.options[dd.default_index])
            }
        }
        buf.write_string("\n\n")
      }
      FormField::Checkboxes(cb) => {
        buf.write_string("### ")
        buf.write_string(cb.label)
        buf.write_string("\n\n")
        // Try to match with checklist section
        match section_map.get(cb.id) {
          Some(section) => {
            @render.render_content_common(buf, section.content, 4, style)
          }
          None => {
            for opt in cb.options {
              buf.write_string("- [ ] ")
              buf.write_string(opt.label)
              buf.write_string("\n")
            }
            buf.write_string("\n")
          }
        }
      }
    }
  }
  buf.to_string()
}

///|
/// Generate filled issue form output with title.
pub struct FilledIssueForm {
  title : String
  body : String
  labels : Array[String]
  assignees : Array[String]
}

///|
/// Fill issue form and return complete output.
pub fn fill_and_render(
  template : IssueFormTemplate,
  doc : @types.PlanDocument
) -> FilledIssueForm {
  let body = fill_issue_form(template, doc)
  // Generate title from template title pattern
  let title = if template.title.length() > 0 {
    // Replace placeholders in title
    replace_title_placeholders(template.title, doc)
  } else {
    doc.title
  }
  {
    title,
    body,
    labels: template.labels,
    assignees: template.assignees,
  }
}

///|
fn replace_title_placeholders(title_pattern : String, doc : @types.PlanDocument) -> String {
  // Simple placeholder replacement: [TYPE] -> doc.metadata.get("type")
  let chars = title_pattern.to_array()
  let result = StringBuilder::new()
  let mut i = 0
  while i < chars.length() {
    if chars[i] == '[' {
      // Find closing bracket
      let mut j = i + 1
      while j < chars.length() && chars[j] != ']' {
        j = j + 1
      }
      if j < chars.length() {
        // Extract placeholder name
        let placeholder : Array[Char] = []
        for k = i + 1; k < j; k = k + 1 {
          placeholder.push(chars[k])
        }
        let name = lower(String::from_array(placeholder))
        // Try to replace
        match doc.metadata.get(name) {
          Some(val) => {
            result.write_string("[")
            result.write_string(val)
            result.write_string("]")
          }
          None => {
            // Keep original
            for k = i; k <= j; k = k + 1 {
              result.write_char(chars[k])
            }
          }
        }
        i = j + 1
        continue
      }
    }
    result.write_char(chars[i])
    i = i + 1
  }
  // Append doc title at the end
  let base = result.to_string()
  if base.has_suffix(": ") || base.has_suffix("]: ") {
    base + doc.title
  } else if base.has_suffix(":") || base.has_suffix("]:") {
    base + " " + doc.title
  } else {
    base
  }
}

///|
fn lower(s : String) -> String {
  let chars = s.to_array()
  let result : Array[Char] = []
  for c in chars {
    if c >= 'A' && c <= 'Z' {
      result.push(Char::from_int(c.to_int() + 32))
    } else {
      result.push(c)
    }
  }
  String::from_array(result)
}
