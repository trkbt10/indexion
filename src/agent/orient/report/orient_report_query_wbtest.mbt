///|
fn orient_query_report_status() -> @types.AgentOrientMapStatus {
  {
    total_files: 6,
    total_owners: 2,
    total_doc_sources: 1,
    changed_files: ["src/agent/orient/report/orient_report_compose.mbt"],
    new_files: [],
    deleted_files: [],
    knowledge_changed: true,
    refreshed_owners: ["src/agent/orient/report"],
    reused_owners: ["src/agent/orient/map"],
  }
}

///|
fn orient_query_report_fixture() -> @map.OrientQueryResult {
  {
    task: "wire query report adapter",
    query_dim: 16,
    owner_candidates: [
      {
        path: "src/agent/orient/report",
        score: 0.91,
        implementation_paths: [
          "src/agent/orient/report/orient_report_compose.mbt",
        ],
        top_implementation_path: "src/agent/orient/report/orient_report_compose.mbt",
        summary_preview: "report adapter composes orient query candidates",
      },
      {
        path: "src/agent/orient/map",
        score: 0.52,
        implementation_paths: ["src/agent/orient/map/orient_cache_query.mbt"],
        top_implementation_path: "src/agent/orient/map/orient_cache_query.mbt",
        summary_preview: "query service returns report-ready candidates",
      },
    ],
    implementation_hits: [
      {
        path: "src/agent/orient/report/orient_report_compose.mbt",
        role: "implementation",
        owner: "src/agent/orient/report",
        score: 0.91,
        summary_preview: "report adapter composes orient query candidates",
      },
    ],
    consumer_candidates: [
      {
        path: "packages/editor/src/orient-panel.mbt",
        role: "consumer",
        owner: "packages/editor/src",
        score: 0.61,
        summary_preview: "consumer surface calls orient query report output",
      },
    ],
    cli_consumers: [
      {
        path: "cmd/indexion/agent/orient_cli.mbt",
        role: "cli-consumer",
        owner: "cmd/indexion/agent",
        score: 0.57,
        summary_preview: "command line consumer renders orient report sections",
      },
    ],
    documentation_sources: [
      {
        path: "docs/orient-query.md",
        role: "documentation",
        owner: "docs",
        score: 0.73,
        summary_preview: "documentation source for orient query migration",
        summary_full: Some(
          "VECTOR_ID_SHOULD_NOT_LEAK source_hash SHOULD_NOT_LEAK attrs should stay private",
        ),
      },
    ],
    forbidden_surfaces: [
      {
        path: "cmd/indexion/agent/orient_cli.mbt",
        role: "cli-consumer",
        owner: "cmd/indexion/agent",
        score: 0.57,
        summary_preview: "command line consumer renders orient report sections",
      },
    ],
    preflight_candidates: [
      {
        path: "src/agent/orient/report/orient_report_compose.mbt",
        role: "implementation",
        owner: "src/agent/orient/report",
        score: 0.91,
        summary_preview: "read before editing the report adapter",
      },
      {
        path: "docs/orient-query.md",
        role: "documentation",
        owner: "docs",
        score: 0.73,
        summary_preview: "read query migration design before editing",
      },
    ],
    evidence_candidates: [
      {
        path: "src/agent/orient/report/orient_report_compose.mbt",
        role: "implementation",
        score: 0.91,
        summary: "report adapter composes orient query candidates into public fields",
      },
      {
        path: "docs/orient-query.md",
        role: "documentation",
        score: 0.73,
        summary: "documentation source for orient query migration",
      },
    ],
  }
}

///|
test "orient report query adapter: populates existing report sections" {
  let config = {
    ..AgentOrientConfig::default(),
    task: "wire query report adapter",
    limit: 3,
  }
  let status = orient_query_report_status()
  let report = orient_report_from_query(
    config,
    orient_query_report_fixture(),
    status,
  )
  assert_eq(report.version, "agent-orient-v1")
  assert_eq(report.task, config.task)
  assert_true(report.map_status == status)
  assert_eq(report.workflow, orientation_workflow())
  assert_eq(report.notes, orientation_notes())
  assert_eq(report.likely_owners.length(), 2)
  assert_eq(report.likely_owners[0].path, "src/agent/orient/report")
  assert_eq(report.knowledge_sources.length(), 1)
  assert_eq(report.knowledge_sources[0].path, "docs/orient-query.md")
  assert_true(
    item_path_exists(
      report.consumer_surfaces,
      "packages/editor/src/orient-panel.mbt",
    ),
  )
  assert_true(
    item_path_exists(
      report.consumer_surfaces,
      "cmd/indexion/agent/orient_cli.mbt",
    ),
  )
  assert_eq(report.do_not_implement_here.length(), 1)
  assert_eq(
    report.do_not_implement_here[0].path,
    "cmd/indexion/agent/orient_cli.mbt",
  )
  assert_eq(report.required_preflight.length(), 2)
  assert_eq(
    report.required_preflight[0].path,
    "src/agent/orient/report/orient_report_compose.mbt",
  )
  assert_eq(report.readiness_quiz.length(), 4)
  assert_eq(report.readiness_quiz[0].expected_answer, "src/agent/orient/report")
  assert_eq(report.readiness_quiz[1].expected_answer, "docs/orient-query.md")
}

///|
test "orient report query adapter: bounds evidence and hides storage attrs" {
  let config = {
    ..AgentOrientConfig::default(),
    task: "wire query report adapter",
    limit: 3,
  }
  let long_summary = "query result evidence preview 0123456789 abcdefghijklmnopqrstuvwxyz " +
    "0123456789 abcdefghijklmnopqrstuvwxyz 0123456789 abcdefghijklmnopqrstuvwxyz " +
    "0123456789 abcdefghijklmnopqrstuvwxyz 0123456789 abcdefghijklmnopqrstuvwxyz " +
    "0123456789 abcdefghijklmnopqrstuvwxyz"
  let query = {
    ..orient_query_report_fixture(),
    evidence_candidates: [
      {
        path: "src/agent/orient/report/orient_report_compose.mbt",
        role: "implementation",
        score: 0.91,
        summary: long_summary,
      },
    ],
  }
  let report = orient_report_from_query(
    config,
    query,
    orient_query_report_status(),
  )
  assert_eq(report.evidence.length(), 1)
  assert_true(report.evidence[0].summary.length() <= 223)
  assert_true(report.evidence[0].summary.has_suffix("..."))
  assert_false(report_text_contains(report, "VECTOR_ID_SHOULD_NOT_LEAK"))
  assert_false(report_text_contains(report, "SHOULD_NOT_LEAK"))
}

///|
test "orient report query adapter: non-positive limit remains unbounded" {
  let config = {
    ..AgentOrientConfig::default(),
    task: "wire query report adapter",
    limit: 0,
  }
  let report = orient_report_from_query(
    config,
    orient_query_report_fixture(),
    orient_query_report_status(),
  )
  assert_eq(report.likely_owners.length(), 2)
  assert_eq(report.consumer_surfaces.length(), 2)
  assert_eq(report.required_preflight.length(), 2)
  assert_eq(report.evidence.length(), 2)
}

///|
fn item_path_exists(items : Array[AgentOrientItem], path : String) -> Bool {
  for item in items {
    if item.path == path {
      return true
    }
  }
  false
}

///|
fn report_text_contains(report : AgentOrientReport, needle : String) -> Bool {
  if report.task.contains(needle) {
    return true
  }
  for item in report.likely_owners {
    if item.path.contains(needle) || item.reason.contains(needle) {
      return true
    }
  }
  for item in report.knowledge_sources {
    if item.path.contains(needle) || item.reason.contains(needle) {
      return true
    }
  }
  for item in report.consumer_surfaces {
    if item.path.contains(needle) || item.reason.contains(needle) {
      return true
    }
  }
  for item in report.do_not_implement_here {
    if item.path.contains(needle) || item.reason.contains(needle) {
      return true
    }
  }
  for item in report.required_preflight {
    if item.path.contains(needle) || item.reason.contains(needle) {
      return true
    }
  }
  for item in report.readiness_quiz {
    if item.question.contains(needle) ||
      item.expected_answer.contains(needle) ||
      item.evidence_path.contains(needle) {
      return true
    }
  }
  for item in report.evidence {
    if item.path.contains(needle) ||
      item.kind.contains(needle) ||
      item.summary.contains(needle) {
      return true
    }
    for term in item.matched_terms {
      if term.contains(needle) {
        return true
      }
    }
  }
  for item in report.workflow {
    if item.contains(needle) {
      return true
    }
  }
  for item in report.notes {
    if item.contains(needle) {
      return true
    }
  }
  false
}
