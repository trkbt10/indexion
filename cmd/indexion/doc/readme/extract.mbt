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
  let docs : Array[String] = []
  // First, look for module_doc notes (preferred)
  for note in graph.get_all_notes() {
    if note.note_type == "module_doc" {
      // Check if note belongs to this package
      if note.module_id.has_prefix(pkg_path) ||
        pkg_path.has_prefix(note.module_id) {
        if note.content.length() > 0 {
          docs.push(note.content)
        }
      }
    }
  }
  // If we found module docs, return them
  if docs.length() > 0 {
    return join_with_newlines(docs)
  }
  // Fallback: look for documentation in edge attrs (legacy behavior)
  // Note: doc values are already cleaned by lexer strip/skip_value
  for edge in graph.get_edges() {
    // Check if edge belongs to this package
    if edge.from.has_prefix(pkg_path) || pkg_path.has_prefix(edge.from) {
      match edge.attrs.get("doc") {
        Some(doc) => if doc.length() > 0 { docs.push(doc) }
        None => ()
      }
    }
  }
  if docs.length() > 0 {
    join_with_newlines(docs)
  } else {
    ""
  }
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
/// Extract summary from doc content (text before second ## heading).
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
