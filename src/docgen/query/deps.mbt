// Module dependency extraction from CodeGraph.

///|
/// Extract all module dependencies from the graph.
/// Looks for ModuleDependsOn edges and extracts via/dep_kind from attrs.
pub fn extract_module_deps(graph : @graph.CodeGraph) -> Array[ModuleDep] {
  let result : Array[ModuleDep] = []
  for edge in graph.get_edges() {
    if edge.kind is @graph.ModuleDependsOn {
      let via = edge.attrs.get("via")
      let dep_kind = edge.attrs.get("dep_kind")
      result.push(ModuleDep::new(edge.from, edge.to, via~, dep_kind~))
    }
  }
  result
}

///|
/// Get direct dependencies of a module.
pub fn get_direct_deps(
  graph : @graph.CodeGraph,
  module_id : String,
) -> Array[ModuleDep] {
  let result : Array[ModuleDep] = []
  for edge in graph.edges_from(module_id) {
    if edge.kind is @graph.ModuleDependsOn {
      let via = edge.attrs.get("via")
      let dep_kind = edge.attrs.get("dep_kind")
      result.push(ModuleDep::new(edge.from, edge.to, via~, dep_kind~))
    }
  }
  result
}

///|
/// Get all modules that depend on the given module (reverse deps).
pub fn get_dependents(
  graph : @graph.CodeGraph,
  module_id : String,
) -> Array[ModuleDep] {
  let result : Array[ModuleDep] = []
  for edge in graph.edges_to(module_id) {
    if edge.kind is @graph.ModuleDependsOn {
      let via = edge.attrs.get("via")
      let dep_kind = edge.attrs.get("dep_kind")
      result.push(ModuleDep::new(edge.from, edge.to, via~, dep_kind~))
    }
  }
  result
}

///|
/// Build transitive closure of dependencies starting from a module.
/// Returns all modules that the given module depends on, directly or indirectly.
pub fn get_transitive_deps(
  graph : @graph.CodeGraph,
  module_id : String,
) -> Array[String] {
  let visited : Map[String, Bool] = {}
  let result : Array[String] = []
  let queue : Array[String] = [module_id]
  while queue.length() > 0 {
    let current = queue.pop().unwrap()
    if visited.contains(current) {
      continue
    }
    visited.set(current, true)
    if current != module_id {
      result.push(current)
    }
    for dep in get_direct_deps(graph, current) {
      if not(visited.contains(dep.to)) {
        queue.push(dep.to)
      }
    }
  }
  result
}
