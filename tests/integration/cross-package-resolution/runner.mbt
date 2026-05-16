// Snapshot runner for cross-package-resolution integration tests.
//
// A snapshot captures the observable output of `doc graph --format=codegraph`
// for a fixture project, distilled to the facts this test suite cares about:
//
//   * The set of modules the graph knows about.
//   * Every `moduleDependsOn` edge.
//   * A graph-structural invariant: every built-in edge kind (declares,
//     moduleDependsOn, calls, …) must have both endpoints registered as
//     modules or symbols. Custom (KGF-emitted metadata) edges are excluded
//     from this check because their `to` is a free-form value like a project
//     version string or a keyword.
//
// The snapshot is deterministic (all arrays are sorted) so textual diffs
// are meaningful. Set `INDEXION_UPDATE_SNAPSHOTS=1` to regenerate the
// snapshot file from the current analyzer output.

///|
/// Analyze a fixture directory and return the resulting CodeGraph. The test
/// caller passes the relative path to the fixture from the repo root; the
/// analyzer is invoked identically to the `doc graph` CLI.
pub fn analyze_fixture(fixture_dir : String) -> @graph.CodeGraph raise {
  let exists = @fs.is_dir(fixture_dir) catch { _ => false }
  if !exists {
    fail("fixture directory not found: " + fixture_dir)
  }
  let specs_dir = "kgfs"
  let input_paths = [fixture_dir]
  let registry = @kgf_features.load_registry_or_empty(
    specs_dir~,
    target_dirs=input_paths,
  )
  let kgf_ignore = registry.collect_ignore_patterns()
  let discover_opts = @pipeline.DiscoverOptions::new(
    root_dir=@pipeline.root_dir_from_paths(input_paths),
    kgf_ignore~,
  )
  let candidate_paths = @pipeline.discover_files(input_paths, discover_opts)
  if candidate_paths.length() == 0 {
    fail("no candidate files under " + fixture_dir)
  }
  let specs = registry.to_specs_map()
  let files = @pipeline.collect_supported_files(candidate_paths, registry)
  if files.length() == 0 {
    fail("no supported files under " + fixture_dir)
  }
  let doc_config = @build.DocConfig::new(
    files,
    specs,
    options=@render.RenderOptions::new(format=@render.OutputFormat::json()),
  )
  let (_, graph) = @build.build_with_graph_progress(doc_config, None)
  graph
}

///|
/// Build a deterministic snapshot JSON string from a graph. The snapshot is
/// derived from the serialized (round-tripped) graph so it reflects exactly
/// what downstream consumers observe.
///
/// Shape:
///   {
///     "modules": [sorted ids],
///     "moduleDependsOn": [sorted edges with via/alias attrs],
///     "stats": { "symbols": N, "edges": M, "unresolved_structural_edges": 0 }
///   }
pub fn snapshot_of(graph : @graph.CodeGraph) -> String raise {
  let serialized = graph.to_json_string()
  let round_tripped = match @graph.CodeGraph::from_json_string(serialized) {
    Some(g) => g
    None => fail("graph JSON round-trip failed")
  }
  let modules = round_tripped.get_modules()
  let symbols = round_tripped.get_symbols()
  let module_ids : Array[String] = []
  for entry in modules {
    module_ids.push(entry.0)
  }
  module_ids.sort()
  let module_json : Array[Json] = []
  for id in module_ids {
    module_json.push(id.to_json())
  }
  // Collect moduleDependsOn edges in a deterministic order (sorted by
  // from, to, via, alias so re-runs produce identical snapshots).
  let dep_rows : Array[(String, String, String, String)] = []
  for edge in round_tripped.get_edges() {
    if !(edge.kind is @graph.ModuleDependsOn) {
      continue
    }
    let via = edge.attrs.get("via").unwrap_or("")
    let alias_name = edge.attrs.get("alias").unwrap_or("")
    dep_rows.push((edge.from, edge.to, via, alias_name))
  }
  dep_rows.sort()
  let dep_json : Array[Json] = []
  for row in dep_rows {
    let obj : Map[String, Json] = {}
    obj.set("from", row.0.to_json())
    obj.set("to", row.1.to_json())
    if row.2.length() > 0 {
      obj.set("via", row.2.to_json())
    }
    if row.3.length() > 0 {
      obj.set("alias", row.3.to_json())
    }
    dep_json.push(Json::object(obj))
  }
  let unresolved = count_unresolved_structural_in(round_tripped)
  // Count unique edges by (kind, from, to) and aggregate per-kind counts.
  // The raw `edge_count()` includes duplicates and varies with filesystem
  // traversal order on different platforms (macOS APFS vs Linux ext4);
  // deduping pins the snapshot to the set of distinct relationships the
  // graph asserts, regardless of how many times each was emitted during
  // the build pass.
  let unique_edge_keys : Map[String, Unit] = {}
  let by_kind : Map[String, Int] = {}
  for edge in round_tripped.get_edges() {
    let kind_str = edge.kind.to_string()
    let key = kind_str + "\u{1f}" + edge.from + "\u{1f}" + edge.to
    if unique_edge_keys.contains(key) {
      continue
    }
    unique_edge_keys.set(key, ())
    let prev = by_kind.get(kind_str).unwrap_or(0)
    by_kind.set(kind_str, prev + 1)
  }
  let kind_keys : Array[String] = []
  for entry in by_kind {
    kind_keys.push(entry.0)
  }
  kind_keys.sort()
  let by_kind_json : Map[String, Json] = {}
  for k in kind_keys {
    by_kind_json.set(k, by_kind.get(k).unwrap().to_json())
  }
  let stats : Map[String, Json] = {}
  stats.set("symbols", symbols.length().to_json())
  stats.set("edges", unique_edge_keys.length().to_json())
  stats.set("edgesByKind", Json::object(by_kind_json))
  stats.set("unresolved_structural_edges", unresolved.to_json())
  let root : Json = {
    "modules": Json::array(module_json),
    "moduleDependsOn": Json::array(dep_json),
    "stats": Json::object(stats),
  }
  root.stringify(indent=2)
}

///|
/// Check unresolved structural edges against a pre-parsed graph (skips the
/// serialization round-trip that `count_unresolved_structural` performs).
pub fn count_unresolved_structural_in(graph : @graph.CodeGraph) -> Int {
  let modules = graph.get_modules()
  let symbols = graph.get_symbols()
  let mut n = 0
  for edge in graph.get_edges() {
    if edge.kind is @graph.Custom(_) {
      continue
    }
    if !modules.contains(edge.from) && !symbols.contains(edge.from) {
      n = n + 1
      continue
    }
    if !modules.contains(edge.to) && !symbols.contains(edge.to) {
      n = n + 1
    }
  }
  n
}

///|
/// Count edges of built-in kinds whose endpoints are not registered as a
/// module or symbol in the serialized graph. A non-zero count is a failure
/// of the graph-structural completeness invariant this test suite exists to
/// guard.
///
/// The check runs against the round-tripped graph (to_json → from_json) so
/// it observes the final output shape including any backfill the serializer
/// performs. This matches what downstream consumers (the React viewer,
/// IDE plugins, etc.) actually see.
pub fn count_unresolved_structural(graph : @graph.CodeGraph) -> Int {
  let json_str = graph.to_json_string()
  let parsed = match @graph.CodeGraph::from_json_string(json_str) {
    Some(g) => g
    None => return -1
  }
  let modules = parsed.get_modules()
  let symbols = parsed.get_symbols()
  let mut n = 0
  for edge in parsed.get_edges() {
    if edge.kind is @graph.Custom(_) {
      continue
    }
    if !modules.contains(edge.from) && !symbols.contains(edge.from) {
      n = n + 1
      continue
    }
    if !modules.contains(edge.to) && !symbols.contains(edge.to) {
      n = n + 1
    }
  }
  n
}

///|
/// Compare `actual` against the contents of `snapshot_path`. On mismatch,
/// either update the snapshot (if `INDEXION_UPDATE_SNAPSHOTS=1` is set) or
/// fail with a diff-friendly error message.
pub fn assert_snapshot_matches(
  snapshot_path : String,
  actual : String,
) -> Unit raise {
  let update = is_update_mode()
  let existing : String? = Some(@fs.read_file_to_string(snapshot_path)) catch {
    _ => None
  }
  match existing {
    Some(stored) =>
      if stored == actual {
        return
      } else if update {
        write_snapshot(snapshot_path, actual)
      } else {
        let msg = "snapshot mismatch: " +
          snapshot_path +
          "\n\n--- expected (" +
          stored.length().to_string() +
          " bytes) ---\n" +
          stored +
          "\n\n--- actual (" +
          actual.length().to_string() +
          " bytes) ---\n" +
          actual +
          "\n\nRun with INDEXION_UPDATE_SNAPSHOTS=1 to regenerate."
        fail(msg)
      }
    None =>
      if update {
        write_snapshot(snapshot_path, actual)
      } else {
        fail(
          "snapshot file missing: " +
          snapshot_path +
          "\nRun with INDEXION_UPDATE_SNAPSHOTS=1 to create it. Actual content:\n" +
          actual,
        )
      }
  }
}

///|
fn is_update_mode() -> Bool {
  match @sys.get_env_var("INDEXION_UPDATE_SNAPSHOTS") {
    Some(v) => v == "1" || v == "true"
    None => false
  }
}

///|
fn write_snapshot(path : String, content : String) -> Unit raise {
  @fs.write_string_to_file(path, content) catch {
    @fs.IOError(msg) => fail("failed to write snapshot " + path + ": " + msg)
  }
}
