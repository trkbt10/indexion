/// # indexion story
///
/// Story divergence analysis: measure n:m vocabulary drift between
/// novel-writing source materials and the resulting prose.
///
/// ## Subcommands
///
/// - `analyze` — read a story directory (sources/ + prose/) and report
///   per-chapter attribution, under-coverage, and out-of-source drift.
///
/// The convention assumes the story root contains:
///
/// ```
/// <story-root>/
/// ├── sources/                ← supply side (n)
/// │   ├── plot/               ← plot drafts and revisions
/// │   ├── references/         ← character sheet, setting, research notes
/// │   └── scene-notes/        ← intermediate scene memos
/// └── prose/                  ← derived chapters (m)
///     ├── 01-chapter.txt
///     ├── 02-chapter.txt
///     └── ...
/// ```

///|
pub fn command() -> @argparse.Command {
  @argparse.Command(
    "story",
    about="Story divergence analysis (n:m sources → prose)",
    subcommand_required=true,
    subcommands=[
      @story_analyze.command(),
      @story_reconcile_cli.command(),
      @story_names.command(),
      @story_wiki_cli.command(),
    ],
  )
}

///|
pub fn dispatch(matches : @argparse.Matches) -> Unit {
  guard matches.subcommand is Some((name, sub)) else { return }
  match name {
    "analyze" => @story_analyze.run_matches(sub)
    "reconcile" => @story_reconcile_cli.run_matches(sub)
    "names" => @story_names.run_matches(sub)
    "wiki" => @story_wiki_cli.dispatch(sub)
    _ => ()
  }
}
