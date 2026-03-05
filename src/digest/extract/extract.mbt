// Extract FunctionUnits from CodeGraph.
// Follows CLAUDE.md: use graph information (ModuleNode.file) for internal/external distinction.

///|
/// Configuration for function extraction.
pub(all) struct ExtractConfig {
  /// Include functions from external packages (no file path).
  include_external : Bool
  /// Minimum function body length to index (placeholder for future).
  min_body_length : Int
  /// Symbol kinds to exclude (e.g., ["param", "field"]).
  /// Empty means include all symbols.
  exclude_kinds : Array[String]
} derive(Eq, Show)

///|
/// Create default extraction config.
/// Excludes Param (function parameters) by default.
pub fn ExtractConfig::default() -> ExtractConfig {
  { include_external: false, min_body_length: 0, exclude_kinds: ["param"] }
}

///|
/// Create config that includes all symbols (no exclusions).
pub fn ExtractConfig::all() -> ExtractConfig {
  { include_external: false, min_body_length: 0, exclude_kinds: [] }
}

///|
/// Check if a module is internal (has file path).
/// Per CLAUDE.md: use ModuleNode.file field presence, not hardcoded org names.
fn is_internal_module(graph : @graph.CodeGraph, module_id : String) -> Bool {
  match graph.get_module(module_id) {
    Some(m) => m.file is Some(_)
    None => false
  }
}

///|
/// Check if a symbol kind should be included (not in exclude list).
fn should_include_kind(kind : String, config : ExtractConfig) -> Bool {
  if config.exclude_kinds.length() == 0 {
    return true
  }
  let kind_lower = kind.to_lower()
  for excluded in config.exclude_kinds {
    if kind_lower == excluded.to_lower() {
      return false
    }
  }
  true
}

///|
/// Get callers of a symbol (symbols that call this one).
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
/// Get callees of a symbol (symbols that this one calls).
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
/// Compute depth of a function in call graph.
/// Depth 0 = leaf function (no outgoing calls).
/// Uses memoization to avoid recomputation.
fn compute_depth(
  graph : @graph.CodeGraph,
  symbol_id : String,
  memo : Map[String, Int],
  visiting : Map[String, Bool],
) -> Int {
  // Check memo
  match memo.get(symbol_id) {
    Some(d) => return d
    None => ()
  }
  // Detect cycles
  if visiting.contains(symbol_id) {
    return 0 // Break cycle
  }
  visiting.set(symbol_id, true)
  let callees = get_callees(graph, symbol_id)
  if callees.length() == 0 {
    memo.set(symbol_id, 0)
    visiting.remove(symbol_id)
    return 0
  }
  let mut max_depth = 0
  for callee in callees {
    let d = compute_depth(graph, callee, memo, visiting)
    if d + 1 > max_depth {
      max_depth = d + 1
    }
  }
  memo.set(symbol_id, max_depth)
  visiting.remove(symbol_id)
  max_depth
}

///|
/// Extract a single FunctionUnit from a symbol.
pub fn extract_function_unit(
  graph : @graph.CodeGraph,
  symbol : @graph.SymbolNode,
  depth_memo : Map[String, Int],
) -> @types.FunctionUnit {
  let callers = get_callers(graph, symbol.id)
  let callees = get_callees(graph, symbol.id)
  // Compute source hash from symbol info (placeholder - actual source not available in graph)
  // In real use, source would be fetched from file system
  let source_content = symbol.id + ":" + symbol.name + ":" + symbol.kind
  let source_hash = @hash.compute_source_hash(source_content)
  // Compute context hash including call relationships
  let context_hash = @hash.compute_context_hash(source_hash, callers, callees)
  // Compute depth
  let visiting : Map[String, Bool] = {}
  let depth = compute_depth(graph, symbol.id, depth_memo, visiting)
  @types.FunctionUnit::new(
    symbol,
    symbol.module_id,
    source_hash,
    context_hash,
    callers,
    callees,
    depth,
  )
}

///|
/// Extract all FunctionUnits from a CodeGraph.
pub fn extract_function_units(
  graph : @graph.CodeGraph,
  config : ExtractConfig,
) -> Array[@types.FunctionUnit] {
  let result : Array[@types.FunctionUnit] = []
  let depth_memo : Map[String, Int] = {}
  for entry in graph.get_symbols() {
    let symbol = entry.1
    // Check symbol kind
    if not(should_include_kind(symbol.kind, config)) {
      continue
    }
    // Check if internal/external
    let is_internal = is_internal_module(graph, symbol.module_id)
    if not(is_internal) && not(config.include_external) {
      continue
    }
    let unit = extract_function_unit(graph, symbol, depth_memo)
    result.push(unit)
  }
  result
}

///|
/// Extract only leaf functions (functions with no outgoing calls).
pub fn extract_leaf_functions(
  graph : @graph.CodeGraph,
  config : ExtractConfig,
) -> Array[@types.FunctionUnit] {
  let all_units = extract_function_units(graph, config)
  all_units.filter(fn(u) { u.is_leaf() })
}

///|
/// Extract functions at a specific depth.
pub fn extract_functions_at_depth(
  graph : @graph.CodeGraph,
  config : ExtractConfig,
  depth : Int,
) -> Array[@types.FunctionUnit] {
  let all_units = extract_function_units(graph, config)
  all_units.filter(fn(u) { u.depth == depth })
}

///|
/// Get the maximum depth in the call graph.
pub fn get_max_depth(units : Array[@types.FunctionUnit]) -> Int {
  let mut max = 0
  for unit in units {
    if unit.depth > max {
      max = unit.depth
    }
  }
  max
}
