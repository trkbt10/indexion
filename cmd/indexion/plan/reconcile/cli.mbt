///|
fn write_output(output : String, content : String) -> Unit {
  if output.length() == 0 || output == "-" {
    println(content)
    return
  }
  @config_paths.ensure_parent_dir(output)
  @fs.write_string_to_file(output, content) catch {
    e => {
      println("Error writing output: " + e.to_string())
      return
    }
  }
  println("Reconcile report written to: " + output)
}

///|
fn collect_document_fragments(
  discovered_paths : Array[String],
  config : ReconcileConfig,
  registry : @registry.KGFRegistry,
) -> (Array[DocFragment], Array[FileState], Array[String]) {
  let fragments : Array[DocFragment] = []
  let file_states : Array[FileState] = []
  let used_specs : Array[String] = []
  for path in discovered_paths {
    if not(is_document_path(path, config, registry)) {
      continue
    }
    let spec = match select_document_spec(path, config, registry) {
      Some(value) => value
      None => continue
    }
    let content = @fs.read_file_to_string(path) catch { _ => continue }
    let doc_fragments = extract_document_fragments(path, spec, content)
    for fragment in doc_fragments {
      fragments.push(fragment)
    }
    if not(contains_string(used_specs, spec)) {
      used_specs.push(spec)
    }
    let ts = timestamp_for_path(config.target_dir, path, config)
    let file_state = {
      path,
      file_kind: "doc",
      spec,
      content_hash: @cas_hash.compute_hash(content).to_string(),
      git_time: ts.epoch_seconds,
      mtime: @git.file_mtime_seconds(path),
      git_dirty: ts.is_dirty,
    }
    file_states.push(file_state)
  }
  (fragments, file_states, used_specs)
}

///|
fn collect_code_file_states(
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
    file_states.push({
      path: unit.module_path,
      file_kind: "code",
      spec: "code",
      content_hash: @cas_hash.compute_hash(content).to_string(),
      git_time: ts.epoch_seconds,
      mtime: @git.file_mtime_seconds(unit.module_path),
      git_dirty: ts.is_dirty,
    })
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
/// Entry point for the reconcile subcommand.
pub fn run(args : Array[String], start_idx : Int) -> Unit {
  let config = resolve_config(args, start_idx)
  if config.show_help {
    show_help()
    return
  }
  if config.target_dir.length() == 0 {
    println("Error: directory path required.")
    println("")
    show_help()
    return
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
  // Fast path: KGF lexer-only symbol extraction (no PEG parse)
  let registry = @registry.KGFRegistry::load_from_dir(config.specs_dir)
  let kgf_ignore = registry.collect_ignore_patterns()
  let discover_opts = @pipeline.DiscoverOptions::new(
    kgf_ignore~,
    root_dir=config.target_dir,
  )
  let discovered_paths = @pipeline.discover_files(
    discovery_roots(config.target_dir),
    discover_opts,
  )
  let project_markers = registry.get_project_markers()
  let code_units = build_code_units_fast(discovered_paths, registry)
  let (doc_fragments, doc_file_states, used_specs) = collect_document_fragments(
    discovered_paths, config, registry,
  )
  let code_file_states = collect_code_file_states(code_units, config)
  let all_file_states = code_file_states + doc_file_states
  let config_hash = build_config_hash(config)
  let source_fingerprint = build_source_fingerprint(
    config_hash, all_file_states,
  )
  match
    maybe_use_cache(manifest, config_hash, source_fingerprint, config.index_dir) {
    Some(report) => {
      write_output(config.output, render_output(report, config.format))
      return
    }
    None => ()
  }
  let candidate_build = build_candidates(
    code_units, doc_fragments, config, registry,
  )
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
  let manifest_to_save = {
    ..sync_result.manifest,
    version: "reconcile-v1",
    updated_at: generated_at,
    config_hash,
    source_fingerprint,
    report_path: report_cache_path(config.index_dir),
    files: {
      let map : Map[String, FileState] = {}
      for state in all_file_states {
        map.set(state.path, state)
      }
      map
    },
  }
  let report = {
    version: "reconcile-v1",
    generated_at,
    config: report_config(config),
    summary: build_summary(
      code_units,
      doc_fragments,
      sync_result.candidates,
      aggregate_suggestions,
      candidate_build.module_covered_symbols,
      sync_result.logical_reviews,
      sync_result.reused_logical_reviews,
    ),
    aggregate_suggestions,
    candidates: sync_result.candidates,
    logical_reviews: sync_result.logical_reviews,
    skipped: [],
    used_specs: sort_strings(used_specs),
    cache_state: {
      cache_hit: false,
      source_fingerprint,
      review_state_hash: manifest_to_save.review_state_hash,
      reused_candidates: sync_result.reused_candidates,
      reused_logical_reviews: sync_result.reused_logical_reviews,
    },
  }
  save_cached_report(config.index_dir, report)
  save_manifest(config.index_dir, manifest_to_save)
  save_record_db(config.index_dir, sync_result.db)
  cleanup_stale_index(config.index_dir)
  write_output(config.output, render_output(report, config.format))
}
