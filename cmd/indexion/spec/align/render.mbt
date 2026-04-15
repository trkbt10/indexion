///|
fn render_summary_block(
  buf : StringBuilder,
  summary : @spec_align.AlignSummary,
) -> Unit {
  buf.write_string("- Matched: ")
  buf.write_string(summary.matched.to_string())
  buf.write_string("\n- Drifted: ")
  buf.write_string(summary.drifted.to_string())
  buf.write_string("\n- Spec only: ")
  buf.write_string(summary.spec_only.to_string())
  buf.write_string("\n- Impl only: ")
  buf.write_string(summary.impl_only.to_string())
  buf.write_string("\n- Conflict: ")
  buf.write_string(summary.conflict.to_string())
  buf.write_string("\n- Shallow: ")
  buf.write_string(summary.shallow.to_string())
  buf.write_string("\n")
}

///|
fn sanitize_node_id(text : String) -> String {
  let buf = StringBuilder::new()
  for ch in text.to_array() {
    if (ch >= 'a' && ch <= 'z') ||
      (ch >= 'A' && ch <= 'Z') ||
      (ch >= '0' && ch <= '9') {
      buf.write_char(ch)
    } else {
      buf.write_char('_')
    }
  }
  buf.to_string()
}

///|
fn task_action(suggestion : @spec_align.AlignSuggestion) -> String {
  suggestion.task.unwrap_or(suggestion.summary)
}

///|
fn render_tasks_generic(report : @spec_align.AlignSuggestReport) -> String {
  let buf = StringBuilder::new()
  buf.write_string("# Spec Align Tasks\n\n")
  for suggestion in report.suggestions {
    buf.write_string("- ")
    buf.write_string(suggestion.title)
    buf.write_string(" [")
    buf.write_string(suggestion.direction)
    buf.write_string("]")
    match suggestion.task {
      Some(task) => {
        buf.write_string(" — ")
        buf.write_string(task)
      }
      None => ()
    }
    buf.write_string("\n")
  }
  buf.to_string()
}

///|
fn render_tasks_claude(report : @spec_align.AlignSuggestReport) -> String {
  let buf = StringBuilder::new()
  buf.write_string("# Claude Tasks\n\n")
  for i = 0; i < report.suggestions.length(); i = i + 1 {
    let suggestion = report.suggestions[i]
    buf.write_string("## Task ")
    buf.write_string((i + 1).to_string())
    buf.write_string(": ")
    buf.write_string(suggestion.title)
    buf.write_string("\n")
    buf.write_string("- Direction: ")
    buf.write_string(suggestion.direction)
    buf.write_string("\n")
    buf.write_string("- Action: ")
    buf.write_string(task_action(suggestion))
    buf.write_string("\n")
    match suggestion.spec_file {
      Some(path) => {
        buf.write_string("- Spec File: `")
        buf.write_string(path)
        buf.write_string("`\n")
      }
      None => ()
    }
    match suggestion.impl_file {
      Some(path) => {
        buf.write_string("- Implementation File: `")
        buf.write_string(path)
        buf.write_string("`\n")
      }
      None => ()
    }
    if suggestion.reasons.length() > 0 {
      buf.write_string("- Evidence: ")
      buf.write_string(suggestion.reasons.join(" "))
      buf.write_string("\n")
    }
    match suggestion.patch {
      Some(patch) => {
        buf.write_string("- Patch:\n\n")
        buf.write_string(patch)
        buf.write_string("\n")
      }
      None => ()
    }
    buf.write_string("\n")
  }
  buf.to_string()
}

///|
fn render_tasks_copilot(report : @spec_align.AlignSuggestReport) -> String {
  let buf = StringBuilder::new()
  buf.write_string("# Copilot Tasks\n\n")
  for suggestion in report.suggestions {
    buf.write_string("- [ ] ")
    buf.write_string(suggestion.title)
    buf.write_string("\n")
    buf.write_string("  direction: ")
    buf.write_string(suggestion.direction)
    buf.write_string("\n")
    buf.write_string("  action: ")
    buf.write_string(task_action(suggestion))
    buf.write_string("\n")
    if suggestion.reasons.length() > 0 {
      buf.write_string("  evidence: ")
      buf.write_string(suggestion.reasons.join(" "))
      buf.write_string("\n")
    }
    match suggestion.spec_file {
      Some(path) => {
        buf.write_string("  spec: ")
        buf.write_string(path)
        buf.write_string("\n")
      }
      None => ()
    }
    match suggestion.impl_file {
      Some(path) => {
        buf.write_string("  impl: ")
        buf.write_string(path)
        buf.write_string("\n")
      }
      None => ()
    }
  }
  buf.to_string()
}

///|
pub fn render_diff(
  report : @spec_align.AlignDiffReport,
  format : String,
) -> String {
  match format {
    "json" => report.to_json().stringify(indent=2)
    "summary" =>
      "matched=" +
      report.summary.matched.to_string() +
      " drifted=" +
      report.summary.drifted.to_string() +
      " spec_only=" +
      report.summary.spec_only.to_string() +
      " impl_only=" +
      report.summary.impl_only.to_string() +
      " conflict=" +
      report.summary.conflict.to_string()
    _ => {
      let buf = StringBuilder::new()
      buf.write_string("# Spec Align Diff Report\n\n")
      buf.write_string("- Spec: `")
      buf.write_string(report.config.spec_path)
      buf.write_string("`\n- Impl: `")
      buf.write_string(report.config.impl_path)
      buf.write_string("`\n")
      render_summary_block(buf, report.summary)
      buf.write_string("\n")
      for item in report.items {
        buf.write_string("## ")
        buf.write_string(item.category)
        buf.write_string(": ")
        buf.write_string(
          item.requirement_title.unwrap_or(
            item.implementation_name.unwrap_or("item"),
          ),
        )
        buf.write_string("\n\n")
        for reason in item.reasons {
          buf.write_string("- ")
          buf.write_string(reason)
          buf.write_string("\n")
        }
        buf.write_string("\n")
      }
      buf.to_string()
    }
  }
}

///|
pub fn render_trace(
  report : @spec_align.AlignTraceReport,
  format : String,
) -> String {
  match format {
    "yaml" => {
      let buf = StringBuilder::new()
      buf.write_string("requirements:\n")
      for requirement in report.requirements {
        buf.write_string("- id: ")
        buf.write_string(requirement.id)
        buf.write_string("\n  title: \"")
        buf.write_string(requirement.title)
        buf.write_string("\"\n")
      }
      buf.write_string("edges:\n")
      for edge in report.edges {
        buf.write_string("- requirement_id: ")
        buf.write_string(edge.requirement_id)
        buf.write_string("\n  implementation_id: ")
        buf.write_string(edge.implementation_id)
        buf.write_string("\n  confidence: ")
        buf.write_string(edge.confidence.to_string())
        buf.write_string("\n")
      }
      buf.to_string()
    }
    "mermaid" => {
      let buf = StringBuilder::new()
      buf.write_string("graph TD\n")
      for requirement in report.requirements {
        buf.write_string("  ")
        buf.write_string(sanitize_node_id(requirement.id))
        buf.write_string("[\"")
        buf.write_string(requirement.title)
        buf.write_string("\"]\n")
      }
      for implementation in report.implementations {
        buf.write_string("  ")
        buf.write_string(sanitize_node_id(implementation.id))
        buf.write_string("[\"")
        buf.write_string(implementation.name)
        buf.write_string("\"]\n")
      }
      for edge in report.edges {
        buf.write_string("  ")
        buf.write_string(sanitize_node_id(edge.requirement_id))
        buf.write_string(" -->|")
        buf.write_string(@common.format_percent(edge.confidence))
        buf.write_string("| ")
        buf.write_string(sanitize_node_id(edge.implementation_id))
        buf.write_string("\n")
      }
      buf.to_string()
    }
    _ => report.to_json().stringify(indent=2)
  }
}

///|
pub fn render_suggest(
  report : @spec_align.AlignSuggestReport,
  format : String,
) -> String {
  match format {
    "json" => report.to_json().stringify(indent=2)
    "tasks" =>
      match report.config.agent {
        "claude" => render_tasks_claude(report)
        "copilot" => render_tasks_copilot(report)
        _ => render_tasks_generic(report)
      }
    "delta-spec" => {
      let buf = StringBuilder::new()
      for suggestion in report.suggestions {
        if suggestion.direction != "impl-wins" {
          continue
        }
        match suggestion.patch {
          Some(patch) => {
            buf.write_string(patch)
            buf.write_string("\n\n")
          }
          None => ()
        }
      }
      if buf.to_string().length() == 0 {
        "No delta spec suggestions."
      } else {
        buf.to_string()
      }
    }
    _ => {
      let buf = StringBuilder::new()
      buf.write_string("# Spec Align Suggestions\n\n")
      render_summary_block(buf, report.summary)
      buf.write_string("\n")
      for suggestion in report.suggestions {
        buf.write_string("## ")
        buf.write_string(suggestion.direction)
        buf.write_string(": ")
        buf.write_string(suggestion.title)
        buf.write_string("\n\n")
        buf.write_string(suggestion.summary)
        buf.write_string("\n\n")
        for reason in suggestion.reasons {
          buf.write_string("- ")
          buf.write_string(reason)
          buf.write_string("\n")
        }
        match suggestion.patch {
          Some(patch) => {
            buf.write_string("\n")
            buf.write_string(patch)
            buf.write_string("\n")
          }
          None => ()
        }
        match suggestion.task {
          Some(task) => {
            buf.write_string("\n- Task: ")
            buf.write_string(task)
            buf.write_string("\n")
          }
          None => ()
        }
        buf.write_string("\n")
      }
      buf.to_string()
    }
  }
}

///|
pub fn render_status(
  report : @spec_align.AlignStatusReport,
  format : String,
) -> String {
  match format {
    "json" => report.to_json().stringify(indent=2)
    "badge" =>
      "spec-align|" +
      (if report.should_fail { "red" } else { "green" }) +
      "|matched:" +
      report.summary.matched.to_string() +
      " drifted:" +
      report.summary.drifted.to_string()
    _ => {
      let buf = StringBuilder::new()
      buf.write_string("status=")
      buf.write_string(report.status)
      buf.write_string(" fail_on=")
      buf.write_string(report.fail_on)
      buf.write_string("\n")
      render_summary_block(buf, report.summary)
      buf.to_string()
    }
  }
}
