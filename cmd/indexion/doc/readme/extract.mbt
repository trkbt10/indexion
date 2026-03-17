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
        if note.content.length() > 0 && not(seen.contains(note.content)) {
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
    if not(sym.module_id.has_prefix(pkg_path)) &&
      not(pkg_path.has_prefix(sym.module_id)) {
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
    let max_listed = 15
    let mut listed = 0
    for item in symbols {
      if listed >= max_listed {
        break
      }
      let (name, kind, doc) = item
      buf.write_string("- **`")
      buf.write_string(name)
      buf.write_string("`** (")
      buf.write_string(kind)
      buf.write_string(") — ")
      buf.write_string(first_doc_line(doc))
      buf.write_string("\n")
      listed += 1
    }
    if total_symbols > listed {
      buf.write_string("\nAnd ")
      buf.write_string((total_symbols - listed).to_string())
      buf.write_string(" more symbols.\n")
    }
    buf.write_string("\n")
  } else if total_symbols > 0 && not(has_overview) {
    buf.write_string(total_symbols.to_string())
    buf.write_string(" public symbols.\n\n")
  }
  // Fallback: edge attrs (legacy)
  if not(has_overview) && total_symbols == 0 {
    for edge in graph.get_edges() {
      if edge.from.has_prefix(pkg_path) || pkg_path.has_prefix(edge.from) {
        match edge.attrs.get("doc") {
          Some(doc) =>
            if doc.length() > 0 && not(seen.contains(doc)) {
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
/// Extract title from document content (first # heading).
fn extract_title_from_content(content : String) -> String? {
  let lines = @common.split_lines(content)
  for line in lines {
    if line.has_prefix("# ") {
      let chars = line.to_array()
      let result : Array[Char] = []
      for i = 2; i < chars.length(); i = i + 1 {
        result.push(chars[i])
      }
      return Some(String::from_array(result))
    }
  }
  None
}

// use @common (SoT): split_lines

///|
fn join_with_newlines(parts : Array[String]) -> String {
  let buf = StringBuilder::new()
  for i, part in parts {
    if i > 0 {
      buf.write_string("\n\n")
    }
    buf.write_string(part)
  }
  buf.to_string()
}

///|
/// Extract summary text from doc content (text before second ## heading).
pub fn extract_summary(content : String) -> String {
  let lines = @common.split_lines(content)
  let result : Array[String] = []
  let mut heading_count = 0
  for line in lines {
    if line.has_prefix("# ") {
      // Skip main title
      continue
    }
    if line.has_prefix("## ") {
      heading_count = heading_count + 1
      if heading_count > 1 {
        break
      }
    }
    result.push(line)
  }
  join_lines(result)
}

///|
fn join_lines(lines : Array[String]) -> String {
  let buf = StringBuilder::new()
  for i, line in lines {
    if i > 0 {
      buf.write_char('\n')
    }
    buf.write_string(line)
  }
  buf.to_string()
}
