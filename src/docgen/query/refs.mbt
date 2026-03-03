// Symbol reference extraction from CodeGraph.

///|
/// Extract all symbol references from the graph.
pub fn extract_references(graph : @graph.CodeGraph) -> Array[SymbolRef] {
  let result : Array[SymbolRef] = []
  for edge in graph.get_edges() {
    if edge.kind is @graph.References {
      let ref_kind = edge.attrs.get("ns").or("value")
      result.push(SymbolRef::new(edge.to, edge.from, ref_kind))
    }
  }
  result
}

///|
/// Get all places where a symbol is referenced.
pub fn get_references_to(
  graph : @graph.CodeGraph,
  symbol_id : String,
) -> Array[SymbolRef] {
  let result : Array[SymbolRef] = []
  for edge in graph.edges_to(symbol_id) {
    if edge.kind is @graph.References {
      let ref_kind = edge.attrs.get("ns").or("value")
      result.push(SymbolRef::new(edge.to, edge.from, ref_kind))
    }
  }
  result
}

///|
/// Get all symbols referenced from a given location.
pub fn get_references_from(
  graph : @graph.CodeGraph,
  site_id : String,
) -> Array[SymbolRef] {
  let result : Array[SymbolRef] = []
  for edge in graph.edges_from(site_id) {
    if edge.kind is @graph.References {
      let ref_kind = edge.attrs.get("ns").or("value")
      result.push(SymbolRef::new(edge.to, edge.from, ref_kind))
    }
  }
  result
}

///|
/// Extract all symbol declarations from the graph.
/// Looks for Declares edges and extracts doc/name/kind from attrs.
pub fn extract_declarations(graph : @graph.CodeGraph) -> Array[SymbolDecl] {
  let result : Array[SymbolDecl] = []
  for edge in graph.get_edges() {
    if edge.kind is @graph.Declares {
      let name = edge.attrs.get("name").or("")
      let kind = edge.attrs.get("kind").or("Unknown")
      let doc = edge.attrs.get("doc")
      result.push(SymbolDecl::new(edge.to, name, kind, edge.from, doc~))
    }
  }
  result
}

///|
/// Get declarations within a module.
pub fn get_module_declarations(
  graph : @graph.CodeGraph,
  module_id : String,
) -> Array[SymbolDecl] {
  let result : Array[SymbolDecl] = []
  for edge in graph.edges_from(module_id) {
    if edge.kind is @graph.Declares {
      let name = edge.attrs.get("name").or("")
      let kind = edge.attrs.get("kind").or("Unknown")
      let doc = edge.attrs.get("doc")
      result.push(SymbolDecl::new(edge.to, name, kind, edge.from, doc~))
    }
  }
  result
}

///|
/// Get the number of references to each symbol.
/// Returns a map of symbol_id -> reference_count.
pub fn count_references(graph : @graph.CodeGraph) -> Map[String, Int] {
  let counts : Map[String, Int] = {}
  for edge in graph.get_edges() {
    if edge.kind is @graph.References {
      let current = counts.get(edge.to).or(0)
      counts.set(edge.to, current + 1)
    }
  }
  counts
}
