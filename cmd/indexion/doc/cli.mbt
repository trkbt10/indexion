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
/// Display help message for doc command.
pub fn show_help() -> Unit {
  println("indexion doc - Documentation commands")
  println("")
  println("Usage:")
  println("  indexion doc <command> [options]")
  println("")
  println("Commands:")
  println("  init     Initialize documentation templates (README.md)")
  println("  graph    Generate dependency graph in Mermaid format")
  println("  readme   Generate README.md from source doc comments")
  println("")
  println(
    "Use 'indexion doc <command> --help' for more information about a command.",
  )
}

///|
/// Run the doc command with given arguments.
pub fn run(args : Array[String], start_idx : Int) -> Unit {
  if start_idx >= args.length() {
    show_help()
    return
  }
  let subcommand = args[start_idx]
  match subcommand {
    "init" => @init.run(args, start_idx + 1)
    "graph" => @graph.run(args, start_idx + 1)
    "readme" => @readme.run(args, start_idx + 1)
    "--help" | "-h" | "help" => show_help()
    _ => {
      println("Unknown doc command: " + subcommand)
      println("")
      show_help()
    }
  }
}
