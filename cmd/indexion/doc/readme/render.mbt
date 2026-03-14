///|
/// Output format for documentation.
pub enum OutputFormat {
  Markdown
  Json
  Raw
}

///|
/// Parse an output format name into an OutputFormat variant.
pub fn OutputFormat::from_string(s : String) -> OutputFormat {
  match s {
    "json" => Json
    "raw" => Raw
    _ => Markdown
  }
}

///|
/// Render extracted docs as Markdown.
pub fn render_markdown(docs : Array[(PackageInfo, ExtractedDoc)]) -> String {
  let buf = StringBuilder::new()
  for i, item in docs {
    let (pkg, doc) = item
    if i > 0 {
      buf.write_string("\n---\n\n")
    }
    buf.write_string("## ")
    buf.write_string(pkg.name)
    buf.write_string("\n\n")
    buf.write_string(doc.content)
    buf.write_char('\n')
  }
  buf.to_string()
}

///|
/// Render extracted docs as JSON.
pub fn render_json(docs : Array[(PackageInfo, ExtractedDoc)]) -> String {
  let buf = StringBuilder::new()
  buf.write_string("[\n")
  for i, item in docs {
    let (pkg, doc) = item
    if i > 0 {
      buf.write_string(",\n")
    }
    buf.write_string("  {\n")
    buf.write_string("    \"path\": \"")
    buf.write_string(escape_json_string(pkg.path))
    buf.write_string("\",\n")
    buf.write_string("    \"name\": \"")
    buf.write_string(escape_json_string(pkg.name))
    buf.write_string("\",\n")
    match doc.title {
      Some(t) => {
        buf.write_string("    \"title\": \"")
        buf.write_string(escape_json_string(t))
        buf.write_string("\",\n")
      }
      None => ()
    }
    buf.write_string("    \"content\": \"")
    buf.write_string(escape_json_string(doc.content))
    buf.write_string("\"\n")
    buf.write_string("  }")
  }
  buf.write_string("\n]\n")
  buf.to_string()
}

///|
fn escape_json_string(s : String) -> String {
  let buf = StringBuilder::new()
  for c in s {
    match c {
      '"' => buf.write_string("\\\"")
      '\\' => buf.write_string("\\\\")
      '\n' => buf.write_string("\\n")
      '\r' => buf.write_string("\\r")
      '\t' => buf.write_string("\\t")
      _ => buf.write_char(c)
    }
  }
  buf.to_string()
}

///|
/// Render extracted docs as raw text (just the content blocks).
pub fn render_raw(docs : Array[(PackageInfo, ExtractedDoc)]) -> String {
  let buf = StringBuilder::new()
  for i, item in docs {
    let (_, doc) = item
    if i > 0 {
      buf.write_string("\n\n")
    }
    buf.write_string(doc.content)
  }
  buf.to_string()
}

///|
/// Write output to file or stdout based on config.
pub fn write_output(
  content : String,
  output_path : String?,
  to_stdout : Bool,
) -> Unit {
  if to_stdout {
    println(content)
  } else {
    match output_path {
      Some(path) =>
        try {
          @fs.write_string_to_file(path, content)
          println("Written to: " + path)
        } catch {
          e => println("Error writing " + path + ": " + e.to_string())
        }
      None => println(content)
    }
  }
}

///|
/// Write per-package README files.
pub fn write_per_package(docs : Array[(PackageInfo, ExtractedDoc)]) -> Unit {
  for item in docs {
    let (pkg, doc) = item
    let readme_path = pkg.path + "/README.md"
    try {
      @fs.write_string_to_file(readme_path, doc.content + "\n")
      println("  Generated: " + readme_path)
    } catch {
      e => println("  Error writing " + readme_path + ": " + e.to_string())
    }
  }
}
