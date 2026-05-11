///|
/// Entry point for building an agent orientation report from cached or freshly
/// scanned file briefs and owner maps.
pub async fn orient_agent(config : AgentOrientConfig) -> AgentOrientReport {
  let _runtime = @map.prepare_orient_cache_runtime(config)
  let cached_map = @map.load_cached_orient_map(config)
  let raw_task_terms = @matching.task_tokens(config.task)
  if config.no_update {
    match cached_map {
      Some(map) => {
        let orient_map = { ..map, status: @map.map_status_for_cached(map) }
        return @report.orient_report_from_map(
          config,
          raw_task_terms,
          @report.briefs_from_orient_map(orient_map),
          orient_map,
        )
      }
      None => ()
    }
  }
  let registry = @kgf_features.load_registry_or_empty(
    specs_dir=config.specs_dir,
    target_dirs=config.paths,
  )
  let files = @source.discover_files(config, registry)
  let graph = @source.build_graph(files, registry)
  let raw_briefs = @source.build_file_briefs(files, graph, cached_map)
  let orient_map = @map.build_or_update_orient_map(
    config, raw_briefs, cached_map,
  )
  if !config.no_update {
    @map.save_orient_map(config, orient_map)
  }
  @report.orient_report_from_map(config, raw_task_terms, raw_briefs, orient_map)
}
