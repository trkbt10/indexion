// Mermaid diagram generation from query results.

///|
/// Generate a module dependency diagram in Mermaid format.
/// Output: graph LR with module dependencies as arrows.
pub fn generate_dep_diagram(
  deps : Array[@query.ModuleDep],
  title? : String = "Module Dependencies",
) -> String {
  generate_dep_diagram_with_circular(deps, [], title~)
}

///|
/// Generate a module dependency diagram with external dependency detection.
/// external_prefixes: bare_prefix values from KGF specs (e.g., ["pkg:", "npm:"])
/// internal_prefixes: paths that are internal even with bare_prefix (e.g., ["trkbt10/indexion"])
pub fn generate_dep_diagram_with_externals(
  deps : Array[@query.ModuleDep],
  circulars : Array[@query.CircularDep],
  external_prefixes : Array[String],
  internal_prefixes? : Array[String] = [],
  title? : String = "Module Dependencies",
) -> String {
  generate_dep_diagram_impl(
    deps, circulars, external_prefixes, internal_prefixes, title,
  )
}

///|
/// Generate a module dependency diagram with circular dependency highlighting.
/// Circular dependencies are shown with red dashed edges.
/// Uses empty external/internal prefixes (for backwards compatibility).
pub fn generate_dep_diagram_with_circular(
  deps : Array[@query.ModuleDep],
  circulars : Array[@query.CircularDep],
  title? : String = "Module Dependencies",
) -> String {
  generate_dep_diagram_impl(deps, circulars, [], [], title)
}

///|
/// Internal implementation for diagram generation.
fn generate_dep_diagram_impl(
  deps : Array[@query.ModuleDep],
  circulars : Array[@query.CircularDep],
  external_prefixes : Array[String],
  internal_prefixes : Array[String],
  title : String,
) -> String {
  if deps.length() == 0 && circulars.length() == 0 {
    return ""
  }
  let lines : Array[String] = []
  lines.push("```mermaid")
  lines.push("---")
  lines.push("title: " + title)
  lines.push("---")
  lines.push("graph LR")
  // Normalize paths and collect unique nodes
  // Use shortened name as key to deduplicate same logical modules
  // External dependencies are collapsed to package name
  let label_to_id : Map[String, String] = {}
  let original_to_label : Map[String, String] = {}
  let external_nodes : Map[String, Bool] = {}
  let mut id_counter = 0
  for dep in deps {
    let from_label = normalize_module_label(
      dep.from,
      external_nodes,
      external_prefixes,
      internal_prefixes,
    )
    let to_label = normalize_module_label(
      dep.to,
      external_nodes,
      external_prefixes,
      internal_prefixes,
    )
    original_to_label.set(dep.from, from_label)
    original_to_label.set(dep.to, to_label)
    if not(label_to_id.contains(from_label)) {
      label_to_id.set(from_label, "N" + id_counter.to_string())
      id_counter = id_counter + 1
    }
    if not(label_to_id.contains(to_label)) {
      label_to_id.set(to_label, "N" + id_counter.to_string())
      id_counter = id_counter + 1
    }
  }
  for circ in circulars {
    let from_label = normalize_module_label(
      circ.from,
      external_nodes,
      external_prefixes,
      internal_prefixes,
    )
    let to_label = normalize_module_label(
      circ.to,
      external_nodes,
      external_prefixes,
      internal_prefixes,
    )
    original_to_label.set(circ.from, from_label)
    original_to_label.set(circ.to, to_label)
    if not(label_to_id.contains(from_label)) {
      label_to_id.set(from_label, "N" + id_counter.to_string())
      id_counter = id_counter + 1
    }
    if not(label_to_id.contains(to_label)) {
      label_to_id.set(to_label, "N" + id_counter.to_string())
      id_counter = id_counter + 1
    }
  }
  // Generate node definitions (external nodes get different shape)
  for entry in label_to_id {
    let label = entry.0
    let id = entry.1
    let escaped = escape_mermaid(label)
    if external_nodes.contains(label) {
      // External dependency: use stadium shape ([label])
      lines.push("  " + id + "([" + escaped + "])")
    } else {
      lines.push("  " + id + "[" + escaped + "]")
    }
  }
  // Generate normal dependency edges (deduplicate by label)
  let seen_edges : Map[String, Bool] = {}
  for dep in deps {
    let from_label = original_to_label.get(dep.from).unwrap()
    let to_label = original_to_label.get(dep.to).unwrap()
    let edge_key = from_label + "->" + to_label
    if not(seen_edges.contains(edge_key)) && from_label != to_label {
      seen_edges.set(edge_key, true)
      let from_id = label_to_id.get(from_label).unwrap()
      let to_id = label_to_id.get(to_label).unwrap()
      lines.push("  " + from_id + " --> " + to_id)
    }
  }
  // Generate circular dependency edges with red dashed style
  let mut circ_count = 0
  if circulars.length() > 0 {
    for circ in circulars {
      let from_label = original_to_label.get(circ.from).unwrap()
      let to_label = original_to_label.get(circ.to).unwrap()
      let edge_key = from_label + "->circular->" + to_label
      if not(seen_edges.contains(edge_key)) && from_label != to_label {
        seen_edges.set(edge_key, true)
        let from_id = label_to_id.get(from_label).unwrap()
        let to_id = label_to_id.get(to_label).unwrap()
        lines.push("  " + from_id + " -.->|circular| " + to_id)
        circ_count = circ_count + 1
      }
    }
    // Add style for circular edges
    if circ_count > 0 {
      lines.push("  linkStyle default stroke:#333")
      let start_idx = seen_edges.length() - circ_count
      for i = 0; i < circ_count; i = i + 1 {
        lines.push(
          "  linkStyle " +
          (start_idx + i).to_string() +
          " stroke:red,stroke-width:2px,stroke-dasharray:5",
        )
      }
    }
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

// Helper functions

///|
/// Normalize module label, collapsing external dependencies.
/// Uses external_prefixes and internal_prefixes from KGF specs.
/// External deps like pkg:moonbitlang/core/json → "moonbitlang/core"
/// Internal deps (matching internal_prefixes) keep their structure.
fn normalize_module_label(
  name : String,
  external_nodes : Map[String, Bool],
  external_prefixes : Array[String],
  internal_prefixes : Array[String],
) -> String {
  // Check if path starts with any external prefix (from KGF specs)
  for prefix in external_prefixes {
    if name.has_prefix(prefix) {
      // Strip the bare_prefix to check internal_prefixes
      let stripped = strip_prefix(name, prefix)
      // Check if stripped path starts with any internal prefix
      let mut is_internal = false
      for internal in internal_prefixes {
        if stripped.has_prefix(internal) {
          is_internal = true
          break
        }
      }
      if is_internal {
        // Internal module - shorten normally
        return shorten_module_name(stripped)
      }
      // External dependency - extract package name
      let package_name = extract_package_name(stripped)
      external_nodes.set(package_name, true)
      return package_name
    }
  }
  // No external prefix - just shorten
  shorten_module_name(name)
}

///|
/// Strip prefix from string.
fn strip_prefix(s : String, prefix : String) -> String {
  if s.has_prefix(prefix) {
    let chars = s.to_array()
    let prefix_len = prefix.length()
    let result : Array[Char] = []
    for i = prefix_len; i < chars.length(); i = i + 1 {
      result.push(chars[i])
    }
    String::from_array(result)
  } else {
    s
  }
}

///|
/// Extract package name from path (first two segments: org/package).
/// "moonbitlang/core/json" → "moonbitlang/core"
fn extract_package_name(path : String) -> String {
  let parts = split_by_char(path, '/')
  if parts.length() >= 2 {
    parts[0] + "/" + parts[1]
  } else if parts.length() == 1 {
    parts[0]
  } else {
    path
  }
}

///|
/// Shorten module name for display.
/// Handles both file paths (src/kgf/types/moon.pkg) and module paths (kgf/types).
fn shorten_module_name(name : String) -> String {
  let parts = split_by_char(name, '/')
  if parts.length() == 0 {
    return name
  }
  let last = parts[parts.length() - 1]
  // For moon.pkg files, show the parent directory path
  if last == "moon.pkg" || last == "package.json" {
    let start = find_meaningful_start(parts)
    if start < parts.length() - 1 {
      return join_path_segments(parts, start, parts.length() - 1)
    }
    if parts.length() > 1 {
      return parts[parts.length() - 2]
    }
    return last
  }
  // For module paths (e.g., pkg:trkbt10/indexion/src/kgf/types)
  // Strip pkg: prefix and common prefixes, keep the meaningful part
  let cleaned = if name.has_prefix("pkg:") {
    let chars = name.to_array()
    let result : Array[Char] = []
    for i = 4; i < chars.length(); i = i + 1 {
      result.push(chars[i])
    }
    String::from_array(result)
  } else {
    name
  }
  // Re-split after stripping prefix
  let clean_parts = split_by_char(cleaned, '/')
  if clean_parts.length() == 0 {
    return cleaned
  }
  // Skip organization/project prefixes and src/
  let start = find_meaningful_start_for_module(clean_parts)
  if start < clean_parts.length() {
    return join_path_segments(clean_parts, start, clean_parts.length())
  }
  clean_parts[clean_parts.length() - 1]
}

///|
/// Find where meaningful path starts (skip src/, cmd/, etc.)
fn find_meaningful_start(parts : Array[String]) -> Int {
  let mut start = 0
  if parts.length() > 0 && parts[0] == "src" {
    start = 1
  } else if parts.length() > 0 && parts[0] == "cmd" {
    start = 0 // Keep cmd prefix
  }
  start
}

///|
/// Find meaningful start for module paths.
/// Uses heuristics to skip common prefixes without hardcoding specific names.
fn find_meaningful_start_for_module(parts : Array[String]) -> Int {
  let mut start = 0
  // Skip segments that look like organization names
  // Heuristic: if first segment is not a known directory type, skip it
  if parts.length() > 2 {
    let first = parts[0]
    if first != "src" && first != "cmd" && first != "lib" && first != "pkg" {
      start = start + 1
      // Check if second segment might be project name
      if parts.length() > start + 1 {
        let second = parts[start]
        if second != "src" && second != "cmd" && second != "lib" {
          start = start + 1
        }
      }
    }
  }
  // Skip src/ if present
  if parts.length() > start && parts[start] == "src" {
    start = start + 1
  }
  start
}

///|
/// Join path segments with /
fn join_path_segments(parts : Array[String], start : Int, end : Int) -> String {
  let result : Array[Char] = []
  for i = start; i < end; i = i + 1 {
    if i > start {
      result.push('/')
    }
    for c in parts[i] {
      result.push(c)
    }
  }
  String::from_array(result)
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
