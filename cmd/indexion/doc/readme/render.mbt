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
/// Render extracted docs as JSON using Json type.
pub fn render_json(docs : Array[(PackageInfo, ExtractedDoc)]) -> String {
  let arr : Array[Json] = docs
    .iter()
    .map(fn(item) {
      let (pkg, doc) = item
      let obj : Map[String, Json] = {}
      obj.set("path", pkg.path.to_json())
      obj.set("name", pkg.name.to_json())
      match doc.title {
        Some(t) => obj.set("title", t.to_json())
        None => ()
      }
      obj.set("content", doc.content.to_json())
      Json::object(obj)
    })
    .collect()
  Json::array(arr).stringify(indent=2)
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
/// Write per-package README files with package header.
/// Skips packages that already have a README.md to avoid overwriting
/// hand-written documentation.
pub fn write_per_package(docs : Array[(PackageInfo, ExtractedDoc)]) -> Unit {
  for item in docs {
    let (pkg, doc) = item
    let readme_path = pkg.path + "/README.md"
    if @fs.path_exists(readme_path) {
      println("  Skipped (exists): " + readme_path)
      continue
    }
    let buf = StringBuilder::new()
    buf.write_string("# ")
    buf.write_string(pkg.name)
    buf.write_string("\n\n")
    buf.write_string(doc.content)
    buf.write_string("\n")
    try {
      @fs.write_string_to_file(readme_path, buf.to_string())
      println("  Generated: " + readme_path)
    } catch {
      e =>
        println("  Error writing " + readme_path + ": " + @debug.to_string(e))
    }
  }
}
