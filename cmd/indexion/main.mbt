///|
/// # indexion
///
/// Source code exploration and documentation tool.
///
/// ## Overview
///
/// indexion provides tools for analyzing, exploring, and documenting source code.
/// Named after Korzybski's "the map is not the territory" - indexion helps build
/// dynamic maps of your codebase.
///
/// ## Installation
///
/// ```bash
/// # Build from source
/// moon build --target native
///
/// # Or download release
/// # See: https://github.com/trkbt10/indexion/releases
/// ```
///
/// ## Commands
///
/// | Command | Description |
/// |---------|-------------|
/// | `explore` | Analyze file similarity in a directory |
/// | `plan refactor` | Generate refactoring plan from similarity |
/// | `doc gen` | Generate documentation from source |
/// | `sim` | Calculate text similarity/distance |
///
/// ## Quick Start
///
/// ```bash
/// # Explore similarity in your codebase
/// indexion explore --format=list src/
///
/// # Generate refactoring plan
/// indexion plan refactor --threshold=0.8 src/
///
/// # Generate documentation
/// indexion doc gen src/
/// ```
///
/// ## Configuration
///
/// - KGF specs: `kgfs/` directory for language specifications
/// - Doc config: `doc.json` for documentation generation settings

///|
/// Main entry point.
fn main {
  let args = @sys.get_cli_args()

  // Find subcommand (skip program name)
  let subcommand = if args.length() > 1 { args[1] } else { "help" }

  match subcommand {
    "explore" => @explore_cli.run(args, 2)
    "plan" => @plan_cli.run(args, 2)
    "doc" => @doc_cli.run(args, 2)
    "sim" | "similarity" => @similarity_cli.run(args, 2)
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
  println("  explore     Analyze similarity across files in a directory")
  println("  plan        Generate planning documents (refactor, etc.)")
  println("  doc         Documentation commands (gen, etc.)")
  println("  sim         Calculate text similarity/distance")
  println("  help        Show this help message")
  println("  version     Show version information")
  println("")
  println("Run 'indexion <command> --help' for more information on a command.")
  println("")
  println("Examples:")
  println("  indexion explore kgfs/")
  println("  indexion plan refactor --threshold=0.7 src/")
  println("  indexion doc gen --format=markdown src/")
  println("  indexion sim \"hello world\" \"hello there\"")
}

///|
/// Show version information.
fn show_version() -> Unit {
  println("indexion version 0.1.0")
}
