// Mermaid diagram generation from query results.

///|
/// Generate a module dependency diagram in Mermaid format.
/// Output: graph LR with module dependencies as arrows.
pub fn generate_dep_diagram(
  deps : Array[@query.ModuleDep],
  title? : String = "Module Dependencies",
) -> String {
  if deps.length() == 0 {
    return ""
  }
  let lines : Array[String] = []
  lines.push("```mermaid")
  lines.push("---")
  lines.push("title: " + title)
  lines.push("---")
  lines.push("graph LR")
  // Collect unique nodes and assign short IDs
  let node_ids : Map[String, String] = {}
  let mut id_counter = 0
  for dep in deps {
    if not(node_ids.contains(dep.from)) {
      node_ids.set(dep.from, "N" + id_counter.to_string())
      id_counter = id_counter + 1
    }
    if not(node_ids.contains(dep.to)) {
      node_ids.set(dep.to, "N" + id_counter.to_string())
      id_counter = id_counter + 1
    }
  }
  // Generate node definitions
  for entry in node_ids {
    let name = entry.0
    let id = entry.1
    let label = shorten_module_name(name)
    lines.push("  " + id + "[" + escape_mermaid(label) + "]")
  }
  // Generate edges
  for dep in deps {
    let from_id = node_ids.get(dep.from).unwrap()
    let to_id = node_ids.get(dep.to).unwrap()
    lines.push("  " + from_id + " --> " + to_id)
  }
  lines.push("```")
  join_lines(lines)
}

///|
/// Generate a call graph diagram in Mermaid format.
/// Output: graph TD with function calls as arrows.
pub fn generate_call_diagram(
  calls : Array[@query.CallInfo],
  title? : String = "Call Graph",
  focus? : String? = None,
) -> String {
  if calls.length() == 0 {
    return ""
  }
  // Filter calls if focus is provided
  let filtered = match focus {
    Some(f) => calls.filter(fn(c) { c.caller == f || c.callee == f })
    None => calls
  }
  if filtered.length() == 0 {
    return ""
  }
  let lines : Array[String] = []
  lines.push("```mermaid")
  lines.push("---")
  lines.push("title: " + title)
  lines.push("---")
  lines.push("graph TD")
  // Collect unique nodes
  let node_ids : Map[String, String] = {}
  let mut id_counter = 0
  for call in filtered {
    if not(node_ids.contains(call.caller)) {
      node_ids.set(call.caller, "F" + id_counter.to_string())
      id_counter = id_counter + 1
    }
    if not(node_ids.contains(call.callee)) {
      node_ids.set(call.callee, "F" + id_counter.to_string())
      id_counter = id_counter + 1
    }
  }
  // Generate node definitions
  for entry in node_ids {
    let name = entry.0
    let id = entry.1
    let label = shorten_symbol_name(name)
    lines.push("  " + id + "[" + escape_mermaid(label) + "]")
  }
  // Generate edges
  for call in filtered {
    let caller_id = node_ids.get(call.caller).unwrap()
    let callee_id = node_ids.get(call.callee).unwrap()
    lines.push("  " + caller_id + " --> " + callee_id)
  }
  lines.push("```")
  join_lines(lines)
}

///|
/// Generate a type hierarchy diagram in Mermaid classDiagram format.
pub fn generate_hierarchy_diagram(
  relations : Array[@query.TypeRelation],
  title? : String = "Type Hierarchy",
) -> String {
  if relations.length() == 0 {
    return ""
  }
  let lines : Array[String] = []
  lines.push("```mermaid")
  lines.push("---")
  lines.push("title: " + title)
  lines.push("---")
  lines.push("classDiagram")
  // Collect unique types
  let types : Map[String, Bool] = {}
  for rel in relations {
    types.set(rel.child, true)
    types.set(rel.parent, true)
  }
  // Generate class declarations
  for entry in types {
    let type_name = entry.0
    let label = shorten_symbol_name(type_name)
    lines.push("  class " + sanitize_class_name(label))
  }
  // Generate relationships
  for rel in relations {
    let child = sanitize_class_name(shorten_symbol_name(rel.child))
    let parent = sanitize_class_name(shorten_symbol_name(rel.parent))
    let arrow = if rel.relation == "extends" {
      " <|-- "
    } else {
      " <|.. " // implements (dashed)
    }
    lines.push("  " + parent + arrow + child)
  }
  lines.push("```")
  join_lines(lines)
}

///|
/// Generate a combined overview diagram showing modules and their key symbols.
pub fn generate_overview_diagram(
  deps : Array[@query.ModuleDep],
  decls : Array[@query.SymbolDecl],
  max_symbols_per_module? : Int = 5,
) -> String {
  if deps.length() == 0 && decls.length() == 0 {
    return ""
  }
  let lines : Array[String] = []
  lines.push("```mermaid")
  lines.push("graph TB")
  // Group declarations by module
  let by_module : Map[String, Array[@query.SymbolDecl]] = {}
  for decl in decls {
    match by_module.get(decl.module_id) {
      Some(arr) => arr.push(decl)
      None => by_module.set(decl.module_id, [decl])
    }
  }
  // Generate subgraphs for each module
  let mut module_counter = 0
  let module_ids : Map[String, String] = {}
  for entry in by_module {
    let mod_name = entry.0
    let symbols = entry.1
    let mod_id = "M" + module_counter.to_string()
    module_ids.set(mod_name, mod_id)
    module_counter = module_counter + 1
    let label = shorten_module_name(mod_name)
    lines.push("  subgraph " + mod_id + "[" + escape_mermaid(label) + "]")
    let mut sym_count = 0
    for sym in symbols {
      if sym_count >= max_symbols_per_module {
        lines.push("    " + mod_id + "_more[...]")
        break
      }
      let sym_id = mod_id + "_S" + sym_count.to_string()
      lines.push("    " + sym_id + "[" + escape_mermaid(sym.name) + "]")
      sym_count = sym_count + 1
    }
    lines.push("  end")
  }
  // Generate module dependencies
  for dep in deps {
    match (module_ids.get(dep.from), module_ids.get(dep.to)) {
      (Some(from_id), Some(to_id)) =>
        lines.push("  " + from_id + " --> " + to_id)
      _ => ()
    }
  }
  lines.push("```")
  join_lines(lines)
}

///|
/// Generate a simplified dependency diagram from a FoldedGraph.
/// Important nodes are shown individually; collapsed nodes appear as
/// rounded boxes with member counts.
pub fn generate_folded_diagram(
  folded : @fold.FoldedGraph,
  title? : String = "Dependency Graph (simplified)",
) -> String {
  let nodes = folded.get_nodes()
  let edges = folded.get_edges()
  if nodes.length() == 0 {
    return ""
  }
  let lines : Array[String] = []
  lines.push("```mermaid")
  lines.push("---")
  lines.push("title: " + title)
  lines.push("---")
  lines.push("graph LR")
  // Assign short IDs and generate node definitions
  let id_map : Map[String, String] = {}
  let mut counter = 0
  for entry in nodes {
    let node_id = entry.0
    let node = entry.1
    let short_id = "N" + counter.to_string()
    id_map.set(node_id, short_id)
    counter = counter + 1
    match node {
      @fold.FoldedNode::Single(real_id, _score) => {
        let label = shorten_module_name(real_id)
        lines.push("  " + short_id + "[" + escape_mermaid(label) + "]")
      }
      @fold.FoldedNode::Cluster(label, count, _members) => {
        let display = escape_mermaid(label) +
          " (" +
          count.to_string() +
          " nodes)"
        // Rounded box for clusters
        lines.push("  " + short_id + "(" + display + ")")
      }
    }
  }
  // Generate edges with optional weight labels
  for edge in edges {
    match (id_map.get(edge.from), id_map.get(edge.to)) {
      (Some(from_id), Some(to_id)) => {
        if edge.weight > 1 {
          lines.push(
            "  " +
            from_id +
            " -- " +
            edge.weight.to_string() +
            " --> " +
            to_id,
          )
        } else {
          lines.push("  " + from_id + " --> " + to_id)
        }
      }
      _ => ()
    }
  }
  // Style clusters differently
  let cluster_ids : Array[String] = []
  for entry in nodes {
    match entry.1 {
      @fold.FoldedNode::Cluster(_, _, _) =>
        match id_map.get(entry.0) {
          Some(short_id) => cluster_ids.push(short_id)
          None => ()
        }
      _ => ()
    }
  }
  if cluster_ids.length() > 0 {
    let ids = join_with_comma(cluster_ids)
    lines.push(
      "  style " + ids + " fill:#f0f0f0,stroke:#999,stroke-dasharray: 5 5",
    )
  }
  lines.push("```")
  join_lines(lines)
}

///|
fn join_with_comma(parts : Array[String]) -> String {
  if parts.length() == 0 {
    return ""
  }
  let result : Array[Char] = []
  for i, part in parts {
    if i > 0 {
      result.push(',')
    }
    for c in part {
      result.push(c)
    }
  }
  String::from_array(result)
}

// Helper functions

///|
/// Shorten module name for display.
fn shorten_module_name(name : String) -> String {
  // Take last path segment
  let parts = split_by_char(name, '/')
  if parts.length() > 0 {
    parts[parts.length() - 1]
  } else {
    name
  }
}

///|
/// Shorten symbol name for display.
fn shorten_symbol_name(name : String) -> String {
  // Take last part after ::
  let parts = split_by_str(name, "::")
  if parts.length() > 0 {
    parts[parts.length() - 1]
  } else {
    name
  }
}

///|
/// Escape special characters for Mermaid.
fn escape_mermaid(s : String) -> String {
  let chars = s.to_array()
  let result : Array[Char] = []
  for c in chars {
    match c {
      '"' => {
        result.push('#')
        result.push('q')
        result.push('u')
        result.push('o')
        result.push('t')
        result.push(';')
      }
      '[' | ']' | '(' | ')' | '{' | '}' =>
        // Skip brackets in labels
        ()
      _ => result.push(c)
    }
  }
  String::from_array(result)
}

///|
/// Sanitize class name for Mermaid classDiagram.
fn sanitize_class_name(s : String) -> String {
  let chars = s.to_array()
  let result : Array[Char] = []
  for c in chars {
    if (c >= 'a' && c <= 'z') ||
      (c >= 'A' && c <= 'Z') ||
      (c >= '0' && c <= '9') ||
      c == '_' {
      result.push(c)
    }
  }
  String::from_array(result)
}

///|
/// Split string by character.
fn split_by_char(s : String, sep : Char) -> Array[String] {
  let parts : Array[String] = []
  let current : Array[Char] = []
  for c in s.to_array() {
    if c == sep {
      if current.length() > 0 {
        parts.push(String::from_array(current))
        current.clear()
      }
    } else {
      current.push(c)
    }
  }
  if current.length() > 0 {
    parts.push(String::from_array(current))
  }
  parts
}

///|
/// Split string by substring.
fn split_by_str(s : String, sep : String) -> Array[String] {
  let parts : Array[String] = []
  let s_chars = s.to_array()
  let sep_chars = sep.to_array()
  let sep_len = sep_chars.length()
  if sep_len == 0 {
    return [s]
  }
  let mut start = 0
  let mut i = 0
  while i <= s_chars.length() - sep_len {
    let mut match_ = true
    for j = 0; j < sep_len; j = j + 1 {
      if s_chars[i + j] != sep_chars[j] {
        match_ = false
        break
      }
    }
    if match_ {
      if i > start {
        let part : Array[Char] = []
        for k = start; k < i; k = k + 1 {
          part.push(s_chars[k])
        }
        parts.push(String::from_array(part))
      }
      start = i + sep_len
      i = start
    } else {
      i = i + 1
    }
  }
  if start < s_chars.length() {
    let part : Array[Char] = []
    for k = start; k < s_chars.length(); k = k + 1 {
      part.push(s_chars[k])
    }
    parts.push(String::from_array(part))
  }
  parts
}

///|
/// Join array of strings with newline.
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
