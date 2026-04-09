///|
/// # indexion wiki
///
/// Wiki management commands for building, maintaining, and exporting wikis.
///
/// ## Subcommands
///
/// - `pages`  - Manage wiki pages (plan, add, update, ingest)
/// - `index`  - Manage wiki index (nav catalog + search vectors)
/// - `lint`   - Check wiki structural integrity
/// - `export` - Export indexion wiki to external format (GitHub, GitLab)
/// - `import` - Import external wiki into indexion format
/// - `log`    - Display wiki operation log
/// - `hook`   - Manage git hooks for automatic wiki maintenance

///|
pub fn command() -> @argparse.Command {
  @argparse.Command(
    "wiki",
    about="Wiki management (pages, index, lint, export, import, log, hook)",
    subcommand_required=true,
    subcommands=[
      @wiki_pages_cli.command(),
      @wiki_index_cli.command(),
      @wiki_lint_cli.command(),
      @wiki_export.command(),
      @wiki_import.command(),
      @wiki_log_cli.command(),
      @wiki_hook_cli.command(),
    ],
  )
}

///|
pub async fn dispatch(matches : @argparse.Matches) -> Unit {
  guard matches.subcommand is Some((name, sub)) else { return }
  match name {
    "pages" => @wiki_pages_cli.dispatch(sub)
    "index" => @wiki_index_cli.dispatch(sub)
    "lint" => @wiki_lint_cli.run_matches(sub)
    "export" => @wiki_export.run_matches(sub)
    "import" => @wiki_import.run_matches(sub)
    "log" => @wiki_log_cli.run_matches(sub)
    "hook" => @wiki_hook_cli.dispatch(sub)
    _ => ()
  }
}
