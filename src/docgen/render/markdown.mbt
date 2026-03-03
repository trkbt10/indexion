// Markdown rendering for documentation.

///|
/// Render complete documentation to markdown.
pub fn render_markdown(
  graph : @graph.CodeGraph,
  options : RenderOptions,
) -> DocOutput {
  // Extract data from graph
  let decls = @query.extract_declarations(graph)
  let deps = @query.extract_module_deps(graph)
  let calls = @query.extract_call_graph(graph)
  let hierarchy = @query.extract_type_hierarchy(graph)
  let ref_counts = @query.count_references(graph)
  // Render API reference
  let api_ref = render_api_reference(decls, ref_counts)
  // Generate diagrams if requested
  let dep_diagram : String? = if options.include_diagrams &&
    options.include_deps {
    let diagram = @diagram.generate_dep_diagram(deps)
    if diagram.length() > 0 {
      Some(diagram)
    } else {
      None
    }
  } else {
    None
  }
  let call_diagram : String? = if options.include_diagrams &&
    options.include_calls {
    let diagram = @diagram.generate_call_diagram(calls)
    if diagram.length() > 0 {
      Some(diagram)
    } else {
      None
    }
  } else {
    None
  }
  let hier_diagram : String? = if options.include_diagrams &&
    options.include_hierarchy {
    let diagram = @diagram.generate_hierarchy_diagram(hierarchy)
    if diagram.length() > 0 {
      Some(diagram)
    } else {
      None
    }
  } else {
    None
  }
  // Render cross references
  let cross_refs : String? = if options.include_refs {
    let refs = render_cross_references(decls, ref_counts)
    if refs.length() > 0 {
      Some(refs)
    } else {
      None
    }
  } else {
    None
  }
  DocOutput::new(
    api_ref,
    dependency_diagram=dep_diagram,
    call_graph=call_diagram,
    type_hierarchy=hier_diagram,
    cross_references=cross_refs,
  )
}

///|
/// Render API reference section.
pub fn render_api_reference(
  decls : Array[@query.SymbolDecl],
  ref_counts : Map[String, Int],
) -> String {
  if decls.length() == 0 {
    return ""
  }
  let lines : Array[String] = []
  lines.push("# API Reference")
  lines.push("")
  // Group by kind
  let by_kind : Map[String, Array[@query.SymbolDecl]] = {}
  for decl in decls {
    match by_kind.get(decl.kind) {
      Some(arr) => arr.push(decl)
      None => by_kind.set(decl.kind, [decl])
    }
  }
  // Render each kind
  let kinds = [
    "Class", "Interface", "Struct", "Enum", "Type", "Function", "Variable",
  ]
  for kind in kinds {
    match by_kind.get(kind) {
      Some(symbols) =>
        if symbols.length() > 0 {
          lines.push("## " + pluralize(kind))
          lines.push("")
          for sym in symbols {
            render_symbol(sym, ref_counts, lines)
          }
        }
      None => ()
    }
  }
  // Render remaining kinds
  for entry in by_kind {
    let kind = entry.0
    let symbols = entry.1
    if not(kinds.contains(kind)) && symbols.length() > 0 {
      lines.push("## " + pluralize(kind))
      lines.push("")
      for sym in symbols {
        render_symbol(sym, ref_counts, lines)
      }
    }
  }
  join_lines(lines)
}

///|
/// Render a single symbol.
fn render_symbol(
  sym : @query.SymbolDecl,
  ref_counts : Map[String, Int],
  lines : Array[String],
) -> Unit {
  lines.push("### " + sym.name)
  lines.push("")
  // Documentation
  match sym.doc {
    Some(doc) => {
      lines.push(clean_doc(doc))
      lines.push("")
    }
    None => ()
  }
  // Reference count
  let refs = ref_counts.get(sym.id).unwrap_or(0)
  if refs > 0 {
    lines.push("**References:** " + refs.to_string())
    lines.push("")
  }
  // Module info
  lines.push("**Module:** `" + sym.module_id + "`")
  lines.push("")
}

///|
/// Render cross references table.
pub fn render_cross_references(
  decls : Array[@query.SymbolDecl],
  ref_counts : Map[String, Int],
) -> String {
  // Filter to symbols with references
  let referenced : Array[@query.SymbolDecl] = []
  for decl in decls {
    let count = ref_counts.get(decl.id).unwrap_or(0)
    if count > 0 {
      referenced.push(decl)
    }
  }
  if referenced.length() == 0 {
    return ""
  }
  // Sort by reference count (descending)
  referenced.sort_by(fn(a, b) {
    let ca = ref_counts.get(a.id).unwrap_or(0)
    let cb = ref_counts.get(b.id).unwrap_or(0)
    cb - ca
  })
  let lines : Array[String] = []
  lines.push("| Symbol | Kind | References |")
  lines.push("|--------|------|------------|")
  for sym in referenced {
    let count = ref_counts.get(sym.id).unwrap_or(0)
    lines.push(
      "| `" + sym.name + "` | " + sym.kind + " | " + count.to_string() + " |",
    )
  }
  join_lines(lines)
}

///|
/// Clean documentation comment.
fn clean_doc(doc : String) -> String {
  let chars = doc.to_array()
  let result : Array[Char] = []
  let mut i = 0
  let len = chars.length()
  // Skip leading /** or ///|
  while i < len {
    if i + 2 < len &&
      chars[i] == '/' &&
      chars[i + 1] == '*' &&
      chars[i + 2] == '*' {
      i = i + 3
      continue
    }
    if i + 3 < len &&
      chars[i] == '/' &&
      chars[i + 1] == '/' &&
      chars[i + 2] == '/' &&
      chars[i + 3] == '|' {
      i = i + 4
      continue
    }
    break
  }
  // Skip whitespace
  while i < len && (chars[i] == ' ' || chars[i] == '\t' || chars[i] == '\n') {
    i = i + 1
  }
  // Copy content
  while i < len {
    // Stop at */
    if i + 1 < len && chars[i] == '*' && chars[i + 1] == '/' {
      break
    }
    // Skip leading * on lines
    if result.length() > 0 &&
      result[result.length() - 1] == '\n' &&
      chars[i] == '*' &&
      (i + 1 >= len || chars[i + 1] == ' ') {
      i = i + 1
      if i < len && chars[i] == ' ' {
        i = i + 1
      }
      continue
    }
    result.push(chars[i])
    i = i + 1
  }
  // Trim trailing whitespace
  while result.length() > 0 {
    let last = result[result.length() - 1]
    if last == ' ' || last == '\t' || last == '\n' || last == '\r' {
      let _ = result.pop()
    } else {
      break
    }
  }
  String::from_array(result)
}

///|
/// Pluralize a kind name.
fn pluralize(kind : String) -> String {
  // Handle special cases
  match kind {
    "Class" => "Classes"
    "Interface" => "Interfaces"
    "Struct" => "Structs"
    "Enum" => "Enums"
    "Type" => "Types"
    "Function" => "Functions"
    "Variable" => "Variables"
    _ => kind + "s"
  }
}

///|
/// Join lines with newline.
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
