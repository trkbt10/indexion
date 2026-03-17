///|
/// Serialization wrapper for code extraction results.
priv struct CodeExtractResult {
  code_units : Array[CodeUnit]
  code_file_states : Array[FileState]
} derive(ToJson, @json.FromJson)

///|
/// Serialization wrapper for document extraction results.
priv struct DocExtractResult {
  fragments : Array[DocFragment]
  file_states : Array[FileState]
  used_specs : Array[String]
} derive(ToJson, @json.FromJson)

///|
/// Serialization wrapper for matching batch results.
priv struct MatchChunkResult {
  candidates : Array[ReconcileCandidate]
  module_covered_symbols : Int
} derive(ToJson, @json.FromJson)

///|
/// Run code and document extraction in parallel using fork.
/// Child A: extract code units + compute code file states.
/// Child B: extract document fragments + compute doc file states.
fn parallel_extract(
  discovered_paths : Array[String],
  config : ReconcileConfig,
  registry : @registry.KGFRegistry,
) -> (Array[CodeUnit], Array[DocFragment], Array[FileState], Array[String]) {
  let results = @parallel.run_parallel([
    fn() {
      let code_units = build_code_units_fast(discovered_paths, registry)
      let code_file_states = collect_code_file_states(code_units, config)
      let result : CodeExtractResult = { code_units, code_file_states }
      result.to_json().stringify()
    },
    fn() {
      let (fragments, file_states, used_specs) = collect_document_fragments(
        discovered_paths, config, registry,
      )
      let result : DocExtractResult = { fragments, file_states, used_specs }
      result.to_json().stringify()
    },
  ])
  let code_result : CodeExtractResult = deserialize_or_default(results[0], {
    code_units: [],
    code_file_states: [],
  })
  let doc_result : DocExtractResult = deserialize_or_default(results[1], {
    fragments: [],
    file_states: [],
    used_specs: [],
  })
  let all_file_states = code_result.code_file_states + doc_result.file_states
  (
    code_result.code_units,
    doc_result.fragments,
    all_file_states,
    doc_result.used_specs,
  )
}

///|
/// Run candidate matching in parallel across multiple workers.
/// Pre-computes shared data in parent, then partitions units across workers.
fn build_candidates_parallel(
  units : Array[CodeUnit],
  fragments : Array[DocFragment],
  config : ReconcileConfig,
  registry : @registry.KGFRegistry,
  num_workers : Int,
) -> CandidateBuildResult {
  if units.length() < 20 || num_workers <= 1 {
    return build_candidates(units, fragments, config, registry)
  }
  // Pre-compute shared data in parent (children inherit via fork COW)
  let module_coverage = build_module_coverage_index(
    units,
    fragments,
    registry,
    config.target_dir,
    config.documents.doc_paths,
  )
  let fragment_signals = build_fragment_match_signals(fragments, registry)
  let inverted_index = build_fragment_inverted_index(
    fragments, fragment_signals,
  )
  let effective_workers = if num_workers > units.length() / 10 {
    let w = units.length() / 10
    if w < 2 {
      2
    } else {
      w
    }
  } else {
    num_workers
  }
  let chunk_size = (units.length() + effective_workers - 1) / effective_workers
  let tasks : Array[() -> String] = []
  for w in 0..<effective_workers {
    let s = w * chunk_size
    let e_raw = (w + 1) * chunk_size
    let e = if e_raw < units.length() { e_raw } else { units.length() }
    if s >= units.length() {
      break
    }
    tasks.push(fn() {
      let (candidates, covered) = match_units_batch(
        units, s, e, fragments, module_coverage, fragment_signals, inverted_index,
        config,
      )
      let result : MatchChunkResult = {
        candidates,
        module_covered_symbols: covered,
      }
      result.to_json().stringify()
    })
  }
  let results = @parallel.run_parallel(tasks)
  // Merge results from all workers
  let all_candidates : Array[ReconcileCandidate] = []
  let mut total_covered = 0
  for json_str in results {
    let chunk : MatchChunkResult = deserialize_or_default(json_str, {
      candidates: [],
      module_covered_symbols: 0,
    })
    for c in chunk.candidates {
      all_candidates.push(c)
    }
    total_covered += chunk.module_covered_symbols
  }
  all_candidates.sort_by(fn(a, b) {
    let status_cmp = status_priority(a.status).compare(
      status_priority(b.status),
    )
    if status_cmp != 0 {
      status_cmp
    } else {
      b.mapping_confidence.compare(a.mapping_confidence)
    }
  })
  { candidates: all_candidates, module_covered_symbols: total_covered }
}

///|
fn[T : @json.FromJson] deserialize_or_default(
  json_str : String,
  default : T,
) -> T {
  let json = @json.parse(json_str) catch { _ => return default }
  @json.from_json(json) catch {
    _ => default
  }
}
