///|
/// # indexion doc
///
/// Documentation commands for generating and managing documentation.
///
/// ## Subcommands
///
/// - `init` - Initialize documentation templates (README.md)
/// - `graph` - Generate dependency graph in Mermaid format
/// - `readme` - Generate README.md from source doc comments (with template support)

///|
/// Build the argparse Command for the doc subcommand.
pub fn command() -> @argparse.Command {
  @argparse.Command(
    "doc",
    about="Documentation commands (graph, readme, init)",
    subcommand_required=true,
    subcommands=[
      @init.command(),
      @graph.command(),
      @readme.command(),
    ],
  )
}

///|
/// Dispatch doc subcommand based on parsed matches.
pub fn dispatch(matches : @argparse.Matches) -> Unit {
  guard matches.subcommand is Some((name, sub)) else { return }
  match name {
    "init" => @init.run_matches(sub)
    "graph" => @graph.run_matches(sub)
    "readme" => @readme.run_matches(sub)
    _ => ()
  }
}
