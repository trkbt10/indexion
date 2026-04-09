///|
/// # indexion wiki pages
///
/// Manage wiki pages: plan, add, update, and detect stale pages.
///
/// ## Subcommands
///
/// - `plan`   - Propose which pages to create (init-like)
/// - `add`    - Add a new page
/// - `update` - Update an existing page
/// - `ingest` - Detect which existing pages need updating

///|
pub fn command() -> @argparse.Command {
  @argparse.Command(
    "pages",
    about="Manage wiki pages (plan, add, update, ingest)",
    subcommand_required=true,
    subcommands=[
      @wiki_plan.command(),
      @wiki_add_page.command(),
      @wiki_update_page.command(),
      @wiki_ingest_cli.command(),
    ],
  )
}

///|
pub async fn dispatch(matches : @argparse.Matches) -> Unit {
  guard matches.subcommand is Some((name, sub)) else { return }
  match name {
    "plan" => @wiki_plan.run_matches(sub)
    "add" => @wiki_add_page.run_matches(sub)
    "update" => @wiki_update_page.run_matches(sub)
    "ingest" => @wiki_ingest_cli.run_matches(sub)
    _ => ()
  }
}
