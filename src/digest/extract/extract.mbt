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
} derive(Eq, Debug)

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
  let callees = graph.get_callees(symbol_id)
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
/// Resolve the file path for a symbol via its module.
fn resolve_file_path(graph : @graph.CodeGraph, module_id : String) -> String? {
  match graph.get_module(module_id) {
    Some(m) => m.file
    None => None
  }
}

///|
/// Extract a single FunctionUnit from a symbol.
/// When `file_hashes` is provided, the source_hash is derived from the file's
/// content hash combined with the symbol identity — this correctly detects when
/// the file containing the function has changed, even though CodeGraph does not
/// store function bodies.
/// When `file_hashes` is absent, falls back to symbol metadata hashing (legacy).
pub fn extract_function_unit(
  graph : @graph.CodeGraph,
  symbol : @graph.SymbolNode,
  depth_memo : Map[String, Int],
  file_hashes? : Map[String, @cas_types.ContentHash]? = None,
) -> @types.FunctionUnit {
  let callers = graph.get_callers(symbol.id)
  let callees = graph.get_callees(symbol.id)
  // Compute source hash:
  // - With file_hashes: hash(file_content_hash + symbol.id + symbol.name + symbol.kind)
  //   This changes when the file changes OR when the symbol identity changes.
  // - Without file_hashes: hash(symbol.id + symbol.name + symbol.kind) (legacy fallback)
  let source_hash = match file_hashes {
    Some(fh) => {
      let file_path = resolve_file_path(graph, symbol.module_id)
      let file_hash = match file_path {
        Some(p) =>
          match fh.get(p) {
            Some(h) => h.to_string()
            None => ""
          }
        None => ""
      }
      // Combine file hash with symbol identity for a per-symbol source hash
      // that accurately reflects file content changes
      let source_content = file_hash +
        "\u0000" +
        symbol.id +
        "\u0000" +
        symbol.name +
        "\u0000" +
        symbol.kind
      @hash.compute_source_hash(source_content)
    }
    None => {
      // Legacy fallback: symbol metadata only (cannot detect body changes)
      let source_content = symbol.id + ":" + symbol.name + ":" + symbol.kind
      @hash.compute_source_hash(source_content)
    }
  }
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
/// When `file_hashes` is provided (path -> content hash), source_hash is computed
/// from actual file content, enabling accurate change detection.
pub fn extract_function_units(
  graph : @graph.CodeGraph,
  config : ExtractConfig,
  file_hashes? : Map[String, @cas_types.ContentHash]? = None,
) -> Array[@types.FunctionUnit] {
  let result : Array[@types.FunctionUnit] = []
  let depth_memo : Map[String, Int] = {}
  for entry in graph.get_symbols() {
    let symbol = entry.1
    // Check symbol kind
    if !should_include_kind(symbol.kind, config) {
      continue
    }
    // Check if internal/external
    let is_internal = is_internal_module(graph, symbol.module_id)
    if !is_internal && !config.include_external {
      continue
    }
    let unit = extract_function_unit(graph, symbol, depth_memo, file_hashes~)
    result.push(unit)
  }
  result
}

///|
/// Extract only leaf functions (functions with no outgoing calls).
pub fn extract_leaf_functions(
  graph : @graph.CodeGraph,
  config : ExtractConfig,
  file_hashes? : Map[String, @cas_types.ContentHash]? = None,
) -> Array[@types.FunctionUnit] {
  let all_units = extract_function_units(graph, config, file_hashes~)
  all_units.filter(fn(u) { u.is_leaf() })
}

///|
/// Extract functions at a specific depth.
pub fn extract_functions_at_depth(
  graph : @graph.CodeGraph,
  config : ExtractConfig,
  depth : Int,
  file_hashes? : Map[String, @cas_types.ContentHash]? = None,
) -> Array[@types.FunctionUnit] {
  let all_units = extract_function_units(graph, config, file_hashes~)
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
