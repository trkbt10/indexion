///|
/// Plan CLI - Generate various planning documents.
/// Subcommands:
///   refactor      - Generate refactoring plan from similarity analysis
///   documentation - Generate documentation coverage analysis
///   readme        - Generate README documentation tasks
///   solid         - Generate solidification plan for common code extraction
///   reconcile     - Generate implementation/documentation drift report
///   unwrap        - Detect unnecessary wrappers for removal

///|
/// Build the argparse Command for the plan subcommand.
pub fn command() -> @argparse.Command {
  @argparse.Command(
    "plan",
    about="Generate planning documents (refactor, solid, unwrap, etc.)",
    subcommand_required=true,
    subcommands=[
      @refactor.command(),
      @documentation.command(),
      @readme.command(),
      @solid.command(),
      @reconcile.command(),
      @unwrap.command(),
    ],
  )
}

///|
/// Dispatch plan subcommand based on parsed matches.
pub async fn dispatch(matches : @argparse.Matches) -> Unit {
  guard matches.subcommand is Some((name, sub)) else { return }
  match name {
    "refactor" => @refactor.run_matches(sub)
    "documentation" => @documentation.run_matches(sub)
    "readme" => @readme.run_matches(sub)
    "solid" => @solid.run_matches(sub)
    "reconcile" => @reconcile.run_matches(sub)
    "unwrap" => @unwrap.run_matches(sub)
    _ => ()
  }
}
