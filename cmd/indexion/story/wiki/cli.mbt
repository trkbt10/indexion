/// # indexion story wiki
///
/// Story-scoped knowledge base. Builds a wiki page per character, setting,
/// research note, and plot act, drawing content from the story's
/// `sources/references/` markdown and the plot acts extracted by
/// `story reconcile`.
///
/// ## Subcommands
///
/// - `plan`  — propose pages from a story dataset (preview, no writes)
/// - `build` — apply the plan, writing pages to `<root>/.indexion/wiki/`

///|
pub fn command() -> @argparse.Command {
  @argparse.Command(
    "wiki",
    about="Story-scoped wiki: characters, settings, research, plot acts",
    subcommand_required=true,
    subcommands=[@story_wiki_plan.command(), @story_wiki_build.command()],
  )
}

///|
pub fn dispatch(matches : @argparse.Matches) -> Unit {
  guard matches.subcommand is Some((name, sub)) else { return }
  match name {
    "plan" => @story_wiki_plan.run_matches(sub)
    "build" => @story_wiki_build.run_matches(sub)
    _ => ()
  }
}
