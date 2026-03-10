///|
/// Common content rendering for PlanDocument.
/// Provides a single implementation that can be customized via RenderStyle.

///|
/// Rendering style options.
pub struct RenderStyle {
  /// Priority format: "bracket" -> [P1], "bold" -> **P1**
  priority_style : String
  /// Whether to add newline before checklist item description
  checklist_desc_newline : Bool
  /// Table alignment separator style: "spaced" -> " :--- |", "compact" -> ":---|"
  table_separator_spaced : Bool
}

///|
/// Default markdown style.
pub fn RenderStyle::markdown() -> RenderStyle {
  {
    priority_style: "bracket",
    checklist_desc_newline: false,
    table_separator_spaced: true,
  }
}

///|
/// GitHub Issue style.
pub fn RenderStyle::github_issue() -> RenderStyle {
  {
    priority_style: "bold",
    checklist_desc_newline: true,
    table_separator_spaced: false,
  }
}

///|
/// Render a section with heading and content.
pub fn render_section_common(
  buf : StringBuilder,
  section : @types.PlanSection,
  level : Int,
  style : RenderStyle,
) -> Unit {
  // Heading
  for i = 0; i < level; i = i + 1 {
    buf.write_string("#")
  }
  buf.write_string(" ")
  buf.write_string(section.heading)
  buf.write_string("\n\n")
  // Content
  render_content_common(buf, section.content, level, style)
}

///|
/// Render section content with style options.
pub fn render_content_common(
  buf : StringBuilder,
  content : @types.SectionContent,
  level : Int,
  style : RenderStyle,
) -> Unit {
  match content {
    @types.SectionContent::Text(s) => {
      buf.write_string(s)
      buf.write_string("\n\n")
    }
    @types.SectionContent::List(items) => {
      for item in items {
        buf.write_string("- ")
        buf.write_string(item.text)
        if item.description.length() > 0 {
          buf.write_string(": ")
          buf.write_string(item.description)
        }
        buf.write_string("\n")
      }
      buf.write_string("\n")
    }
    @types.SectionContent::Table(data) => render_table_common(buf, data, style)
    @types.SectionContent::Checklist(items) => {
      for item in items {
        if item.checked {
          buf.write_string("- [x] ")
        } else {
          buf.write_string("- [ ] ")
        }
        if item.priority > 0 {
          if style.priority_style == "bold" {
            buf.write_string("**P")
            buf.write_string(item.priority.to_string())
            buf.write_string("** ")
          } else {
            buf.write_string("[P")
            buf.write_string(item.priority.to_string())
            buf.write_string("] ")
          }
        }
        buf.write_string(item.label)
        if item.description.length() > 0 {
          if style.checklist_desc_newline {
            buf.write_string("\n  ")
          } else {
            buf.write_string(" - ")
          }
          buf.write_string(item.description)
        }
        buf.write_string("\n")
      }
      buf.write_string("\n")
    }
    @types.SectionContent::Code(lang, code) => {
      buf.write_string("```")
      buf.write_string(lang)
      buf.write_string("\n")
      buf.write_string(code)
      buf.write_string("\n```\n\n")
    }
    @types.SectionContent::Nested(sections) =>
      for section in sections {
        render_section_common(buf, section, level + 1, style)
      }
    @types.SectionContent::KeyValue(pairs) => {
      for pair in pairs {
        let (k, v) = pair
        buf.write_string("**")
        buf.write_string(k)
        buf.write_string(":** ")
        buf.write_string(v)
        buf.write_string("\n")
      }
      buf.write_string("\n")
    }
  }
}

///|
/// Render table with style options.
fn render_table_common(
  buf : StringBuilder,
  data : @types.TableData,
  style : RenderStyle,
) -> Unit {
  // Header row
  buf.write_string("|")
  for header in data.headers {
    buf.write_string(" ")
    buf.write_string(header)
    buf.write_string(" |")
  }
  buf.write_string("\n")
  // Separator row
  buf.write_string("|")
  for i, _ in data.headers {
    let align = if i < data.alignments.length() {
      data.alignments[i]
    } else {
      @types.TableAlign::default_left()
    }
    if style.table_separator_spaced {
      match align {
        Left => buf.write_string(" :--- |")
        Center => buf.write_string(" :---: |")
        Right => buf.write_string(" ---: |")
      }
    } else {
      match align {
        Left => buf.write_string(":---|")
        Center => buf.write_string(":---:|")
        Right => buf.write_string("---:|")
      }
    }
  }
  buf.write_string("\n")
  // Data rows
  for row in data.rows {
    buf.write_string("|")
    for cell in row {
      buf.write_string(" ")
      buf.write_string(cell)
      buf.write_string(" |")
    }
    buf.write_string("\n")
  }
  buf.write_string("\n")
}
