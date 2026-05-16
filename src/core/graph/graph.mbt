// Graph operations for building and manipulating code graphs.

///|
/// Create a new empty code graph.
pub fn CodeGraph::new() -> CodeGraph {
  { modules: Map([]), symbols: Map([]), edges: [], notes: [] }
}

///|
/// Add a note to the graph.
pub fn CodeGraph::add_note(
  self : CodeGraph,
  note_type : String,
  content : String,
  module_id : String,
) -> Unit {
  self.notes.push({ note_type, content, module_id })
}

///|
/// Get notes of a specific type for a module.
pub fn CodeGraph::get_notes(
  self : CodeGraph,
  note_type : String,
  module_id : String,
) -> Array[ModuleNote] {
  let result : Array[ModuleNote] = []
  for note in self.notes {
    if note.note_type == note_type &&
      (module_id.length() == 0 || note.module_id == module_id) {
      result.push(note)
    }
  }
  result
}

///|
/// Get all module_doc notes for a module.
pub fn CodeGraph::get_module_doc(
  self : CodeGraph,
  module_id : String,
) -> String? {
  for note in self.notes {
    if note.note_type == "module_doc" && note.module_id == module_id {
      return Some(note.content)
    }
  }
  None
}

///|
/// Get all notes.
pub fn CodeGraph::get_all_notes(self : CodeGraph) -> Array[ModuleNote] {
  self.notes
}

///|
/// Get an existing module or add a new one.
/// If the module exists and a file path is provided, updates the file if not already set.
pub fn CodeGraph::get_or_add_module(
  self : CodeGraph,
  id : String,
  file? : String? = None,
) -> ModuleNode {
  match self.modules.get(id) {
    Some(existing) =>
      // Update file path if newly provided and not already set
      match (file, existing.file) {
        (Some(f), None) => {
          let updated = { ..existing, file: Some(f) }
          self.modules.set(id, updated)
          updated
        }
        _ => existing
      }
    None => {
      let node : ModuleNode = { id, file }
      self.modules.set(id, node)
      node
    }
  }
}

///|
/// Get an existing symbol or add a new one.
/// Symbol identity is determined by its ID.
pub fn CodeGraph::get_or_add_symbol(
  self : CodeGraph,
  id : String,
  name~ : String,
  kind~ : String,
  ns~ : String,
  module_id~ : String,
  doc? : String? = None,
) -> SymbolNode {
  match self.symbols.get(id) {
    Some(existing) => existing
    None => {
      let node : SymbolNode = { id, name, kind, ns, module_id, doc }
      self.symbols.set(id, node)
      node
    }
  }
}

///|
/// Add an edge between two nodes.
pub fn CodeGraph::add_edge(
  self : CodeGraph,
  kind : EdgeKind,
  from : String,
  to : String,
  attrs? : Map[String, String] = Map([]),
) -> Unit {
  let edge : Edge = { kind, from, to, attrs }
  self.edges.push(edge)
}

///|
/// Rewrite edge endpoints in place according to the provided map. Used by
/// post-merge enrichment to collapse external references (e.g. `pkg:<proj>/foo`)
/// back to their canonical internal module ids once the project layout has
/// been fully observed. The rewrite is applied to both `from` and `to` so that
/// a canonicalized node participates as both source and target consistently.
pub fn CodeGraph::rewrite_edge_targets(
  self : CodeGraph,
  rewrite : Map[String, String],
) -> Unit {
  if rewrite.is_empty() {
    return
  }
  for i = 0; i < self.edges.length(); i = i + 1 {
    let e = self.edges[i]
    let new_from = match rewrite.get(e.from) {
      Some(v) => v
      None => e.from
    }
    let new_to = match rewrite.get(e.to) {
      Some(v) => v
      None => e.to
    }
    if new_from != e.from || new_to != e.to {
      self.edges[i] = {
        kind: e.kind,
        from: new_from,
        to: new_to,
        attrs: e.attrs,
      }
    }
  }
  // Also drop any `moduleDependsOn` edges that become self-loops as a result
  // of canonicalization (a file depending on its own package manifest is not a
  // meaningful fact and clutters the graph).
  let kept : Array[Edge] = []
  for e in self.edges {
    if e.kind is ModuleDependsOn && e.from == e.to {
      continue
    }
    kept.push(e)
  }
  while self.edges.length() > 0 {
    let _ = self.edges.pop()
  }
  for e in kept {
    self.edges.push(e)
  }
}

///|
/// Get all modules in the graph.
pub fn CodeGraph::get_modules(self : CodeGraph) -> Map[String, ModuleNode] {
  self.modules
}

///|
/// Get all symbols in the graph.
pub fn CodeGraph::get_symbols(self : CodeGraph) -> Map[String, SymbolNode] {
  self.symbols
}

///|
/// Get all edges in the graph.
pub fn CodeGraph::get_edges(self : CodeGraph) -> Array[Edge] {
  self.edges
}

///|
/// Get a module by ID if it exists.
pub fn CodeGraph::get_module(self : CodeGraph, id : String) -> ModuleNode? {
  self.modules.get(id)
}

///|
/// Get a symbol by ID if it exists.
pub fn CodeGraph::get_symbol(self : CodeGraph, id : String) -> SymbolNode? {
  self.symbols.get(id)
}

///|
/// Count the number of modules.
pub fn CodeGraph::module_count(self : CodeGraph) -> Int {
  self.modules.length()
}

///|
/// Count the number of symbols.
pub fn CodeGraph::symbol_count(self : CodeGraph) -> Int {
  self.symbols.length()
}

///|
/// Count the number of edges.
pub fn CodeGraph::edge_count(self : CodeGraph) -> Int {
  self.edges.length()
}

///|
/// Find all edges from a given node.
pub fn CodeGraph::edges_from(self : CodeGraph, node_id : String) -> Array[Edge] {
  self.edges.filter(fn(e) { e.from == node_id })
}

///|
/// Find all edges to a given node.
pub fn CodeGraph::edges_to(self : CodeGraph, node_id : String) -> Array[Edge] {
  self.edges.filter(fn(e) { e.to == node_id })
}

///|
/// Get callees of a symbol (symbols that this symbol calls).
pub fn CodeGraph::get_callees(
  self : CodeGraph,
  symbol_id : String,
) -> Array[String] {
  let result : Array[String] = []
  for edge in self.edges_from(symbol_id) {
    if edge.kind is Calls {
      result.push(edge.to)
    }
  }
  result
}

///|
/// Get callers of a symbol (symbols that call this symbol).
pub fn CodeGraph::get_callers(
  self : CodeGraph,
  symbol_id : String,
) -> Array[String] {
  let result : Array[String] = []
  for edge in self.edges_to(symbol_id) {
    if edge.kind is Calls {
      result.push(edge.from)
    }
  }
  result
}

///|
/// Convert EdgeKind to its string representation.
pub fn EdgeKind::to_string(self : EdgeKind) -> String {
  match self {
    Declares => "declares"
    References => "references"
    ModuleDependsOn => "module_depends_on"
    Imports => "imports"
    Calls => "calls"
    Extends => "extends"
    Implements => "implements"
    CircularDependency => "circular_dependency"
    Custom(s) => s
  }
}

///|
/// Parse a string into an EdgeKind.
/// Accepts both camelCase (e.g., "moduleDependsOn") and snake_case (e.g., "module_depends_on").
pub fn EdgeKind::from_string(s : String) -> EdgeKind {
  match s {
    "declares" | "Declares" => Declares
    "references" | "References" => References
    "module_depends_on" | "moduleDependsOn" | "ModuleDependsOn" =>
      ModuleDependsOn
    "imports" | "Imports" => Imports
    "calls" | "Calls" => Calls
    "extends" | "Extends" => Extends
    "implements" | "Implements" => Implements
    "circular_dependency" | "circularDependency" | "CircularDependency" =>
      CircularDependency
    _ => Custom(s)
  }
}

///|
/// Resolve an edge endpoint against known symbols and modules by matching on
/// the endpoint's trailing id segment. This covers the cross-spec mismatch
/// where semantics scripts emit `<file>::<name>` while `attrs def` registers
/// `<file>::<ns>:<name>`, or where nested `<parent>.<name>` references need
/// to be rewritten to the canonical symbol id.
fn rewrite_by_trailing_name(
  id : String,
  modules : Map[String, ModuleNode],
  symbols : Map[String, SymbolNode],
  symbol_by_module_name : Map[String, String],
) -> String? {
  if symbols.contains(id) || modules.contains(id) {
    return None
  }
  // Try to split at "::" to extract (module_id, trailing_name). When the
  // trailing_name itself contains "." (member syntax), fall back to the last
  // segment so `ClassName.method` still matches a symbol named `method` in
  // the enclosing file. The module_id side does not need to be exact — the
  // `(module_id, name)` lookup is keyed on the file the symbol was declared
  // in.
  let sep_idx = find_last_substring(id, "::")
  if sep_idx < 0 {
    return None
  }
  let module_part = substring_upto(id, sep_idx)
  let tail = substring_from(id, sep_idx + 2)
  // The trailing name might be bare ("foo"), ns-prefixed ("value:foo"), or
  // dotted ("ClassName.method"). Strip a leading `<ns>:` prefix if present,
  // then take the last dot-separated segment.
  let after_ns = match find_char(tail, ':') {
    -1 => tail
    i => substring_from(tail, i + 1)
  }
  let bare = last_dot_segment(after_ns)
  let key = module_part + "\u{1f}" + bare
  match symbol_by_module_name.get(key) {
    Some(sym_id) => Some(sym_id)
    None => None
  }
}

///|
fn find_last_substring(s : String, needle : String) -> Int {
  let ca = s.to_array()
  let na = needle.to_array()
  if na.length() == 0 || na.length() > ca.length() {
    return -1
  }
  let mut last = -1
  for i = 0; i <= ca.length() - na.length(); i = i + 1 {
    let mut ok = true
    for j = 0; j < na.length(); j = j + 1 {
      if ca[i + j] != na[j] {
        ok = false
        break
      }
    }
    if ok {
      last = i
    }
  }
  last
}

///|
fn substring_upto(s : String, end : Int) -> String {
  let ca = s.to_array()
  let sb = StringBuilder::new()
  for i = 0; i < end && i < ca.length(); i = i + 1 {
    sb.write_char(ca[i])
  }
  sb.to_string()
}

///|
fn substring_from(s : String, start : Int) -> String {
  let ca = s.to_array()
  if start >= ca.length() {
    return ""
  }
  let sb = StringBuilder::new()
  for i = start; i < ca.length(); i = i + 1 {
    sb.write_char(ca[i])
  }
  sb.to_string()
}

///|
fn find_char(s : String, c : Char) -> Int {
  let ca = s.to_array()
  for i = 0; i < ca.length(); i = i + 1 {
    if ca[i] == c {
      return i
    }
  }
  -1
}

///|
fn last_dot_segment(s : String) -> String {
  let ca = s.to_array()
  let mut last = -1
  for i = 0; i < ca.length(); i = i + 1 {
    if ca[i] == '.' {
      last = i
    }
  }
  if last < 0 {
    return s
  }
  substring_from(s, last + 1)
}

///|
/// Resolve an edge target against known symbols and modules.
/// If the target already exists, returns it unchanged. If a `declares` edge
/// references a target that matches an existing symbol by `(module_id, name)`,
/// rewrites it to the canonical symbol ID. Returns the pair
/// `(resolved_id, was_rewritten)`; `was_rewritten` is true only when the ID
/// changed.
fn resolve_edge_target(
  to : String,
  edge : Edge,
  modules : Map[String, ModuleNode],
  symbols : Map[String, SymbolNode],
  symbol_by_module_name : Map[String, String],
) -> (String, Bool) {
  if symbols.contains(to) || modules.contains(to) {
    return (to, false)
  }
  // Try to resolve declares edges against the canonical symbol by (from, name).
  if edge.kind is Declares {
    match edge.attrs.get("name") {
      Some(name) => {
        let key = edge.from + "\u{1f}" + name
        match symbol_by_module_name.get(key) {
          Some(sym_id) => return (sym_id, true)
          None => ()
        }
      }
      None => ()
    }
  }
  (to, false)
}

///|
/// Convert CodeGraph to JSON string following KGF format.
/// Format:
/// {
///   "modules": { "id": { "file": "..." } },
///   "symbols": { "id": { "name": "...", "kind": "...", "ns": "...", "module": "..." } },
///   "edges": [{ "kind": "...", "from": "...", "to": "...", ...attrs }]
/// }
///
/// Before writing, edge endpoints are reconciled against the node tables:
/// - `declares` edges whose `to` does not match a symbol ID are remapped to the
///   canonical symbol by `(from, name)` lookup (KGF scripts often emit
///   `<file>::<name>` while `attrs def` registers `<file>::<ns>:<name>`).
/// - Any `to` that still has no matching node is registered as an external
///   module with `file: null` so consumers see every endpoint in `modules` or
///   `symbols`.
pub fn CodeGraph::to_json_string(self : CodeGraph) -> String {
  // Build (module_id, name) → symbol_id lookup for declares-edge normalization.
  let symbol_by_module_name : Map[String, String] = {}
  for entry in self.symbols {
    let s = entry.1
    let key = s.module_id + "\u{1f}" + s.name
    // First write wins; later duplicates keep the earliest registration.
    if !symbol_by_module_name.contains(key) {
      symbol_by_module_name.set(key, s.id)
    }
  }

  // Working copy of modules; receives backfilled external targets.
  let modules_out : Map[String, ModuleNode] = {}
  for entry in self.modules {
    modules_out.set(entry.0, entry.1)
  }

  // Build edges array with normalized endpoints.
  let edges_arr : Array[Json] = []
  let mut backfilled_count = 0
  let backfilled_samples : Array[String] = []
  for edge in self.edges {
    let (resolved_to, _) = resolve_edge_target(
      edge.to,
      edge,
      self.modules,
      self.symbols,
      symbol_by_module_name,
    )
    // Also resolve the edge's `from`: nested declarations (class methods
    // etc.) are emitted by semantics scripts with from = the parent
    // symbol's scope-looked-up id, which can differ from the canonical
    // symbol id registered by `attrs def`. Applying the same trailing-name
    // rewrite keeps both endpoints pointing at real nodes.
    let resolved_from = match
      rewrite_by_trailing_name(
        edge.from,
        self.modules,
        self.symbols,
        symbol_by_module_name,
      ) {
      Some(v) => v
      None => edge.from
    }
    // Backfill missing endpoints only for edges whose kind intrinsically
    // encodes a graph-structural relationship. `Custom` kinds come from KGF
    // spec authors who use them for metadata (project name, keyword,
    // repository URL, package entry path, …). Auto-creating modules for
    // those turns strings like "Apache-2.0" or "parsing" into fake nodes,
    // which breaks downstream consumers. Built-in kinds — Declares,
    // ModuleDependsOn, Calls, and the rest — always point at real
    // modules or symbols, so backfilling them preserves the invariant that
    // every `declares` / `moduleDependsOn` / `calls` endpoint resolves.
    let is_structural = !(edge.kind is Custom(_))
    if is_structural &&
      !self.symbols.contains(resolved_to) &&
      !modules_out.contains(resolved_to) {
      modules_out.set(resolved_to, { id: resolved_to, file: None })
      backfilled_count = backfilled_count + 1
      if backfilled_samples.length() < 5 {
        backfilled_samples.push(resolved_to)
      }
    }
    if is_structural &&
      !self.symbols.contains(resolved_from) &&
      !modules_out.contains(resolved_from) {
      modules_out.set(resolved_from, { id: resolved_from, file: None })
      backfilled_count = backfilled_count + 1
      if backfilled_samples.length() < 5 {
        backfilled_samples.push(resolved_from)
      }
    }
    let edge_obj : Map[String, Json] = {}
    // Attrs first, then canonical fields — canonical fields must win so
    // attrs like `"kind": "Function"` on a `declares` edge do not clobber
    // the edge's actual kind.
    for attr_entry in edge.attrs {
      edge_obj.set(attr_entry.0, attr_entry.1.to_json())
    }
    edge_obj.set("kind", edge.kind.to_string().to_json())
    edge_obj.set("from", resolved_from.to_json())
    edge_obj.set("to", resolved_to.to_json())
    edges_arr.push(Json::object(edge_obj))
  }

  // Build modules object from working copy.
  let modules_obj : Map[String, Json] = {}
  for entry in modules_out {
    let id = entry.0
    let m = entry.1
    let file_json : Json = match m.file {
      Some(f) => f.to_json()
      None => Json::null()
    }
    modules_obj.set(id, { "file": file_json })
  }

  // Build symbols object.
  let symbols_obj : Map[String, Json] = {}
  for entry in self.symbols {
    let id = entry.0
    let s = entry.1
    let sym_map : Map[String, Json] = {}
    sym_map.set("name", s.name.to_json())
    sym_map.set("kind", s.kind.to_json())
    sym_map.set("ns", s.ns.to_json())
    sym_map.set("module", s.module_id.to_json())
    match s.doc {
      Some(d) => sym_map.set("doc", d.to_json())
      None => ()
    }
    symbols_obj.set(id, Json::object(sym_map))
  }

  if backfilled_count > 0 {
    let mut sample_str = ""
    for i, s in backfilled_samples {
      if i > 0 {
        sample_str = sample_str + ", "
      }
      sample_str = sample_str + s
    }
    println(
      "[codegraph] warning: " +
      backfilled_count.to_string() +
      " edge target(s) not registered as modules or symbols; auto-registered as external modules. samples: " +
      sample_str,
    )
  }

  let result : Json = {
    "modules": Json::object(modules_obj),
    "symbols": Json::object(symbols_obj),
    "edges": Json::array(edges_arr),
  }
  result.stringify()
}

///|
/// Parse JSON string to CodeGraph following KGF format.
pub fn CodeGraph::from_json_string(json_str : String) -> CodeGraph? {
  let json : Json = @json.parse(json_str) catch { _ => return None }
  // Extract top-level objects using map pattern
  guard json
    is {
      "modules": modules_json,
      "symbols": symbols_json,
      "edges": edges_json,
      ..
    } else {
    return None
  }
  // Get the inner maps/arrays
  let modules_map : Map[String, Json] = @json.from_json(modules_json) catch {
    _ => return None
  }
  let symbols_map : Map[String, Json] = @json.from_json(symbols_json) catch {
    _ => return None
  }
  let edges_arr : Array[Json] = @json.from_json(edges_json) catch {
    _ => return None
  }

  let graph = CodeGraph::new()

  // Parse modules
  for entry in modules_map {
    let id = entry.0
    let m_json = entry.1
    let file : String? = if m_json is { "file": String(f), .. } {
      Some(f)
    } else {
      None
    }
    let _ = graph.get_or_add_module(id, file~)
  }

  // Parse symbols
  for entry in symbols_map {
    let id = entry.0
    let s_json = entry.1
    if s_json
      is {
        "name": String(name),
        "kind": String(kind),
        "ns": String(ns),
        "module": String(module_id),
        ..
      } {
      let doc : String? = if s_json is { "doc": String(d), .. } {
        Some(d)
      } else {
        None
      }
      let _ = graph.get_or_add_symbol(id, name~, kind~, ns~, module_id~, doc~)
    }
  }

  // Parse edges
  for e_json in edges_arr {
    if e_json
      is {
        "kind": String(kind_str),
        "from": String(from),
        "to": String(to),
        ..
      } {
      let kind = EdgeKind::from_string(kind_str)
      // Extract additional attrs (excluding kind, from, to)
      let attrs : Map[String, String] = {}
      let obj : Map[String, Json] = @json.from_json(e_json) catch { _ => {} }
      for attr_entry in obj {
        let k = attr_entry.0
        let v = attr_entry.1
        if k != "kind" && k != "from" && k != "to" {
          if v is String(s) {
            attrs.set(k, s)
          }
        }
      }
      graph.add_edge(kind, from, to, attrs~)
    }
  }

  Some(graph)
}
