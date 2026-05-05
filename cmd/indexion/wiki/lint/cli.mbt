///|
/// # indexion wiki lint
///
/// Check wiki structural integrity: broken links, orphan pages,
/// stale sources, missing cross-references, empty pages, manifest mismatches.

///|
pub fn command() -> @argparse.Command {
  @argparse.Command("lint", about="Check wiki structural integrity", options=[
    @argparse.OptionArg("wiki-dir", about="Wiki directory", default_values=[
      @wiki_workspace.DEFAULT_WIKI_DIR,
    ]),
    @argparse.OptionArg(
      "format",
      about="Output format: md, json, github-issue",
      default_values=["md"],
    ),
    @argparse.OptionArg("output", short='o', about="Output file path"),
    @argparse.OptionArg("specs-dir", about=@help.specs_dir, default_values=[
      "kgfs",
    ]),
  ])
}

///|
pub fn run_matches(matches : @argparse.Matches) -> Unit {
  let wiki_dir_resolved = match @wiki_cli_common.resolve_wiki_dir_arg(matches) {
    Some(dir) => dir
    None => {
      @wiki_cli_common.print_project_root_error()
      return
    }
  }
  let format = match matches.values.get("format") {
    Some(arr) => if arr.length() > 0 { arr[0] } else { "md" }
    _ => "md"
  }
  let output = match matches.values.get("output") {
    Some(arr) => if arr.length() > 0 { arr[0] } else { "" }
    _ => ""
  }
  let specs_dir = match matches.values.get("specs-dir") {
    Some(arr) => if arr.length() > 0 { arr[0] } else { "kgfs" }
    _ => "kgfs"
  }
  // Load wiki
  let registry = @kgf_features.load_registry(specs_dir~, target_dir=".")
  let wiki = match @wiki_reader.load_wiki(wiki_dir_resolved, registry~) {
    Some(w) => w
    None => {
      println("Error: No wiki found at " + wiki_dir_resolved)
      return
    }
  }
  // Run lint
  let report = @wiki_lint.lint(wiki, wiki_dir=wiki_dir_resolved)
  // Convert to plan document and render
  let doc = report.to_plan_document()
  let output_content = match format {
    "json" => doc.to_json().stringify(indent=2)
    "github-issue" => @plan_render.render_github_issue(doc).format()
    _ => @plan_render.render_markdown(doc)
  }
  @common.write_output(output, output_content, label="Wiki lint report")
  // Log the lint operation
  let log = @wiki_log.WikiLog::load(wiki_dir_resolved)
  let affected : Array[String] = []
  for issue in report.issues {
    if !affected.contains(issue.page_id) {
      affected.push(issue.page_id)
    }
  }
  log.append(
    @wiki_log.WikiLogEntry::new(
      timestamp=@env.now(),
      operation="lint",
      actor="indexion",
      summary=report.issues.length().to_string() +
        " issues found across " +
        report.total_pages.to_string() +
        " pages",
      affected_pages=affected,
    ),
  )
  log.save(wiki_dir_resolved)
}
