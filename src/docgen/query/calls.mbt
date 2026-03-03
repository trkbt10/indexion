// Call graph extraction from CodeGraph.

///|
/// Extract all call relationships from the graph.
pub fn extract_call_graph(graph : @graph.CodeGraph) -> Array[CallInfo] {
  let result : Array[CallInfo] = []
  for edge in graph.get_edges() {
    if edge.kind is @graph.Calls {
      let file = edge.attrs.get("file").or("")
      result.push(CallInfo::new(edge.from, edge.to, file))
    }
  }
  result
}

///|
/// Get functions called by a given symbol.
pub fn get_callees(
  graph : @graph.CodeGraph,
  caller_id : String,
) -> Array[CallInfo] {
  let result : Array[CallInfo] = []
  for edge in graph.edges_from(caller_id) {
    if edge.kind is @graph.Calls {
      let file = edge.attrs.get("file").or("")
      result.push(CallInfo::new(edge.from, edge.to, file))
    }
  }
  result
}

///|
/// Get callers of a given function.
pub fn get_callers(
  graph : @graph.CodeGraph,
  callee_id : String,
) -> Array[CallInfo] {
  let result : Array[CallInfo] = []
  for edge in graph.edges_to(callee_id) {
    if edge.kind is @graph.Calls {
      let file = edge.attrs.get("file").or("")
      result.push(CallInfo::new(edge.from, edge.to, file))
    }
  }
  result
}

///|
/// Get call chain starting from a function (transitive callees).
pub fn get_call_chain(
  graph : @graph.CodeGraph,
  start_id : String,
  max_depth? : Int = 10,
) -> Array[CallInfo] {
  let visited : Map[String, Bool] = {}
  let result : Array[CallInfo] = []
  let queue : Array[(String, Int)] = [(start_id, 0)]
  while queue.length() > 0 {
    let (current, depth) = queue.pop().unwrap()
    if depth >= max_depth || visited.contains(current) {
      continue
    }
    visited.set(current, true)
    for call in get_callees(graph, current) {
      result.push(call)
      if not(visited.contains(call.callee)) {
        queue.push((call.callee, depth + 1))
      }
    }
  }
  result
}
