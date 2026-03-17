///|
/// Plan CLI - Generate various planning documents.
/// Subcommands:
///   refactor      - Generate refactoring plan from similarity analysis
///   documentation - Generate documentation coverage analysis
///   readme        - Generate README documentation tasks
///   reconcile     - Generate implementation/documentation drift report

///|
/// Display help message for plan command.
pub fn show_help() -> Unit {
  println("indexion plan - Generate planning documents")
  println("")
  println("Usage:")
  println("  indexion plan <command> [options]")
  println("")
  println("Commands:")
  println(
    "  refactor       Generate refactoring plan from file similarity analysis",
  )
  println("  documentation  Generate documentation coverage analysis")
  println(
    "  readme         Generate README documentation tasks for manual/LLM writing",
  )
  println(
    "  solid          Generate solidification plan for common code extraction",
  )
  println(
    "  reconcile      Detect implementation/documentation drift candidates",
  )
  println("  unwrap         Detect unnecessary wrappers for removal")
  println("")
  println(
    "Use 'indexion plan <command> --help' for more information about a command.",
  )
}

///|
/// Run the plan command with given arguments.
pub fn run(args : Array[String], start_idx : Int) -> Unit {
  if start_idx >= args.length() {
    show_help()
    return
  }
  let subcommand = args[start_idx]
  match subcommand {
    "refactor" => @refactor.run(args, start_idx + 1)
    "documentation" | "doc" | "docs" => @documentation.run(args, start_idx + 1)
    "readme" => @readme.run(args, start_idx + 1)
    "solid" => @solid.run(args, start_idx + 1)
    "reconcile" => @reconcile.run(args, start_idx + 1)
    "unwrap" => @unwrap.run(args, start_idx + 1)
    "--help" | "-h" | "help" => show_help()
    _ => {
      println("Unknown plan command: " + subcommand)
      println("")
      show_help()
    }
  }
}
