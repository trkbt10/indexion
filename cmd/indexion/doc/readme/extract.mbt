///|
/// Documentation extraction using KGF-based analysis.

///|
/// Extracted documentation from a package.
pub struct ExtractedDoc {
  title : String?
  content : String
  source_path : String
}

///|
/// Create a new extracted documentation value.
pub fn ExtractedDoc::new(
  title : String?,
  content : String,
  source_path : String,
) -> ExtractedDoc {
  { title, content, source_path }
}

///|
/// Extract documentation from a package using KGF analysis.
pub fn extract_package_doc(
  pkg : PackageInfo,
  specs : Map[String, @kgf_types.KGFSpec],
) -> ExtractedDoc? {
  if pkg.files.length() == 0 {
    return None
  }
  // Collect file contents
  let file_contents : Array[(String, String)] = []
  for path in pkg.files {
    try {
      let content = @fs.read_file_to_string(path)
      file_contents.push((path, content))
    } catch {
      _ => ()
    }
  }
  if file_contents.length() == 0 {
    return None
  }
  // Build documentation using KGF pipeline
  let config = @build.DocConfig::new(
    file_contents,
    specs,
    options=@render.RenderOptions::new(
      format=@render.OutputFormat::markdown(),
      include_diagrams=false,
    ),
  )
  let (output, graph) = @build.build_with_graph(config)
  // Extract module-level documentation from graph
  let doc_content = extract_module_docs(graph, pkg.path)
  if doc_content.length() > 0 {
    let title = extract_title_from_content(doc_content)
    Some(ExtractedDoc::new(title, doc_content, pkg.files[0]))
  } else {
    // Fallback to rendered output
    let markdown = output.to_markdown()
    if markdown.length() > 0 {
      Some(ExtractedDoc::new(None, markdown, pkg.files[0]))
    } else {
      None
    }
  }
}

///|
/// Extract module-level documentation from CodeGraph.
/// Looks for module_doc notes first, then falls back to edge attrs.
fn extract_module_docs(graph : @graph.CodeGraph, pkg_path : String) -> String {
  let buf = StringBuilder::new()
  let seen : Map[String, Bool] = {}
  // Module-level documentation (package overview)
  let mut has_overview = false
  for note in graph.get_all_notes() {
    if note.note_type == "module_doc" {
      if note.module_id.has_prefix(pkg_path) ||
        pkg_path.has_prefix(note.module_id) {
        if note.content.length() > 0 && !seen.contains(note.content) {
          seen.set(note.content, true)
          buf.write_string(note.content)
          buf.write_string("\n\n")
          has_overview = true
        }
      }
    }
  }
  // Collect documented symbols, grouped by kind from the graph
  let symbols : Array[(String, String, String)] = [] // (name, kind, doc)
  let mut total_symbols = 0
  for entry in graph.get_symbols() {
    let sym = entry.1
    if !sym.module_id.has_prefix(pkg_path) &&
      !pkg_path.has_prefix(sym.module_id) {
      continue
    }
    let dedup_key = sym.kind + ":" + sym.name
    if seen.contains(dedup_key) {
      continue
    }
    seen.set(dedup_key, true)
    total_symbols += 1
    let doc = match sym.doc {
      Some(d) => d
      None => ""
    }
    // Only include symbols with meaningful doc
    if doc.length() > 20 {
      symbols.push((sym.name, sym.kind, doc))
    }
  }
  // Sort by doc length (most documented = most important)
  symbols.sort_by(fn(a, b) { b.2.length() - a.2.length() })
  if symbols.length() > 0 {
    buf.write_string("## API\n\n")
    for item in symbols {
      let (name, kind, doc) = item
      buf.write_string("- **`")
      buf.write_string(name)
      buf.write_string("`** (")
      buf.write_string(kind)
      buf.write_string(") — ")
      buf.write_string(first_doc_line(doc))
      buf.write_string("\n")
    }
    buf.write_string("\n")
  }
  // Fallback: edge attrs (legacy)
  if !has_overview && total_symbols == 0 {
    for edge in graph.get_edges() {
      if edge.from.has_prefix(pkg_path) || pkg_path.has_prefix(edge.from) {
        match edge.attrs.get("doc") {
          Some(doc) =>
            if doc.length() > 0 && !seen.contains(doc) {
              seen.set(doc, true)
              buf.write_string(doc)
              buf.write_string("\n\n")
            }
          None => ()
        }
      }
    }
  }
  @common.trim_ascii_spaces(buf.to_string())
}

///|
fn first_doc_line(doc : String) -> String {
  for line in @common.split_lines(doc) {
    let trimmed = @common.trim_ascii_spaces(line)
    if trimmed.length() > 0 {
      return trimmed
    }
  }
  doc
}

///|
/// Extract title from document content (first level-1 heading via KGF).
fn extract_title_from_content(content : String) -> String? {
  let headings = tokenize_and_extract_headings(content)
  for h in headings {
    if h.level == 1 {
      return Some(h.text)
    }
  }
  None
}

///|
/// Extract summary text from doc content (text before second level-2 heading).
/// Uses KGF headings to identify heading boundaries.
pub fn extract_summary(content : String) -> String {
  let headings = tokenize_and_extract_headings(content)
  let lines = @common.split_lines(content)
  // Find title line (level 1) and first two level-2 headings
  let mut title_line = -1
  let mut h2_count = 0
  let mut second_h2_line = lines.length() + 1
  for h in headings {
    if h.level == 1 && title_line < 0 {
      title_line = h.line
    }
    if h.level == 2 {
      h2_count += 1
      if h2_count > 1 {
        second_h2_line = h.line
        break
      }
    }
  }
  let result : Array[String] = []
  for i, line in lines {
    let line_num = i + 1
    if line_num == title_line {
      continue
    }
    if line_num >= second_h2_line {
      break
    }
    result.push(line)
  }
  @common.join_lines(result)
}
