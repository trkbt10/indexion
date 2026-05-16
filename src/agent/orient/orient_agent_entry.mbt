///|
let orient_entry_vector_dim : Int = 256

///|
/// Entry point for building an agent orientation report from the vcdb-backed
/// cache. Update mode owns the writer lock; read-only mode never mutates.
pub async fn orient_agent(config : AgentOrientConfig) -> AgentOrientReport {
  if config.no_update {
    orient_agent_read_only(config)
  } else {
    orient_agent_update(config)
  }
}

///|
async fn orient_agent_update(config : AgentOrientConfig) -> AgentOrientReport {
  let lock = @cache.try_acquire_writer_lock(config)
  let report = orient_agent_update_locked(config) catch {
    err => {
      lock.release()
      raise err
    }
  }
  lock.release()
  report
}

///|
async fn orient_agent_update_locked(
  config : AgentOrientConfig,
) -> AgentOrientReport {
  let total_start = @progress.now_ms()
  log_progress(config, "[orient] starting update", "", 0UL)

  // Stage: load KGF registry.
  let t = @progress.now_ms()
  let registry = @kgf_features.load_registry_or_empty(
    specs_dir=config.specs_dir,
    target_dirs=config.paths,
  )
  log_progress(config, "[orient] load registry", "", @progress.elapsed_ms(t))

  // Open the vcdb with a lazy bootstrap thunk. On a cold cache the thunk has
  // to walk the filesystem and build the corpus from scratch — we capture
  // its briefs into the Ref so the main flow below can reuse them instead of
  // recomputing the same load+graph+brief pass after the cache is open.
  let bootstrap_briefs : Ref[Array[@types.LocalFileBrief]?] = Ref(None)
  let t = @progress.now_ms()
  let handle = @cache.open_for_update_lazy(
    config,
    fn() {
      log_progress(config, "[orient] cold-cache vocabulary bootstrap", "", 0UL)
      let opts = orient_entry_discover_options(config, registry)
      let sigs = @signature.discover_signatures(config.paths, opts, registry)
      let files = @signature.load_contents(sigs, registry)
      let graph = @source.build_graph(files, registry)
      let briefs = @source.build_file_briefs(files, graph, None)
      bootstrap_briefs.val = Some(orient_entry_stamp_signatures(briefs, sigs))
      orient_entry_corpus_texts(briefs)
    },
    orient_entry_vector_dim,
  )
  log_progress(config, "[orient] open cache", "", @progress.elapsed_ms(t))

  // Cold-cache fast path: the bootstrap thunk already paid the full
  // load+graph+briefs cost while building the TF-IDF corpus. Reuse those
  // briefs directly — running the warm-path classify pipeline would just
  // redo the same work.
  match bootstrap_briefs.val {
    Some(briefs) =>
      return orient_entry_finalize(
        config,
        handle,
        briefs,
        [],
        total_start,
        "cold build",
      )
    None => ()
  }

  // Warm path. Project the cached vcdb entries into the signature view used
  // for classification.
  let t = @progress.now_ms()
  let cached_files = @cache.scan_all_cached_files(handle)
  let cached_signature_by_path : Map[String, @signature.FileSignature] = {}
  let cached_by_path : Map[String, @cache.CachedFile] = {}
  for cached in cached_files {
    cached_by_path.set(cached.path, cached)
    cached_signature_by_path.set(cached.path, {
      path: cached.path,
      mtime_ns: cached.mtime_ns,
      size_bytes: cached.size_bytes,
    })
  }
  log_progress(
    config,
    "[orient] scan cache",
    "cached=" + cached_files.length().to_string(),
    @progress.elapsed_ms(t),
  )

  // Stage: stat the file set we need to verify. Two modes:
  //   1) Fast path (default): stat only the paths the cache already knows
  //      about. ~stat-per-file syscall cost vs. a recursive directory walk,
  //      which on a 1900-file monorepo is the difference between <1s and
  //      ~10s. New files on disk are *not* discovered here.
  //   2) Rescan (`--rescan` or `config.rescan=true`): full FS walk so newly
  //      created files enter the orient brief.
  let t = @progress.now_ms()
  let fresh_signatures = if config.rescan || cached_files.length() == 0 {
    let opts = orient_entry_discover_options(config, registry)
    @signature.discover_signatures(config.paths, opts, registry)
  } else {
    let paths : Array[String] = []
    for cached in cached_files {
      paths.push(cached.path)
    }
    @signature.signatures_for_paths(paths)
  }
  log_progress(
    config,
    if config.rescan || cached_files.length() == 0 {
      "[orient] discover signatures (walk)"
    } else {
      "[orient] discover signatures (cached paths)"
    },
    "files=" + fresh_signatures.length().to_string(),
    @progress.elapsed_ms(t),
  )

  // Classify against the cached signatures. `unchanged` files require zero
  // work; `candidates` may need a content re-read and a possible rebuild.
  let t = @progress.now_ms()
  let classification = @signature.classify_against_cache(
    fresh_signatures, cached_signature_by_path,
  )
  log_progress(
    config,
    "[orient] classify signatures",
    "unchanged=" +
    classification.unchanged.length().to_string() +
    " candidates=" +
    classification.candidates.length().to_string() +
    " deleted=" +
    classification.deleted_paths.length().to_string(),
    @progress.elapsed_ms(t),
  )

  // Load content for candidates and recompute their hashes.
  let t = @progress.now_ms()
  let candidate_files = @signature.load_contents(
    classification.candidates,
    registry,
  )
  let candidate_files_by_path : Map[String, @pipeline.SupportedFile] = {}
  let candidate_hashes : Map[String, String] = {}
  let mut content_changed = 0
  for file in candidate_files {
    candidate_files_by_path.set(file.path, file)
    let hash = @cas_hash.compute_hash(file.content).to_string()
    candidate_hashes.set(file.path, hash)
    match cached_by_path.get(file.path) {
      Some(cached) if cached.source_hash == hash => ()
      _ => content_changed = content_changed + 1
    }
  }
  log_progress(
    config,
    "[orient] read candidates",
    "loaded=" +
    candidate_files.length().to_string() +
    " content-changed=" +
    content_changed.to_string(),
    @progress.elapsed_ms(t),
  )

  // Build the per-file brief list.
  let needs_graph = content_changed > 0
  let signatures_by_fresh_path : Map[String, @signature.FileSignature] = {}
  for sig in fresh_signatures {
    signatures_by_fresh_path.set(sig.path, sig)
  }
  let rebuild_files : Array[@pipeline.SupportedFile] = []
  for sig in classification.candidates {
    match candidate_files_by_path.get(sig.path) {
      Some(file) => {
        let hash = candidate_hashes.get(sig.path).unwrap_or("")
        let cached_hash = match cached_by_path.get(sig.path) {
          Some(cached) => cached.source_hash
          None => ""
        }
        if hash != cached_hash {
          rebuild_files.push(file)
        }
      }
      None => () // file vanished between signature walk and content load
    }
  }
  let t = @progress.now_ms()
  let rebuild_briefs : Array[@types.LocalFileBrief] = if needs_graph {
    let graph = @source.build_graph(rebuild_files, registry)
    log_progress(
      config,
      "[orient] build code graph",
      "rebuild=" + rebuild_files.length().to_string(),
      @progress.elapsed_ms(t),
    )
    @source.build_file_briefs(rebuild_files, graph, None)
  } else {
    []
  }
  let new_briefs : Array[@types.LocalFileBrief] = []
  let mut refreshed_only = 0
  let mut reused_pure = 0
  let mut rebuilt = 0
  let rebuilt_by_path : Map[String, @types.LocalFileBrief] = {}
  for brief in rebuild_briefs {
    let fresh_sig = signatures_by_fresh_path.get(brief.path)
    let mtime_ns = match fresh_sig {
      Some(sig) => sig.mtime_ns
      None => 0L
    }
    let size_bytes = match fresh_sig {
      Some(sig) => sig.size_bytes
      None => 0L
    }
    rebuilt_by_path.set(brief.path, { ..brief, mtime_ns, size_bytes })
  }
  for sig in fresh_signatures {
    match rebuilt_by_path.get(sig.path) {
      Some(updated) => {
        rebuilt = rebuilt + 1
        new_briefs.push(updated)
        continue
      }
      None => ()
    }
    match cached_by_path.get(sig.path) {
      Some(cached) => {
        let candidate_hash = candidate_hashes.get(sig.path)
        let cached_signature_matches = cached.mtime_ns == sig.mtime_ns &&
          cached.size_bytes == sig.size_bytes
        if cached_signature_matches {
          reused_pure = reused_pure + 1
        } else {
          refreshed_only = refreshed_only + 1
        }
        let summary = match cached.summary_full {
          Some(full) => full
          None => cached.summary_preview
        }
        let source_hash_to_keep = match candidate_hash {
          Some(hash) => hash
          None => cached.source_hash
        }
        new_briefs.push(
          @source.cached_local_file_brief(
            cached.path,
            source_hash_to_keep,
            cached.structural_summary,
            summary,
            cached.role,
            mtime_ns=sig.mtime_ns,
            size_bytes=sig.size_bytes,
          ),
        )
      }
      None => () // brand-new file whose content failed to load — skip
    }
  }
  log_progress(
    config,
    "[orient] build briefs",
    "rebuilt=" +
    rebuilt.to_string() +
    " refreshed-meta=" +
    refreshed_only.to_string() +
    " reused=" +
    reused_pure.to_string(),
    @progress.elapsed_ms(t),
  )

  orient_entry_finalize(
    config, handle, new_briefs, cached_files, total_start, "warm",
  )
}

///|
/// Apply incremental updates, query, and emit the report. Shared between the
/// cold-cache bootstrap and the warm signature path.
async fn orient_entry_finalize(
  config : AgentOrientConfig,
  handle : @cache.Handle,
  briefs : Array[@types.LocalFileBrief],
  cached_snapshot : Array[@cache.CachedFile],
  total_start : UInt64,
  label : String,
) -> AgentOrientReport {
  let t = @progress.now_ms()
  let cache_snapshot : Array[@cache.CachedFile]? = if cached_snapshot.length() ==
    0 {
    None
  } else {
    Some(cached_snapshot)
  }
  let update = @cache.apply_incremental_updates_with_cache(
    handle, briefs, cache_snapshot,
  )
  log_progress(
    config,
    "[orient] apply updates",
    "upsert=" +
    update.upsert_count.to_string() +
    " remove=" +
    update.remove_count.to_string(),
    @progress.elapsed_ms(t),
  )
  let t = @progress.now_ms()
  let query = @cache.query(handle, config.task, config.limit)
  log_progress(config, "[orient] query", "", @progress.elapsed_ms(t))
  log_progress(
    config,
    "[orient] done (" + label + ")",
    "",
    @progress.elapsed_ms(total_start),
  )
  @report.orient_report_from_query(config, query, update.status)
}

///|
async fn orient_agent_read_only(
  config : AgentOrientConfig,
) -> AgentOrientReport {
  let provider = match
    @cache.load_or_build_provider(config, None, orient_entry_vector_dim) {
    @cache.VocabularyLoaded(provider) => provider
    @cache.VocabularyBuilt(_) =>
      raise @cache.Unavailable(
        "orient vcdb TF-IDF vocabulary rebuild is disabled in read-only mode",
      )
    @cache.VocabularyInvalid(_) =>
      raise @cache.Unavailable(
        "orient vcdb cache is unavailable in read-only mode",
      )
  }
  let handle = @cache.open(config, @cache.ReadOnly, provider)
  let status = @cache.current_status(handle)
  let query = @cache.query(handle, config.task, config.limit)
  @report.orient_report_from_query(config, query, status)
}

///|
fn orient_entry_discover_options(
  config : AgentOrientConfig,
  registry : @kgf_registry.KGFRegistry,
) -> @pipeline.DiscoverOptions {
  @pipeline.DiscoverOptions::new(
    root_dir=@pipeline.root_dir_from_paths(config.paths),
    recursive=true,
    kgf_ignore=registry.collect_ignore_patterns(),
  )
}

///|
fn orient_entry_corpus_texts(
  briefs : Array[@types.LocalFileBrief],
) -> Array[String] {
  let texts : Array[String] = []
  for brief in briefs {
    texts.push(brief.structural_summary + "\n" + brief.summary)
  }
  if texts.length() == 0 {
    texts.push("agent orient empty cache")
  }
  texts
}

///|
/// Splice freshly discovered signatures (mtime_ns / size_bytes) into the
/// briefs produced by the cold-cache bootstrap, so the records persisted
/// into vcdb already carry the file signature that the next run can match.
fn orient_entry_stamp_signatures(
  briefs : Array[@types.LocalFileBrief],
  signatures : Array[@signature.FileSignature],
) -> Array[@types.LocalFileBrief] {
  let sig_by_path : Map[String, @signature.FileSignature] = {}
  for sig in signatures {
    sig_by_path.set(sig.path, sig)
  }
  let stamped : Array[@types.LocalFileBrief] = []
  for brief in briefs {
    match sig_by_path.get(brief.path) {
      Some(sig) =>
        stamped.push({
          ..brief,
          mtime_ns: sig.mtime_ns,
          size_bytes: sig.size_bytes,
        })
      None => stamped.push(brief)
    }
  }
  stamped
}

///|
fn log_progress(
  config : AgentOrientConfig,
  stage : String,
  detail : String,
  elapsed_ms : UInt64,
) -> Unit {
  if config.quiet {
    return
  }
  @progress.stage(stage, detail, elapsed_ms)
}
