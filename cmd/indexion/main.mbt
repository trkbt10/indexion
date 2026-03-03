///|
/// indexion - Source code exploration and documentation tool
///
/// Usage:
///   indexion <command> [options]
///
/// Commands:
///   docgen      Generate documentation from source files
///   similarity  Calculate text similarity/distance
///   help        Show this help message
///   version     Show version information
///
/// Run 'indexion <command> --help' for more information on a command.

///|
/// Main entry point.
fn main {
  let args = @sys.get_cli_args()

  // Find subcommand (skip program name)
  let subcommand = if args.length() > 1 { args[1] } else { "help" }

  match subcommand {
    "docgen" => @docgen_cli.run(args, 2)
    "similarity" | "sim" => @similarity_cli.run(args, 2)
    "version" | "-v" | "--version" => show_version()
    "help" | "-h" | "--help" => show_help()
    _ => {
      println("Unknown command: " + subcommand)
      println("")
      show_help()
    }
  }
}

///|
/// Show main help message.
fn show_help() -> Unit {
  println("indexion - Source code exploration and documentation tool")
  println("")
  println("Usage:")
  println("  indexion <command> [options]")
  println("")
  println("Commands:")
  println("  docgen      Generate documentation from source files")
  println("  similarity  Calculate text similarity/distance (alias: sim)")
  println("  help        Show this help message")
  println("  version     Show version information")
  println("")
  println("Run 'indexion <command> --help' for more information on a command.")
  println("")
  println("Examples:")
  println("  indexion docgen --format=markdown src/")
  println("  indexion similarity \"hello world\" \"hello there\"")
}

///|
/// Show version information.
fn show_version() -> Unit {
  println("indexion version 0.1.0")
}
