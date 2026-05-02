/// Render a `StoryWikiPlan` for human or machine consumption.
///
/// JSON serialisation is delegated to `derive(ToJson)` and the standard
/// library's `Json::stringify(indent=2)`.

///|
pub enum PlanFormat {
  Text
  Markdown
  Json
} derive(Eq, Show)

///|
pub fn PlanFormat::parse(s : String) -> PlanFormat {
  match s {
    "json" => Json
    "md" => Markdown
    "markdown" => Markdown
    _ => Text
  }
}

///|
pub fn render_plan(plan : StoryWikiPlan, format : PlanFormat) -> String {
  match format {
    Text => render_text(plan)
    Markdown => render_markdown(plan)
    Json => plan.to_json().stringify(indent=2) + "\n"
  }
}

///|
fn render_text(plan : StoryWikiPlan) -> String {
  let buf = StringBuilder::new()
  buf.write_string("=== indexion story wiki plan ===\n")
  buf.write_string(
    "Pages proposed: " +
    plan.proposals.length().to_string() +
    " (from " +
    plan.source_doc_count.to_string() +
    " spec doc(s))\n",
  )
  buf.write_string("\n")
  if plan.proposals.is_empty() {
    buf.write_string("(no pages to propose)\n")
    return buf.to_string()
  }
  for p in plan.proposals {
    buf.write_string("  " + p.id + " — " + p.title + "\n")
    buf.write_string("    sources: ")
    for i, s in p.sources {
      if i > 0 {
        buf.write_string(", ")
      }
      buf.write_string(s)
    }
    buf.write_string("\n")
  }
  buf.to_string()
}

///|
fn render_markdown(plan : StoryWikiPlan) -> String {
  let buf = StringBuilder::new()
  buf.write_string("# Story Wiki Plan\n\n")
  buf.write_string(
    "**" +
    plan.proposals.length().to_string() +
    " page(s)** proposed from " +
    plan.source_doc_count.to_string() +
    " spec document(s).\n\n",
  )
  if plan.proposals.is_empty() {
    buf.write_string("_No pages to propose._\n")
    return buf.to_string()
  }
  buf.write_string("## Pages\n\n")
  for p in plan.proposals {
    buf.write_string("- **" + p.title + "** (`" + p.id + "`) — sources: ")
    for i, s in p.sources {
      if i > 0 {
        buf.write_string(", ")
      }
      buf.write_string("`")
      buf.write_string(s)
      buf.write_string("`")
    }
    buf.write_string("\n")
  }
  buf.write_string("\n")
  buf.to_string()
}
