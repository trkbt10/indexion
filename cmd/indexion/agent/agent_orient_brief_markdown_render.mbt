///|
/// Render an agent orientation brief as Markdown for human and subagent handoff.
fn render_markdown(report : @agent_orient.AgentOrientReport) -> String {
  let buf = StringBuilder()
  buf.write_string("# Agent Orientation Brief\n\n")
  if report.task.length() > 0 {
    buf.write_string("## Task\n\n")
    buf.write_string(report.task)
    buf.write_string("\n\n")
  }
  render_items(buf, "Likely Implementation Owners", report.likely_owners)
  render_items(buf, "Knowledge Sources", report.knowledge_sources)
  render_items(buf, "Consumer Surfaces", report.consumer_surfaces)
  render_items(buf, "Do Not Implement Here", report.do_not_implement_here)
  render_items(buf, "Required Preflight", report.required_preflight)
  render_quiz(buf, report.readiness_quiz)
  render_map_status(buf, report.map_status)
  render_evidence(buf, report.evidence)
  render_list(buf, "Workflow", report.workflow)
  render_list(buf, "Notes", report.notes)
  buf.to_string()
}

///|
fn render_items(
  buf : StringBuilder,
  title : String,
  items : Array[@agent_orient.AgentOrientItem],
) -> Unit {
  buf.write_string("## ")
  buf.write_string(title)
  buf.write_string("\n\n")
  if items.length() == 0 {
    buf.write_string("- None found.\n\n")
    return
  }
  for item in items {
    buf.write_string("- `")
    buf.write_string(item.path)
    buf.write_string("`: ")
    buf.write_string(item.reason)
    buf.write_string("\n")
  }
  buf.write_string("\n")
}

///|
fn render_quiz(
  buf : StringBuilder,
  quiz : Array[@agent_orient.AgentOrientQuizItem],
) -> Unit {
  buf.write_string("## Readiness Quiz\n\n")
  if quiz.length() == 0 {
    buf.write_string("- None found.\n\n")
    return
  }
  for item in quiz {
    buf.write_string("- ")
    buf.write_string(item.question)
    buf.write_string(" Expected: `")
    buf.write_string(item.expected_answer)
    buf.write_string("` Evidence: `")
    buf.write_string(item.evidence_path)
    buf.write_string("`\n")
  }
  buf.write_string("\n")
}

///|
fn render_map_status(
  buf : StringBuilder,
  status : @agent_orient.AgentOrientMapStatus,
) -> Unit {
  buf.write_string("## Orientation Map\n\n")
  buf.write_string("- Files: ")
  buf.write_string(status.total_files.to_string())
  buf.write_string("\n- Owners: ")
  buf.write_string(status.total_owners.to_string())
  buf.write_string("\n- Documentation sources: ")
  buf.write_string(status.total_doc_sources.to_string())
  buf.write_string("\n- Knowledge changed: ")
  buf.write_string(status.knowledge_changed.to_string())
  buf.write_string("\n- Refreshed owners: ")
  buf.write_string(status.refreshed_owners.length().to_string())
  buf.write_string("\n- Reused owners: ")
  buf.write_string(status.reused_owners.length().to_string())
  buf.write_string("\n\n")
}

///|
fn render_evidence(
  buf : StringBuilder,
  evidence : Array[@agent_orient.AgentOrientEvidence],
) -> Unit {
  buf.write_string("## Evidence\n\n")
  if evidence.length() == 0 {
    buf.write_string("- None found.\n\n")
    return
  }
  for item in evidence {
    buf.write_string("- `")
    buf.write_string(item.path)
    buf.write_string("` [")
    buf.write_string(item.kind)
    buf.write_string("] score=")
    buf.write_string(@common.format_percent(item.score))
    if item.matched_terms.length() > 0 {
      buf.write_string(" terms=`")
      buf.write_string(item.matched_terms.join("`, `"))
      buf.write_string("`")
    }
    buf.write_string("\n")
  }
  buf.write_string("\n")
}

///|
fn render_list(
  buf : StringBuilder,
  title : String,
  items : Array[String],
) -> Unit {
  buf.write_string("## ")
  buf.write_string(title)
  buf.write_string("\n\n")
  for item in items {
    buf.write_string("- ")
    buf.write_string(item)
    buf.write_string("\n")
  }
  buf.write_string("\n")
}
