///|
/// # indexion doc
///
/// Documentation commands for generating and managing documentation.
///
/// ## Subcommands
///
/// - `gen` - Generate documentation from source files (KGF-based)
/// - `readme` - Generate README.md from source doc comments

///|
pub fn show_help() -> Unit {
  println("indexion doc - Documentation commands")
  println("")
  println("Usage:")
  println("  indexion doc <command> [options]")
  println("")
  println("Commands:")
  println("  gen      Generate documentation from source files (KGF-based)")
  println("  readme   Generate README.md from source doc comments")
  println("")
  println("Use 'indexion doc <command> --help' for more information about a command.")
}

///|
pub fn run(args : Array[String], start_idx : Int) -> Unit {
  if start_idx >= args.length() {
    show_help()
    return
  }
  let subcommand = args[start_idx]
  match subcommand {
    "gen" | "generate" => @gen.run(args, start_idx + 1)
    "readme" => @readme.run(args, start_idx + 1)
    "--help" | "-h" | "help" => show_help()
    _ => {
      println("Unknown doc command: " + subcommand)
      println("")
      show_help()
    }
  }
}
