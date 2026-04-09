///|
/// # indexion wiki ingest
///
/// Detect source file changes and generate update tasks for wiki pages.

///|
pub fn command() -> @argparse.Command {
  @argparse.Command(
    "ingest",
    about="Detect source changes and generate wiki update tasks",
    flags=[
      @argparse.FlagArg(
        "dry-run",
        about="Show changes without updating manifest",
      ),
    ],
    options=[
      @argparse.OptionArg(
        "wiki-dir",
        about="Wiki directory",
        default_values=[".indexion/wiki"],
      ),
      @argparse.OptionArg(
        "format",
        about="Output format: md, json, github-issue",
        default_values=["md"],
      ),
      @argparse.OptionArg("output", short='o', about="Output file path"),
      @argparse.OptionArg("specs-dir", about=@help.specs_dir, default_values=[
        "kgfs",
      ]),
    ],
  )
}

///|
pub fn run_matches(matches : @argparse.Matches) -> Unit {
  let wiki_dir = match matches.values.get("wiki-dir") {
    Some(arr) => if arr.length() > 0 { arr[0] } else { ".indexion/wiki" }
    _ => ".indexion/wiki"
  }
  let wiki_dir_resolved = if wiki_dir == ".indexion/wiki" {
    match @config.resolve_project_indexion_dir(".", "wiki") {
      Some(dir) => dir
      None => {
        println("Error: Could not find project root directory.")
        return
      }
    }
  } else {
    wiki_dir
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
  let dry_run = match matches.flags.get("dry-run") {
    Some(v) => v
    _ => false
  }
  // Load wiki
  let registry = @kgf_features.load_registry(
    specs_dir=specs_dir,
    target_dir=".",
  )
  let wiki = match @wiki_reader.load_wiki(wiki_dir_resolved, registry~) {
    Some(w) => w
    None => {
      println("Error: No wiki found at " + wiki_dir_resolved)
      return
    }
  }
  // Run ingest analysis
  let result = @wiki_ingest.analyze(wiki, wiki_dir_resolved)
  // Render output
  let doc = @wiki_ingest.tasks_to_plan_document(result.tasks)
  let output_content = match format {
    "json" => doc.to_json().stringify(indent=2)
    "github-issue" => @plan_render.render_github_issue(doc).format()
    _ => @plan_render.render_markdown(doc)
  }
  @common.write_output(output, output_content, label="Wiki ingest report")
  // Save manifest (unless dry-run)
  if !dry_run {
    @wiki_ingest.save_manifest(result.new_manifest, wiki_dir_resolved)
  }
  // Log the operation
  let log = @wiki_log.WikiLog::load(wiki_dir_resolved)
  let affected : Array[String] = []
  for task in result.tasks {
    affected.push(task.page_id)
  }
  log.append(
    @wiki_log.WikiLogEntry::new(
      timestamp=@env.now(),
      operation="ingest",
      actor="indexion",
      summary=result.tasks.length().to_string() +
        " pages need attention" +
        (if dry_run { " (dry-run)" } else { "" }),
      affected_pages=affected,
    ),
  )
  log.save(wiki_dir_resolved)
}
