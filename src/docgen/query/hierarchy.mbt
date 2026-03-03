// Type hierarchy extraction from CodeGraph.

///|
/// Extract all type hierarchy relationships.
/// Looks for Extends and Implements edges.
pub fn extract_type_hierarchy(graph : @graph.CodeGraph) -> Array[TypeRelation] {
  let result : Array[TypeRelation] = []
  for edge in graph.get_edges() {
    match edge.kind {
      @graph.Extends =>
        result.push(TypeRelation::new(edge.from, edge.to, "extends"))
      @graph.Implements =>
        result.push(TypeRelation::new(edge.from, edge.to, "implements"))
      _ => ()
    }
  }
  result
}

///|
/// Get parents (extended/implemented types) of a type.
pub fn get_parents(
  graph : @graph.CodeGraph,
  type_id : String,
) -> Array[TypeRelation] {
  let result : Array[TypeRelation] = []
  for edge in graph.edges_from(type_id) {
    match edge.kind {
      @graph.Extends =>
        result.push(TypeRelation::new(edge.from, edge.to, "extends"))
      @graph.Implements =>
        result.push(TypeRelation::new(edge.from, edge.to, "implements"))
      _ => ()
    }
  }
  result
}

///|
/// Get children (implementing/extending types) of a type.
pub fn get_children(
  graph : @graph.CodeGraph,
  type_id : String,
) -> Array[TypeRelation] {
  let result : Array[TypeRelation] = []
  for edge in graph.edges_to(type_id) {
    match edge.kind {
      @graph.Extends =>
        result.push(TypeRelation::new(edge.from, edge.to, "extends"))
      @graph.Implements =>
        result.push(TypeRelation::new(edge.from, edge.to, "implements"))
      _ => ()
    }
  }
  result
}

///|
/// Get all ancestors (transitive parents) of a type.
pub fn get_ancestors(
  graph : @graph.CodeGraph,
  type_id : String,
) -> Array[TypeRelation] {
  let visited : Map[String, Bool] = {}
  let result : Array[TypeRelation] = []
  let queue : Array[String] = [type_id]
  while queue.length() > 0 {
    let current = queue.pop().unwrap()
    if visited.contains(current) {
      continue
    }
    visited.set(current, true)
    for rel in get_parents(graph, current) {
      result.push(rel)
      if not(visited.contains(rel.parent)) {
        queue.push(rel.parent)
      }
    }
  }
  result
}

///|
/// Get all descendants (transitive children) of a type.
pub fn get_descendants(
  graph : @graph.CodeGraph,
  type_id : String,
) -> Array[TypeRelation] {
  let visited : Map[String, Bool] = {}
  let result : Array[TypeRelation] = []
  let queue : Array[String] = [type_id]
  while queue.length() > 0 {
    let current = queue.pop().unwrap()
    if visited.contains(current) {
      continue
    }
    visited.set(current, true)
    for rel in get_children(graph, current) {
      result.push(rel)
      if not(visited.contains(rel.child)) {
        queue.push(rel.child)
      }
    }
  }
  result
}
