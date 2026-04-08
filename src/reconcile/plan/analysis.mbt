///|
fn report_config(config : ReconcileConfig) -> ReconcileReportConfig {
  {
    target_dir: config.target_dir,
    specs_dir: config.specs_dir,
    index_dir: config.index_dir,
    review_results_path: config.review_results_path,
    doc_scope: config.documents.scope_name,
    doc_paths: config.documents.doc_paths,
    doc_specs: config.documents.doc_specs,
    threshold_seconds: config.threshold_seconds,
    max_candidates: config.max_candidates,
    allow_file_fallback: config.allow_file_fallback,
    git_preferred: config.git_preferred,
    mtime_fallback: config.mtime_fallback,
    logical_review_mode: config.logical_review_mode,
  }
}

///|
pub async fn collect_document_fragments(
  discovered_files : Array[@pipeline.SupportedFile],
  config : ReconcileConfig,
  registry : @registry.KGFRegistry,
) -> (Array[DocFragment], Array[FileState], Array[String]) {
  let fragments : Array[DocFragment] = []
  let file_states : Array[FileState] = []
  let used_specs : Array[String] = []
  for file in discovered_files {
    if !is_document_candidate(file.path, file.content_type, config, registry) {
      continue
    }
    let spec = match select_document_spec_for_file(file, config, registry) {
      Some(value) => value
      None => continue
    }
    let doc_fragments = extract_document_fragments(
      file.path,
      spec,
      file.content,
    )
    for fragment in doc_fragments {
      fragments.push(fragment)
    }
    if !contains_string(used_specs, spec) {
      used_specs.push(spec)
    }
    let ts = timestamp_for_path(config.target_dir, file.path, config)
    let file_state = @reconcile_tracking.FileState::new(
      file.path,
      "doc",
      spec,
      @cas_hash.compute_hash(file.content).to_string(),
      ts.epoch_seconds,
      @git.file_mtime_seconds(file.path),
      ts.is_dirty,
    )
    file_states.push(file_state)
  }
  (fragments, file_states, used_specs)
}

///|
async fn collect_code_file_states(
  units : Array[CodeUnit],
  config : ReconcileConfig,
) -> Array[FileState] {
  let file_map : Map[String, Bool] = {}
  let file_states : Array[FileState] = []
  for unit in units {
    if file_map.contains(unit.module_path) {
      continue
    }
    file_map.set(unit.module_path, true)
    let content = @fs.read_file_to_string(unit.module_path) catch {
      _ => continue
    }
    let ts = timestamp_for_path(config.target_dir, unit.module_path, config)
    file_states.push(
      @reconcile_tracking.FileState::new(
        unit.module_path,
        "code",
        "code",
        @cas_hash.compute_hash(content).to_string(),
        ts.epoch_seconds,
        @git.file_mtime_seconds(unit.module_path),
        ts.is_dirty,
      ),
    )
  }
  file_states
}

///|
fn maybe_use_cache(
  manifest : ReconcileManifest,
  config_hash : String,
  source_fingerprint : String,
  index_dir : String,
) -> ReconcileReport? {
  if manifest.config_hash != config_hash ||
    manifest.source_fingerprint != source_fingerprint {
    return None
  }
  match load_cached_report(index_dir) {
    Some(report) =>
      if report.cache_state.review_state_hash == manifest.review_state_hash {
        Some({
          ..report,
          cache_state: {
            ..report.cache_state,
            cache_hit: true,
            source_fingerprint,
            review_state_hash: manifest.review_state_hash,
          },
        })
      } else {
        None
      }
    None => None
  }
}

///|
/// Core analysis result — discriminated by whether cache was hit.
priv enum AnalysisResult {
  /// Cache hit: only the report is available, no sync state to persist.
  Cached(ReconcileReport)
  /// Full analysis: report + sync state needed for CLI cache persistence.
  Fresh(ReconcileReport, FreshAnalysisState)
}

///|
/// State from a full (non-cached) analysis, needed for CLI cache persistence.
priv struct FreshAnalysisState {
  sync_result : IndexSyncResult
  all_file_states : Array[FileState]
  config_hash : String
  source_fingerprint : String
  generated_at : Int
}

///|
fn AnalysisResult::report(self : AnalysisResult) -> ReconcileReport {
  match self {
    Cached(r) => r
    Fresh(r, _) => r
  }
}

///|
async fn run_analysis(config : ReconcileConfig) -> AnalysisResult? {
  if config.target_dir.length() == 0 {
    return None
  }
  let generated_at = current_epoch_seconds()
  let mut manifest = load_manifest(config.index_dir)
  let db = load_record_db(config.index_dir)
  let review_decisions = load_review_decisions(config.review_results_path)
  let db = if review_decisions.length() > 0 {
    let (updated_manifest, updated_db) = apply_review_decisions(
      manifest, db, review_decisions, generated_at,
    )
    manifest = updated_manifest
    updated_db
  } else {
    db
  }
  let registry = @kgf_features.load_registry_or_empty(
    specs_dir=config.specs_dir,
    target_dir=config.target_dir,
  )
  let kgf_ignore = registry.collect_ignore_patterns()
  let discover_opts = @pipeline.DiscoverOptions::new(
    kgf_ignore~,
    root_dir=config.target_dir,
  )
  let discovered_paths = @pipeline.discover_files(
    discovery_roots(config.target_dir),
    discover_opts,
  )
  let discovered_files = @pipeline.load_supported_file_info(
    discovered_paths, registry,
  )
  let project_markers = registry.get_project_markers()
  let code_units = build_code_units_fast(discovered_files, registry)
  let (doc_fragments, doc_file_states, used_specs, code_file_states) = @async.with_task_group(group => {
      let doc_task = group.spawn(() => {
        collect_document_fragments(discovered_files, config, registry)
      })
      let code_task = group.spawn(() => {
        collect_code_file_states(code_units, config)
      })
      let (doc_fragments, doc_file_states, used_specs) = doc_task.wait()
      let code_file_states = code_task.wait()
      (doc_fragments, doc_file_states, used_specs, code_file_states)
    },
  )
  let all_file_states = code_file_states + doc_file_states
  let config_hash = build_config_hash(config)
  let source_fingerprint = build_source_fingerprint(
    config_hash, all_file_states,
  )
  match
    maybe_use_cache(manifest, config_hash, source_fingerprint, config.index_dir) {
    Some(report) => return Some(Cached(report))
    None => ()
  }
  let candidate_build = if config.parallel && @parallel.available() {
    build_candidates_concurrent(
      code_units,
      doc_fragments,
      config,
      registry,
      @parallel.cpu_count(),
    )
  } else {
    build_candidates(code_units, doc_fragments, config, registry)
  }
  let raw_aggregate_suggestions = build_aggregate_suggestions(
    candidate_build.candidates,
    [],
    doc_fragments,
    config.target_dir,
    project_markers,
  )
  let visible_candidates = limit_candidates(
    collapse_aggregate_only_candidates(
      candidate_build.candidates,
      raw_aggregate_suggestions,
      config.target_dir,
      project_markers,
    ),
    config.max_candidates,
  )
  let sync_result = sync_candidates_with_index(
    visible_candidates,
    manifest,
    db,
    config.logical_review_mode,
    generated_at,
  )
  let aggregate_suggestions = build_aggregate_suggestions(
    candidate_build.candidates,
    sync_result.candidates,
    doc_fragments,
    config.target_dir,
    project_markers,
  )
  let vocabulary_divergences = compute_vocabulary_divergences(
    discovered_files, config, registry,
  )
  let summary = build_summary(
    code_units,
    doc_fragments,
    sync_result.candidates,
    aggregate_suggestions,
    candidate_build.module_covered_symbols,
    sync_result.logical_reviews,
    sync_result.reused_logical_reviews,
  )
  let summary = {
    ..summary,
    vocabulary_divergence_count: vocabulary_divergences.length(),
    max_vocabulary_divergence: max_distance(vocabulary_divergences),
  }
  let report = {
    version: "reconcile-v1",
    generated_at,
    config: report_config(config),
    summary,
    aggregate_suggestions,
    candidates: sync_result.candidates,
    logical_reviews: sync_result.logical_reviews,
    vocabulary_divergences,
    skipped: [],
    used_specs: sort_strings(used_specs),
    cache_state: {
      cache_hit: false,
      source_fingerprint,
      review_state_hash: sync_result.manifest.review_state_hash,
      reused_candidates: sync_result.reused_candidates,
      reused_logical_reviews: sync_result.reused_logical_reviews,
    },
  }
  Some(
    Fresh(report, {
      sync_result,
      all_file_states,
      config_hash,
      source_fingerprint,
      generated_at,
    }),
  )
}

///|
pub async fn report(config : ReconcileConfig) -> ReconcileReport? {
  match run_analysis(config) {
    Some(result) => Some(result.report())
    None => None
  }
}

///|
pub async fn persisted_report(config : ReconcileConfig) -> ReconcileReport? {
  let result = match run_analysis(config) {
    Some(value) => value
    None => return None
  }
  match result {
    Fresh(report, state) => {
      let manifest_to_save = {
        ..state.sync_result.manifest,
        version: "reconcile-v1",
        updated_at: state.generated_at,
        config_hash: state.config_hash,
        source_fingerprint: state.source_fingerprint,
        report_path: report_cache_path(config.index_dir),
        files: {
          let map : Map[String, FileState] = {}
          for s in state.all_file_states {
            map.set(s.path, s)
          }
          map
        },
      }
      save_cached_report(config.index_dir, report)
      save_manifest(config.index_dir, manifest_to_save)
      save_record_db(config.index_dir, state.sync_result.db)
      cleanup_stale_index(config.index_dir)
      Some(report)
    }
    Cached(report) => Some(report)
  }
}
