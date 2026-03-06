// Bottom-up traversal of call graph for reminiscent backtracking.
// Processes leaf functions first, then propagates upward through callers.

///|
/// Result of computing traversal order.
pub struct TraversalResult {
  /// Symbol IDs in traversal order.
  order : Array[String]
  /// Symbol ID -> depth mapping (0 = leaf for bottom-up).
  depths : Map[String, Int]
  /// Detected cycles as (from, to) pairs.
  cycles : Array[(String, String)]
} derive(Eq, Show)

///|
/// Create an empty TraversalResult.
pub fn TraversalResult::new() -> TraversalResult {
  { order: [], depths: {}, cycles: [] }
}

///|
/// Get functions at a specific depth.
pub fn TraversalResult::at_depth(
  self : TraversalResult,
  depth : Int,
) -> Array[String] {
  let result : Array[String] = []
  for entry in self.depths {
    if entry.1 == depth {
      result.push(entry.0)
    }
  }
  result
}

///|
/// Get the maximum depth.
pub fn TraversalResult::max_depth(self : TraversalResult) -> Int {
  let mut max = 0
  for entry in self.depths {
    if entry.1 > max {
      max = entry.1
    }
  }
  max
}

///|
/// Get callees of a symbol.
fn get_callees(graph : @graph.CodeGraph, symbol_id : String) -> Array[String] {
  let result : Array[String] = []
  for edge in graph.edges_from(symbol_id) {
    if edge.kind is @graph.Calls {
      result.push(edge.to)
    }
  }
  result
}

///|
/// Get callers of a symbol.
fn get_callers(graph : @graph.CodeGraph, symbol_id : String) -> Array[String] {
  let result : Array[String] = []
  for edge in graph.edges_to(symbol_id) {
    if edge.kind is @graph.Calls {
      result.push(edge.from)
    }
  }
  result
}

///|
/// Compute bottom-up traversal order.
/// Returns functions ordered from leaves (depth 0) to roots (max depth).
pub fn compute_bottom_up_order(
  graph : @graph.CodeGraph,
  function_ids : Array[String],
) -> TraversalResult {
  let result = TraversalResult::new()
  let id_set : Map[String, Bool] = {}
  for id in function_ids {
    id_set.set(id, true)
  }
  // Compute depths using DFS with cycle detection
  let visiting : Map[String, Bool] = {}
  for id in function_ids {
    let _ = compute_depth_recursive(
      graph,
      id,
      id_set,
      result.depths,
      visiting,
      result.cycles,
    )
  }
  // Sort by depth (ascending) for bottom-up order
  let depth_pairs : Array[(String, Int)] = []
  for entry in result.depths {
    depth_pairs.push((entry.0, entry.1))
  }
  depth_pairs.sort_by(fn(a, b) { a.1.compare(b.1) })
  for pair in depth_pairs {
    result.order.push(pair.0)
  }
  result
}

///|
/// Recursive depth computation with cycle detection.
fn compute_depth_recursive(
  graph : @graph.CodeGraph,
  symbol_id : String,
  valid_ids : Map[String, Bool],
  depths : Map[String, Int],
  visiting : Map[String, Bool],
  cycles : Array[(String, String)],
) -> Int {
  // Already computed
  match depths.get(symbol_id) {
    Some(d) => return d
    None => ()
  }
  // Cycle detection
  if visiting.contains(symbol_id) {
    return 0 // Break cycle, already recorded
  }
  visiting.set(symbol_id, true)
  let callees = get_callees(graph, symbol_id)
  let mut max_callee_depth = -1
  for callee in callees {
    // Only consider callees within our valid set
    if not(valid_ids.contains(callee)) {
      continue
    }
    // Check for cycle
    if visiting.contains(callee) {
      cycles.push((symbol_id, callee))
      continue
    }
    let d = compute_depth_recursive(
      graph, callee, valid_ids, depths, visiting, cycles,
    )
    if d > max_callee_depth {
      max_callee_depth = d
    }
  }
  visiting.remove(symbol_id)
  let depth = max_callee_depth + 1
  depths.set(symbol_id, depth)
  depth
}

///|
/// Compute top-down traversal order.
/// Returns functions ordered from roots (no callers) to leaves.
pub fn compute_top_down_order(
  graph : @graph.CodeGraph,
  function_ids : Array[String],
) -> TraversalResult {
  let result = TraversalResult::new()
  let id_set : Map[String, Bool] = {}
  for id in function_ids {
    id_set.set(id, true)
  }
  // Compute depths from callers using DFS
  let visiting : Map[String, Bool] = {}
  for id in function_ids {
    let _ = compute_caller_depth_recursive(
      graph,
      id,
      id_set,
      result.depths,
      visiting,
      result.cycles,
    )
  }
  // Sort by depth (ascending) for top-down order
  let depth_pairs : Array[(String, Int)] = []
  for entry in result.depths {
    depth_pairs.push((entry.0, entry.1))
  }
  depth_pairs.sort_by(fn(a, b) { a.1.compare(b.1) })
  for pair in depth_pairs {
    result.order.push(pair.0)
  }
  result
}

///|
/// Recursive caller depth computation.
fn compute_caller_depth_recursive(
  graph : @graph.CodeGraph,
  symbol_id : String,
  valid_ids : Map[String, Bool],
  depths : Map[String, Int],
  visiting : Map[String, Bool],
  cycles : Array[(String, String)],
) -> Int {
  match depths.get(symbol_id) {
    Some(d) => return d
    None => ()
  }
  if visiting.contains(symbol_id) {
    return 0
  }
  visiting.set(symbol_id, true)
  let callers = get_callers(graph, symbol_id)
  let mut max_caller_depth = -1
  for caller in callers {
    if not(valid_ids.contains(caller)) {
      continue
    }
    if visiting.contains(caller) {
      cycles.push((caller, symbol_id))
      continue
    }
    let d = compute_caller_depth_recursive(
      graph, caller, valid_ids, depths, visiting, cycles,
    )
    if d > max_caller_depth {
      max_caller_depth = d
    }
  }
  visiting.remove(symbol_id)
  let depth = max_caller_depth + 1
  depths.set(symbol_id, depth)
  depth
}

///|
/// Traverse functions in bottom-up order, calling visitor for each.
pub fn traverse_bottom_up(
  units : Array[@types.FunctionUnit],
  visitor : (@types.FunctionUnit) -> Unit,
) -> Unit {
  // Sort by depth ascending
  let sorted = units.copy()
  sorted.sort_by(fn(a, b) { a.depth.compare(b.depth) })
  for unit in sorted {
    visitor(unit)
  }
}

///|
/// Traverse functions in top-down order, calling visitor for each.
pub fn traverse_top_down(
  units : Array[@types.FunctionUnit],
  visitor : (@types.FunctionUnit) -> Unit,
) -> Unit {
  // Sort by depth descending
  let sorted = units.copy()
  sorted.sort_by(fn(a, b) { b.depth.compare(a.depth) })
  for unit in sorted {
    visitor(unit)
  }
}
