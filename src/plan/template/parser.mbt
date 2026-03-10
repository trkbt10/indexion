///|
/// Parser for GitHub Issue Form templates (YAML).
/// Simplified YAML parser for issue form structure.

///|
/// Parse an issue form template from YAML string.
pub fn parse_issue_form(content : String) -> IssueFormTemplate {
  let template = IssueFormTemplate::new()
  let lines = split_lines(content)
  let mut i = 0
  let mut in_body = false
  let mut current_field : FormField? = None
  let mut indent_stack : Array[Int] = []
  while i < lines.length() {
    let line = lines[i]
    let trimmed = trim_string(line)
    let indent = count_indent(line)
    // Skip empty lines and comments
    if trimmed.length() == 0 || trimmed.has_prefix("#") {
      i = i + 1
      continue
    }
    // Top-level keys
    if indent == 0 {
      if trimmed.has_prefix("name:") {
        template.name = extract_yaml_value(trimmed, "name:")
      } else if trimmed.has_prefix("description:") {
        template.description = extract_yaml_value(trimmed, "description:")
      } else if trimmed.has_prefix("title:") {
        template.title = extract_yaml_value(trimmed, "title:")
      } else if trimmed.has_prefix("labels:") {
        // Could be inline array or block
        let val = extract_yaml_value(trimmed, "labels:")
        if val.has_prefix("[") {
          template.labels = parse_inline_array(val)
        } else {
          // Block array follows
          i = i + 1
          while i < lines.length() {
            let arr_line = lines[i]
            let arr_trimmed = trim_string(arr_line)
            if arr_trimmed.has_prefix("- ") {
              template.labels.push(
                trim_string(substring(arr_trimmed, 2, arr_trimmed.length())),
              )
              i = i + 1
            } else if count_indent(arr_line) > 0 && arr_trimmed.length() > 0 {
              i = i + 1
            } else {
              break
            }
          }
          continue
        }
      } else if trimmed.has_prefix("assignees:") {
        let val = extract_yaml_value(trimmed, "assignees:")
        if val.has_prefix("[") {
          template.assignees = parse_inline_array(val)
        }
      } else if trimmed == "body:" {
        in_body = true
        indent_stack = []
      }
      i = i + 1
      continue
    }
    // Inside body block
    if in_body {
      if trimmed.has_prefix("- type:") {
        // Save previous field
        match current_field {
          Some(field) => template.body.push(field)
          None => ()
        }
        // Start new field
        let field_type = extract_yaml_value(trimmed, "- type:")
        current_field = Some(create_empty_field(field_type))
        indent_stack = [indent]
      } else if trimmed.has_prefix("type:") && indent > 0 {
        // Type on separate line after -
        let field_type = extract_yaml_value(trimmed, "type:")
        current_field = Some(create_empty_field(field_type))
      } else {
        match current_field {
          Some(field) =>
            current_field = Some(update_field(field, trimmed, lines, i))
          None => ()
        }
      }
    }
    i = i + 1
  }
  // Add last field
  match current_field {
    Some(field) => template.body.push(field)
    None => ()
  }
  template
}

///|
fn create_empty_field(field_type : String) -> FormField {
  match field_type {
    "markdown" => FormField::Markdown({ value: "" })
    "textarea" =>
      FormField::Textarea({
        id: "",
        label: "",
        description: "",
        placeholder: "",
        value: "",
        render: "",
        required: false,
      })
    "input" =>
      FormField::Input({
        id: "",
        label: "",
        description: "",
        placeholder: "",
        value: "",
        required: false,
      })
    "dropdown" =>
      FormField::Dropdown({
        id: "",
        label: "",
        description: "",
        options: [],
        default_index: 0,
        multiple: false,
        required: false,
      })
    "checkboxes" =>
      FormField::Checkboxes({
        id: "",
        label: "",
        description: "",
        options: [],
        required: false,
      })
    _ =>
      // Default to markdown for unknown types
      FormField::Markdown({ value: "" })
  }
}

///|
fn update_field(
  field : FormField,
  line : String,
  _lines : Array[String],
  _idx : Int,
) -> FormField {
  match field {
    FormField::Markdown(md) =>
      if line.has_prefix("value:") {
        let val = extract_yaml_value(line, "value:")
        FormField::Markdown({ value: val })
      } else {
        field
      }
    FormField::Textarea(ta) => {
      let mut updated = ta
      if line.has_prefix("id:") {
        updated = { ..updated, id: extract_yaml_value(line, "id:") }
      } else if line.has_prefix("label:") {
        updated = { ..updated, label: extract_yaml_value(line, "label:") }
      } else if line.has_prefix("description:") {
        updated = {
          ..updated,
          description: extract_yaml_value(line, "description:"),
        }
      } else if line.has_prefix("placeholder:") {
        updated = {
          ..updated,
          placeholder: extract_yaml_value(line, "placeholder:"),
        }
      } else if line.has_prefix("value:") {
        updated = { ..updated, value: extract_yaml_value(line, "value:") }
      } else if line.has_prefix("render:") {
        updated = { ..updated, render: extract_yaml_value(line, "render:") }
      } else if line.has_prefix("required:") {
        updated = {
          ..updated,
          required: extract_yaml_value(line, "required:") == "true",
        }
      }
      FormField::Textarea(updated)
    }
    FormField::Input(inp) => {
      let mut updated = inp
      if line.has_prefix("id:") {
        updated = { ..updated, id: extract_yaml_value(line, "id:") }
      } else if line.has_prefix("label:") {
        updated = { ..updated, label: extract_yaml_value(line, "label:") }
      } else if line.has_prefix("description:") {
        updated = {
          ..updated,
          description: extract_yaml_value(line, "description:"),
        }
      } else if line.has_prefix("placeholder:") {
        updated = {
          ..updated,
          placeholder: extract_yaml_value(line, "placeholder:"),
        }
      } else if line.has_prefix("value:") {
        updated = { ..updated, value: extract_yaml_value(line, "value:") }
      } else if line.has_prefix("required:") {
        updated = {
          ..updated,
          required: extract_yaml_value(line, "required:") == "true",
        }
      }
      FormField::Input(updated)
    }
    FormField::Dropdown(dd) => {
      let mut updated = dd
      if line.has_prefix("id:") {
        updated = { ..updated, id: extract_yaml_value(line, "id:") }
      } else if line.has_prefix("label:") {
        updated = { ..updated, label: extract_yaml_value(line, "label:") }
      } else if line.has_prefix("description:") {
        updated = {
          ..updated,
          description: extract_yaml_value(line, "description:"),
        }
      } else if line.has_prefix("multiple:") {
        updated = {
          ..updated,
          multiple: extract_yaml_value(line, "multiple:") == "true",
        }
      } else if line.has_prefix("required:") {
        updated = {
          ..updated,
          required: extract_yaml_value(line, "required:") == "true",
        }
      } else if line.has_prefix("- ") {
        // Option item
        let opt = trim_string(substring(line, 2, line.length()))
        updated.options.push(opt)
      }
      FormField::Dropdown(updated)
    }
    FormField::Checkboxes(cb) => {
      let mut updated = cb
      if line.has_prefix("id:") {
        updated = { ..updated, id: extract_yaml_value(line, "id:") }
      } else if line.has_prefix("label:") {
        updated = { ..updated, label: extract_yaml_value(line, "label:") }
      } else if line.has_prefix("description:") {
        updated = {
          ..updated,
          description: extract_yaml_value(line, "description:"),
        }
      } else if line.has_prefix("required:") {
        updated = {
          ..updated,
          required: extract_yaml_value(line, "required:") == "true",
        }
      } else if line.has_prefix("- label:") {
        let label = extract_yaml_value(line, "- label:")
        updated.options.push({ label, required: false })
      }
      FormField::Checkboxes(updated)
    }
  }
}

///|
fn extract_yaml_value(line : String, prefix : String) -> String {
  let chars = line.to_array()
  let prefix_chars = prefix.to_array()
  // Find prefix
  let mut start = 0
  for i = 0; i < chars.length() - prefix_chars.length() + 1; i = i + 1 {
    let mut found = true
    for j = 0; j < prefix_chars.length(); j = j + 1 {
      if chars[i + j] != prefix_chars[j] {
        found = false
        break
      }
    }
    if found {
      start = i + prefix_chars.length()
      break
    }
  }
  // Skip whitespace
  while start < chars.length() && (chars[start] == ' ' || chars[start] == '\t') {
    start = start + 1
  }
  // Handle quoted strings
  if start < chars.length() && (chars[start] == '"' || chars[start] == '\'') {
    let quote = chars[start]
    start = start + 1
    let result : Array[Char] = []
    while start < chars.length() && chars[start] != quote {
      result.push(chars[start])
      start = start + 1
    }
    return String::from_array(result)
  }
  // Unquoted value
  let result : Array[Char] = []
  for i = start; i < chars.length(); i = i + 1 {
    result.push(chars[i])
  }
  trim_string(String::from_array(result))
}

///|
fn parse_inline_array(s : String) -> Array[String] {
  let result : Array[String] = []
  let chars = s.to_array()
  if chars.length() < 2 {
    return result
  }
  // Skip [ and ]
  let mut start = 1
  let end = chars.length() - 1
  let current : Array[Char] = []
  let mut in_quote = false
  let mut quote_char : Char = '"'
  while start < end {
    let c = chars[start]
    if not(in_quote) && (c == '"' || c == '\'') {
      in_quote = true
      quote_char = c
    } else if in_quote && c == quote_char {
      in_quote = false
    } else if not(in_quote) && c == ',' {
      let item = trim_string(String::from_array(current))
      if item.length() > 0 {
        result.push(item)
      }
      current.clear()
    } else {
      current.push(c)
    }
    start = start + 1
  }
  if current.length() > 0 {
    let item = trim_string(String::from_array(current))
    if item.length() > 0 {
      result.push(item)
    }
  }
  result
}

// String utilities

///|
fn split_lines(s : String) -> Array[String] {
  let lines : Array[String] = []
  let chars = s.to_array()
  let current : Array[Char] = []
  for c in chars {
    if c == '\n' {
      lines.push(String::from_array(current))
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

///|
fn substring(s : String, start : Int, end : Int) -> String {
  let chars = s.to_array()
  let result : Array[Char] = []
  let actual_end = if end > chars.length() { chars.length() } else { end }
  for i = start; i < actual_end; i = i + 1 {
    result.push(chars[i])
  }
  String::from_array(result)
}

///|
fn count_indent(s : String) -> Int {
  let chars = s.to_array()
  let mut count = 0
  for c in chars {
    if c == ' ' {
      count = count + 1
    } else if c == '\t' {
      count = count + 2
    } else {
      break
    }
  }
  count
}

///|
/// Load and parse issue form template from file.
pub fn load_issue_form(path : String) -> IssueFormTemplate? {
  try {
    let content = @fs.read_file_to_string(path)
    Some(parse_issue_form(content))
  } catch {
    _ => None
  }
}
