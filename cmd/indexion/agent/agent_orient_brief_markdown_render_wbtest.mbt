///|
fn orient_render_fixture_report() -> @agent_orient.AgentOrientReport {
  {
    version: "agent-orient-vcdb-v1",
    task: "compose orient brief from vcdb query",
    likely_owners: [
      {
        path: "src/agent/orient/map",
        reason: "owns vcdb cache lifecycle",
      },
    ],
    knowledge_sources: [
      {
        path: "docs/orient-vcdb-migration.md",
        reason: "describes the migration plan",
      },
    ],
    consumer_surfaces: [
      {
        path: "packages/editor/src/orient-panel.mbt",
        reason: "renders the orient brief",
      },
    ],
    do_not_implement_here: [
      {
        path: "cmd/indexion/agent/agent_orient_cli.mbt",
        reason: "CLI entry only renders",
      },
    ],
    required_preflight: [
      {
        path: "src/agent/orient/source",
        reason: "discovers file briefs",
      },
    ],
    readiness_quiz: [
      {
        question: "Where is the orient cache schema defined?",
        expected_answer: "src/agent/orient/map/orient_cache_schema.mbt",
        evidence_path: "src/agent/orient/map/orient_cache_schema.mbt",
      },
    ],
    map_status: {
      total_files: 4,
      total_owners: 2,
      total_doc_sources: 1,
      changed_files: ["src/agent/orient/map/orient_cache_store.mbt"],
      new_files: [],
      deleted_files: [],
      knowledge_changed: false,
      refreshed_owners: ["src/agent/orient/map"],
      reused_owners: ["src/agent/orient/source"],
    },
    evidence: [
      {
        path: "src/agent/orient/map/orient_cache_query.mbt",
        kind: "implementation",
        score: 0.82,
        matched_terms: ["vector", "filter"],
        summary: "vector similarity query service with role filters",
      },
    ],
    workflow: ["1. read briefing", "2. edit owner", "3. run tests"],
    notes: ["bounded preview only"],
  }
}

///|
fn orient_render_section_order() -> Array[String] {
  [
    "## Task",
    "## Likely Implementation Owners",
    "## Knowledge Sources",
    "## Consumer Surfaces",
    "## Do Not Implement Here",
    "## Required Preflight",
    "## Readiness Quiz",
    "## Orientation Map",
    "## Evidence",
    "## Workflow",
    "## Notes",
  ]
}

///|
fn find_substring_index(haystack : String, needle : String) -> Int {
  let n_len = needle.length()
  let h_len = haystack.length()
  if n_len == 0 {
    return 0
  }
  if n_len > h_len {
    return -1
  }
  let limit = h_len - n_len
  for start in 0..=limit {
    let mut matched = true
    for offset in 0..<n_len {
      if haystack.unsafe_get(start + offset) != needle.unsafe_get(offset) {
        matched = false
        break
      }
    }
    if matched {
      return start
    }
  }
  -1
}

///|
test "agent orient markdown render: section headings appear in stable order" {
  let report = orient_render_fixture_report()
  let rendered = render_markdown(report)
  assert_true(rendered.has_prefix("# Agent Orientation Brief\n"))
  let mut last_index = 0
  for heading in orient_render_section_order() {
    let found = find_substring_index(rendered, heading)
    assert_true(found >= last_index)
    last_index = found
  }
}

///|
test "agent orient markdown render: empty sections still emit headings" {
  let empty : @agent_orient.AgentOrientReport = {
    version: "agent-orient-vcdb-v1",
    task: "",
    likely_owners: [],
    knowledge_sources: [],
    consumer_surfaces: [],
    do_not_implement_here: [],
    required_preflight: [],
    readiness_quiz: [],
    map_status: {
      total_files: 0,
      total_owners: 0,
      total_doc_sources: 0,
      changed_files: [],
      new_files: [],
      deleted_files: [],
      knowledge_changed: false,
      refreshed_owners: [],
      reused_owners: [],
    },
    evidence: [],
    workflow: [],
    notes: [],
  }
  let rendered = render_markdown(empty)
  for heading in [
    "## Likely Implementation Owners",
    "## Knowledge Sources",
    "## Consumer Surfaces",
    "## Do Not Implement Here",
    "## Required Preflight",
    "## Readiness Quiz",
    "## Orientation Map",
    "## Evidence",
    "## Workflow",
    "## Notes",
  ] {
    assert_true(find_substring_index(rendered, heading) >= 0)
  }
}

///|
test "agent orient json render: preserves top-level field names" {
  let report = orient_render_fixture_report()
  let payload = report.to_json().stringify(indent=2)
  for field in [
    "\"version\":",
    "\"task\":",
    "\"likely_owners\":",
    "\"knowledge_sources\":",
    "\"consumer_surfaces\":",
    "\"do_not_implement_here\":",
    "\"required_preflight\":",
    "\"readiness_quiz\":",
    "\"map_status\":",
    "\"evidence\":",
    "\"workflow\":",
    "\"notes\":",
  ] {
    assert_true(find_substring_index(payload, field) >= 0)
  }
}
