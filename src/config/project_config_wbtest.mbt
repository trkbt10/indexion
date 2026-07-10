///|
test "project_config: default has inherit_global true" {
  let config = ProjectFileConfig::default()
  assert_true(config.inherit_global)
}

///|
test "project_config: parse_project_toml_config parses inherit false" {
  let input =
    #|[indexion]
    #|inherit = false
    #|
    #|[reconcile]
    #|threshold_seconds = 120
  let config = parse_project_toml_config(input)
  assert_false(config.inherit_global)
  assert_eq(config.reconcile.threshold_seconds, Some(120))
}

///|
test "project_config: parse_project_toml_config defaults inherit_global to true" {
  let input =
    #|[reconcile]
    #|threshold_seconds = 60
  let config = parse_project_toml_config(input)
  assert_true(config.inherit_global)
  assert_eq(config.reconcile.threshold_seconds, Some(60))
}

///|
test "project_config: parse_project_json_config parses inherit" {
  let input =
    #|{
    #|  "indexion": { "inherit": false },
    #|  "reconcile": { "threshold_seconds": 90 }
    #|}
  let config = parse_project_json_config(input)
  assert_false(config.inherit_global)
  assert_eq(config.reconcile.threshold_seconds, Some(90))
}

///|
test "project_config: merge_global_into_file prefers file over global" {
  let file : ReconcileFileConfig = {
    ..ReconcileFileConfig::empty(),
    threshold_seconds: Some(120),
  }
  let global : ReconcileFileConfig = {
    ..ReconcileFileConfig::empty(),
    threshold_seconds: Some(60),
    max_candidates: Some(100),
  }
  let merged = merge_global_into_file(file, global)
  assert_eq(merged.threshold_seconds, Some(120))
  assert_eq(merged.max_candidates, Some(100))
}

///|
test "project_config: merge_global_into_file fills from global when file is empty" {
  let file = ReconcileFileConfig::empty()
  let global : ReconcileFileConfig = {
    ..ReconcileFileConfig::empty(),
    threshold_seconds: Some(60),
    git_preferred: Some(true),
  }
  let merged = merge_global_into_file(file, global)
  assert_eq(merged.threshold_seconds, Some(60))
  assert_eq(merged.git_preferred, Some(true))
}

///|
test "project_config: build_effective_reconcile_config preserves provenance" {
  let project : ProjectFileConfig = {
    ..ProjectFileConfig::default(),
    inherit_global: true,
    reconcile: ReconcileFileConfig::empty(),
  }
  let global : GlobalConfig = {
    ..GlobalConfig::empty(),
    reconcile: {
      ..ReconcileFileConfig::empty(),
      index_dir: Some(".cache/reconcile"),
      threshold_seconds: Some(45),
    },
  }
  let effective = build_effective_reconcile_config(
    project,
    global,
    Some("/Users/demo/.config/indexion/config.toml"),
  )
  assert_eq(effective.merged.index_dir, Some(".cache/reconcile"))
  assert_eq(effective.merged.threshold_seconds, Some(45))
  assert_eq(effective.project.reconcile.index_dir, None)
  assert_eq(effective.global.reconcile.index_dir, Some(".cache/reconcile"))
  assert_eq(
    effective.global_config_path,
    Some("/Users/demo/.config/indexion/config.toml"),
  )
}

///|
test "project_config: build_effective_reconcile_config drops global when disabled" {
  let project : ProjectFileConfig = {
    ..ProjectFileConfig::default(),
    inherit_global: false,
    reconcile: { ..ReconcileFileConfig::empty(), threshold_seconds: Some(30) },
  }
  let global : GlobalConfig = {
    ..GlobalConfig::empty(),
    reconcile: { ..ReconcileFileConfig::empty(), threshold_seconds: Some(60) },
  }
  let effective = build_effective_reconcile_config(
    project,
    global,
    Some("/Users/demo/.config/indexion/config.toml"),
  )
  assert_eq(effective.merged.threshold_seconds, Some(30))
  assert_eq(effective.global, GlobalConfig::empty())
  assert_eq(effective.global_config_path, None)
}

///|
test "project_config: parse_project_toml_config parses digest section" {
  let input =
    #|[digest]
    #|provider = "openai"
    #|strategy = "hnsw"
    #|dim = 1536
    #|api_key_env = "MY_API_KEY"
    #|api_base_url = "https://example.com/v1/embeddings"
    #|model = "nomic-embed-text"
  let config = parse_project_toml_config(input)
  assert_eq(config.embedding.provider, Some("openai"))
  assert_eq(config.embedding.strategy, Some("hnsw"))
  assert_eq(config.embedding.dim, Some(1536))
  assert_eq(config.embedding.api_key_env, Some("MY_API_KEY"))
  assert_eq(
    config.embedding.api_base_url,
    Some("https://example.com/v1/embeddings"),
  )
  assert_eq(config.embedding.model, Some("nomic-embed-text"))
}

///|
test "project_config: parse_project_toml_config digest defaults to empty" {
  let input =
    #|[indexion]
    #|inherit = true
  let config = parse_project_toml_config(input)
  assert_eq(config.digest, DigestFileConfig::empty())
}

///|
test "project_config: parse_project_json_config parses digest section" {
  let input =
    #|{
    #|  "digest": {
    #|    "provider": "openai",
    #|    "strategy": "hnsw",
    #|    "dim": 1536,
    #|    "api_key_env": "MY_KEY"
    #|  }
    #|}
  let config = parse_project_json_config(input)
  assert_eq(config.embedding.provider, Some("openai"))
  assert_eq(config.embedding.strategy, Some("hnsw"))
  assert_eq(config.embedding.dim, Some(1536))
  assert_eq(config.embedding.api_key_env, Some("MY_KEY"))
}

///|
test "project_config: merge_embedding_configs primary takes precedence" {
  let primary : EmbeddingFileConfig = {
    ..EmbeddingFileConfig::empty(),
    provider: Some("openai"),
  }
  let fallback : EmbeddingFileConfig = {
    ..EmbeddingFileConfig::empty(),
    provider: Some("tfidf"),
    strategy: Some("ivf"),
  }
  let merged = merge_embedding_configs(primary, fallback)
  assert_eq(merged.provider, Some("openai"))
  assert_eq(merged.strategy, Some("ivf"))
}
