// Graph operations for building and manipulating code graphs.

///|
/// Create a new empty code graph.
pub fn CodeGraph::new() -> CodeGraph {
  { modules: Map::new(), symbols: Map::new(), edges: [] }
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
  attrs? : Map[String, String] = Map::new(),
) -> Unit {
  let edge : Edge = { kind, from, to, attrs }
  self.edges.push(edge)
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
/// Convert CodeGraph to JSON string following KGF format.
/// Format:
/// {
///   "modules": { "id": { "file": "..." } },
///   "symbols": { "id": { "name": "...", "kind": "...", "ns": "...", "module": "..." } },
///   "edges": [{ "kind": "...", "from": "...", "to": "...", ...attrs }]
/// }
pub fn CodeGraph::to_json_string(self : CodeGraph) -> String {
  // Build modules object
  let modules_obj : Map[String, Json] = {}
  for entry in self.modules {
    let id = entry.0
    let m = entry.1
    let file_json : Json = match m.file {
      Some(f) => f.to_json()
      None => Json::null()
    }
    modules_obj.set(id, { "file": file_json })
  }

  // Build symbols object
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

  // Build edges array
  let edges_arr : Array[Json] = []
  for edge in self.edges {
    let edge_obj : Map[String, Json] = {}
    edge_obj.set("kind", edge.kind.to_string().to_json())
    edge_obj.set("from", edge.from.to_json())
    edge_obj.set("to", edge.to.to_json())
    // Add attrs directly to edge object
    for attr_entry in edge.attrs {
      edge_obj.set(attr_entry.0, attr_entry.1.to_json())
    }
    edges_arr.push(Json::object(edge_obj))
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
