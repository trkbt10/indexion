///|
/// # indexion wiki
///
/// Wiki management commands for building, maintaining, and exporting wikis.
///
/// ## Subcommands
///
/// - `plan` - Generate wiki writing plan from project analysis
/// - `lint` - Check wiki structural integrity
/// - `ingest` - Detect source changes and generate wiki update tasks
/// - `index` - Generate wiki index page (category catalog + hub pages)
/// - `add-page` - Add a new page to the wiki
/// - `update-page` - Update an existing wiki page
/// - `export` - Export indexion wiki to external format (GitHub, GitLab)
/// - `import` - Import external wiki into indexion format
/// - `log` - Display wiki operation log

///|
/// Build the argparse Command for the wiki subcommand.
pub fn command() -> @argparse.Command {
  @argparse.Command(
    "wiki",
    about="Wiki management (plan, lint, ingest, index, export, import, log)",
    subcommand_required=true,
    subcommands=[
      @wiki_plan.command(),
      @wiki_lint_cli.command(),
      @wiki_ingest_cli.command(),
      @wiki_index_cli.command(),
      @wiki_add_page.command(),
      @wiki_update_page.command(),
      @wiki_export.command(),
      @wiki_import.command(),
      @wiki_log_cli.command(),
    ],
  )
}

///|
/// Dispatch wiki subcommand based on parsed matches.
pub async fn dispatch(matches : @argparse.Matches) -> Unit {
  guard matches.subcommand is Some((name, sub)) else { return }
  match name {
    "plan" => @wiki_plan.run_matches(sub)
    "lint" => @wiki_lint_cli.run_matches(sub)
    "ingest" => @wiki_ingest_cli.run_matches(sub)
    "index" => @wiki_index_cli.run_matches(sub)
    "add-page" => @wiki_add_page.run_matches(sub)
    "update-page" => @wiki_update_page.run_matches(sub)
    "export" => @wiki_export.run_matches(sub)
    "import" => @wiki_import.run_matches(sub)
    "log" => @wiki_log_cli.run_matches(sub)
    _ => ()
  }
}
