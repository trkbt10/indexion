// Document generation for README markdown.
// Generates markdown sections from component docs and token groups.

///|
/// Generate markdown documentation for an array of components.
/// Creates a formatted section with descriptions and examples.
pub fn generate_components_markdown(docs : Array[@types.ComponentDoc]) -> String {
  if docs.length() == 0 {
    return ""
  }
  let lines : Array[String] = []
  for doc in docs {
    let name = doc.get_name()
    if name.length() == 0 {
      continue
    }
    // Component heading
    lines.push("### " + name)
    lines.push("")
    // Description
    match doc.get_description() {
      Some(desc) => {
        lines.push(desc)
        lines.push("")
      }
      None =>
        match doc.get_file_tag() {
          Some(file_tag) => {
            lines.push(file_tag)
            lines.push("")
          }
          None => ()
        }
    }
    // Example
    match doc.get_example() {
      Some(example) => {
        lines.push(example)
        lines.push("")
      }
      None => ()
    }
  }
  join_lines(lines)
}

///|
/// Generate markdown documentation for token groups.
/// Creates a table format for each group.
pub fn generate_tokens_markdown(groups : Array[@types.TokenGroup]) -> String {
  if groups.length() == 0 {
    return ""
  }
  let lines : Array[String] = []
  for group in groups {
    // Group heading
    lines.push("### " + group.get_name())
    lines.push("")
    // Group description
    let desc = group.get_description()
    if desc.length() > 0 {
      lines.push("> " + desc)
      lines.push("")
    }
    // Token table
    let tokens = group.get_tokens()
    if tokens.length() > 0 {
      // Check if any token has a default value
      let has_defaults = has_any_default_value(tokens)
      if has_defaults {
        lines.push("| Token | CSS Variable | Default | Description |")
        lines.push("|-------|--------------|---------|-------------|")
      } else {
        lines.push("| Token | CSS Variable | Description |")
        lines.push("|-------|--------------|-------------|")
      }
      for token in tokens {
        if has_defaults {
          let default_val = match token.get_default_value() {
            Some(v) => "`" + v + "`"
            None => "-"
          }
          lines.push(
            "| `" +
            token.get_name() +
            "` | `" +
            token.get_css_var() +
            "` | " +
            default_val +
            " | " +
            token.get_description() +
            " |",
          )
        } else {
          lines.push(
            "| `" +
            token.get_name() +
            "` | `" +
            token.get_css_var() +
            "` | " +
            token.get_description() +
            " |",
          )
        }
      }
      lines.push("")
    }
  }
  join_lines(lines)
}

///|
/// Generate a component section with category header.
pub fn generate_component_section(
  category_name : String,
  category_description : String,
  docs : Array[@types.ComponentDoc],
) -> String {
  if docs.length() == 0 {
    return ""
  }
  let lines : Array[String] = []
  // Category heading
  lines.push("## " + category_name)
  lines.push("")
  if category_description.length() > 0 {
    lines.push("> " + category_description)
    lines.push("")
  }
  // Components
  for doc in docs {
    let name = doc.get_name()
    if name.length() == 0 {
      continue
    }
    lines.push("### " + name)
    lines.push("")
    match doc.get_description() {
      Some(desc) => {
        lines.push(desc)
        lines.push("")
      }
      None =>
        match doc.get_file_tag() {
          Some(file_tag) => {
            lines.push(file_tag)
            lines.push("")
          }
          None => ()
        }
    }
    match doc.get_example() {
      Some(example) => {
        lines.push(example)
        lines.push("")
      }
      None => ()
    }
  }
  join_lines(lines)
}

///|
/// Generate a token category section (e.g., "Base Tokens" or "Color Tokens").
pub fn generate_token_category(
  category_name : String,
  category_description : String,
  groups : Array[@types.TokenGroup],
) -> String {
  if groups.length() == 0 {
    return ""
  }
  let lines : Array[String] = []
  lines.push("## " + category_name)
  lines.push("")
  if category_description.length() > 0 {
    lines.push(category_description)
    lines.push("")
  }
  // Generate each group
  for group in groups {
    lines.push("### " + group.get_name())
    lines.push("")
    let desc = group.get_description()
    if desc.length() > 0 {
      lines.push("> " + desc)
      lines.push("")
    }
    let tokens = group.get_tokens()
    if tokens.length() > 0 {
      let has_defaults = has_any_default_value(tokens)
      if has_defaults {
        lines.push("| Token | CSS Variable | Default | Description |")
        lines.push("|-------|--------------|---------|-------------|")
      } else {
        lines.push("| Token | CSS Variable | Description |")
        lines.push("|-------|--------------|-------------|")
      }
      for token in tokens {
        if has_defaults {
          let default_val = match token.get_default_value() {
            Some(v) => "`" + v + "`"
            None => "-"
          }
          lines.push(
            "| `" +
            token.get_name() +
            "` | `" +
            token.get_css_var() +
            "` | " +
            default_val +
            " | " +
            token.get_description() +
            " |",
          )
        } else {
          lines.push(
            "| `" +
            token.get_name() +
            "` | `" +
            token.get_css_var() +
            "` | " +
            token.get_description() +
            " |",
          )
        }
      }
      lines.push("")
    }
  }
  join_lines(lines)
}

///|
/// Generate a simple import example for a component.
pub fn generate_import_example(
  component_name : String,
  export_path : String,
) -> String {
  "```tsx\nimport { " +
  component_name +
  " } from \"" +
  export_path +
  "\";\n```"
}

///|
/// Check if any token in the array has a default value.
fn has_any_default_value(tokens : Array[@types.TokenInfo]) -> Bool {
  for token in tokens {
    if token.get_default_value() is Some(_) {
      return true
    }
  }
  false
}

///|
/// Join lines with newline separator.
fn join_lines(lines : Array[String]) -> String {
  if lines.length() == 0 {
    return ""
  }
  let result : Array[Char] = []
  for i, line in lines {
    if i > 0 {
      result.push('\n')
    }
    for c in line.to_array() {
      result.push(c)
    }
  }
  String::from_array(result)
}
