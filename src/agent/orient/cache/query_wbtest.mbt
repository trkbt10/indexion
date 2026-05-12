///|
fn orient_query_test_config(name : String) -> AgentOrientConfig {
  {
    ..AgentOrientConfig::default(),
    cache_dir: "_build/orient-cache-query/" + name,
  }
}

///|
fn orient_query_test_provider() -> @text_embed.TfidfEmbeddingProvider {
  let provider = @text_embed.TfidfEmbeddingProvider::new(16)
  provider.build_vocabulary([
    "vector similarity query service role filters implementation owner", "orient cache query service implementation owner candidate",
    "consumer surface calls vector query service without json parsing", "command line consumer parses orient query flags",
    "documentation source explains vector query migration", "unrelated legacy implementation background",
  ])
  provider
}

///|
fn orient_query_test_brief(
  path : String,
  role : String,
  summary : String,
) -> LocalFileBrief {
  {
    path,
    role,
    source_hash: "hash-" + path,
    structural_summary: "structure for " + path,
    summary,
    structural_terms: [],
    summary_terms: [],
    score: 0.0,
    matched_terms: [],
  }
}

///|
async fn reset_orient_query_fixture(cache_dir : String) -> Unit {
  @async_fs.rmdir(cache_dir, recursive=true) catch {
    _ => ()
  }
}

///|
async fn orient_query_test_handle(name : String) -> Handle {
  let config = orient_query_test_config(name)
  reset_orient_query_fixture(config.cache_dir)
  let provider = orient_query_test_provider()
  let handle = rebuild_empty(config, provider)
  let long_doc = "# Orient query migration\n" +
    "Documentation source explains vector query migration role filters and report composition. " +
    "This full documentation field is allowed for documentation records."
  let long_evidence = "vector similarity query service role filters implementation owner " +
    "0123456789abcdefghijklmnopqrstuvwxyz 0123456789abcdefghijklmnopqrstuvwxyz " +
    "0123456789abcdefghijklmnopqrstuvwxyz 0123456789abcdefghijklmnopqrstuvwxyz " +
    "0123456789abcdefghijklmnopqrstuvwxyz 0123456789abcdefghijklmnopqrstuvwxyz"
  handle.upsert_many(
    [
      orient_query_test_brief(
        "src/agent/orient/cache/query.mbt", "implementation", long_evidence,
      ),
      orient_query_test_brief(
        "src/agent/orient/report/orient_report_compose.mbt", "implementation", "orient cache query service implementation owner candidate report adapter",
      ),
      orient_query_test_brief(
        "src/unrelated/legacy.mbt", "implementation", "unrelated legacy implementation background",
      ),
      orient_query_test_brief(
        "packages/editor/src/orient-panel.mbt", "consumer", "consumer surface calls vector query service without json parsing",
      ),
      orient_query_test_brief(
        "cmd/indexion/agent/orient_cli.mbt", "cli-consumer", "command line consumer parses orient query flags",
      ),
      orient_query_test_brief("docs/orient-query.md", "documentation", long_doc),
    ],
    timestamp_ns=100L,
  )
  handle
}

///|
test "orient cache query: role filter helper uses direct role attrs" {
  let brief = orient_query_test_brief(
    "packages/editor/src/orient-panel.mbt", "consumer", "consumer surface calls vector query service",
  )
  let attrs = attrs_from_brief(brief, preview_limit=64)
  let consumer_filter = query_role_filter("consumer")
  let implementation_filter = query_role_filter("implementation")
  assert_true(@vcdb_filter.eval_filter(consumer_filter, attrs))
  assert_false(@vcdb_filter.eval_filter(implementation_filter, attrs))
}

///|
async test "orient cache query: implementation filter drives owner aggregation" {
  let handle = orient_query_test_handle("implementation-owners")
  let result = query(
    handle, "build vector similarity query service role filters", 2,
  )
  assert_eq(result.query_dim, handle.provider().dim())
  assert_eq(result.implementation_hits.length(), 2)
  for hit in result.implementation_hits {
    assert_eq(hit.role, "implementation")
  }
  assert_eq(result.owner_candidates.length(), 2)
  assert_true(
    result.owner_candidates[0].implementation_paths.contains(
      "src/agent/orient/cache/query.mbt",
    ),
  )
  for owner in result.owner_candidates {
    assert_true(owner.path != "src/unrelated")
  }
}

///|
async test "orient cache query: consumer and cli role filters are visible" {
  let handle = orient_query_test_handle("consumer-filters")
  let result = query(
    handle, "wire consumer surface and command line orient query service", 4,
  )
  assert_eq(result.consumer_candidates.length(), 1)
  assert_eq(result.consumer_candidates[0].role, "consumer")
  assert_eq(
    result.consumer_candidates[0].path,
    "packages/editor/src/orient-panel.mbt",
  )
  assert_eq(result.cli_consumers.length(), 1)
  assert_eq(result.cli_consumers[0].role, "cli-consumer")
  assert_eq(result.forbidden_surfaces.length(), 1)
  assert_eq(
    result.forbidden_surfaces[0].path,
    "cmd/indexion/agent/orient_cli.mbt",
  )
}

///|
async test "orient cache query: documentation filter keeps preview and full doc" {
  let handle = orient_query_test_handle("documentation-filter")
  let result = query(
    handle, "read documentation source for orient query migration", 3,
  )
  assert_eq(result.documentation_sources.length(), 1)
  let doc = result.documentation_sources[0]
  assert_eq(doc.role, "documentation")
  assert_eq(doc.path, "docs/orient-query.md")
  assert_true(doc.summary_preview.length() <= summary_preview_limit)
  assert_true(doc.summary_full is Some(_))
}

///|
async test "orient cache query: evidence and preflight candidates are bounded" {
  let handle = orient_query_test_handle("bounded-evidence")
  let result = query(
    handle, "vector similarity query service role filters implementation owner",
    3,
  )
  assert_true(result.preflight_candidates.length() > 0)
  assert_true(result.preflight_candidates.length() <= 3)
  assert_true(result.evidence_candidates.length() > 0)
  assert_true(result.evidence_candidates.length() <= 3)
  for evidence in result.evidence_candidates {
    assert_true(
      evidence.summary.length() <= query_evidence_preview_limit + 3,
    )
  }
}
