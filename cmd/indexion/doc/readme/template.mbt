///|
/// Template processing for documentation generation.
/// Supports simple placeholder substitution:
/// - `{{include:path}}` - Include file contents
/// - `{{packages}}` - All discovered packages (uses CLI --include/--exclude for filtering)

///|
/// Context for template rendering.
pub struct TemplateContext {
  base_dir : String
  packages : Array[(PackageInfo, ExtractedDoc)]
}

///|
/// Create a new template rendering context.
pub fn TemplateContext::new(
  base_dir : String,
  packages : Array[(PackageInfo, ExtractedDoc)],
) -> TemplateContext {
  { base_dir, packages, }
}

///|
/// Render a template string with the given context.
pub fn render_template(template : String, ctx : TemplateContext) -> String {
  let result = StringBuilder()
  let chars = template.to_array()
  let mut i = 0
  while i < chars.length() {
    if i + 1 < chars.length() && chars[i] == '{' && chars[i + 1] == '{' {
      let start = i + 2
      let mut end = start
      while end + 1 < chars.length() &&
            !(chars[end] == '}' && chars[end + 1] == '}') {
        end = end + 1
      }
      if end + 1 < chars.length() {
        let placeholder = extract_substring(chars, start, end)
        let replacement = resolve_placeholder(placeholder, ctx)
        result.write_string(replacement)
        i = end + 2
      } else {
        result.write_char(chars[i])
        i = i + 1
      }
    } else {
      result.write_char(chars[i])
      i = i + 1
    }
  }
  result.to_string()
}

///|
fn extract_substring(chars : Array[Char], start : Int, end : Int) -> String {
  let buf : Array[Char] = []
  for j = start; j < end; j = j + 1 {
    buf.push(chars[j])
  }
  String::from_array(buf)
}

///|
/// Resolve a placeholder to its value.
fn resolve_placeholder(placeholder : String, ctx : TemplateContext) -> String {
  if placeholder.has_prefix("include:") {
    let path = @common.substring(placeholder, 8, placeholder.length())
    resolve_include(path, ctx.base_dir)
  } else {
    match placeholder {
      "packages" => render_packages(ctx.packages, ctx.base_dir)
      "module_doc" => render_module_docs(ctx.packages)
      _ => "{{" + placeholder + "}}"
    }
  }
}

///|
/// Render {{module_doc}} - outputs only module-level documentation.
fn render_module_docs(packages : Array[(PackageInfo, ExtractedDoc)]) -> String {
  let buf = StringBuilder()
  for i, item in packages {
    let (_, doc) = item
    // Only output non-empty content that looks like module documentation
    let content = doc.content
    if content.length() > 0 && is_module_doc_content(content) {
      if buf.to_string().length() > 0 {
        buf.write_string("\n\n")
      }
      buf.write_string(content)
    }
    let _ = i
  }
  buf.to_string()
}

///|
/// Check if content looks like module-level documentation.
/// Note: doc content is already cleaned by KGF lexer strip/skip_value,
/// so we just check for non-empty content.
fn is_module_doc_content(content : String) -> Bool {
  content.length() > 0
}

///|
/// Resolve {{include:path}} placeholder.
/// Tries CWD-relative first, then base_dir-relative as fallback.
/// Prints a warning instead of silently returning empty on failure.
fn resolve_include(path : String, base_dir : String) -> String {
  if path.has_prefix("/") {
    return @fs.read_file_to_string(path) catch {
      _ => {
        println("Warning: {{include:" + path + "}} — file not found")
        ""
      }
    }
  }
  // Try CWD-relative first (plan convention), then base_dir-relative
  @fs.read_file_to_string(path) catch {
    _ =>
      @fs.read_file_to_string(base_dir + "/" + path) catch {
        _ => {
          println("Warning: {{include:" + path + "}} — file not found")
          ""
        }
      }
  }
}

///|
/// Render {{packages}} - outputs each package's documentation content.
fn render_packages(
  packages : Array[(PackageInfo, ExtractedDoc)],
  base_dir : String,
) -> String {
  if packages.length() == 0 {
    return ""
  }
  let buf = StringBuilder()
  for i, item in packages {
    let (pkg, doc) = item
    if i > 0 {
      buf.write_string("\n---\n\n")
    }
    // Output package path as heading
    let rel_path = @common.make_relative_path(pkg.path, base_dir)
    buf.write_string("### ")
    buf.write_string(rel_path)
    buf.write_string("\n\n")
    // Output document content
    buf.write_string(doc.content)
    buf.write_char('\n')
  }
  buf.to_string()
}

// use @common (SoT): make_relative_path

///|
/// Load and render a template file.
pub fn render_template_file(
  template_path : String,
  ctx : TemplateContext,
) -> String? {
  try {
    let template = @fs.read_file_to_string(template_path)
    Some(render_template(template, ctx))
  } catch {
    _ => None
  }
}
