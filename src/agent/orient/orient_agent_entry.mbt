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
  let registry = @kgf_features.load_registry_or_empty(
    specs_dir=config.specs_dir,
    target_dirs=config.paths,
  )
  let files = @source.discover_files(config, registry)
  let graph = @source.build_graph(files, registry)
  let briefs = @source.build_file_briefs(files, graph, None)
  let handle = @cache.open_for_update(
    config,
    orient_entry_corpus_texts(briefs),
    orient_entry_vector_dim,
  )
  let update = @cache.apply_incremental_updates(handle, briefs)
  let query = @cache.query(handle, config.task, config.limit)
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
