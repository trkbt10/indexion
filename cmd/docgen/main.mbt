///|
/// Documentation Generator CLI (standalone entry point)
/// Delegates to the CLI library.

///|
/// Main entry point.
fn main {
  let args = @sys.get_cli_args()
  // Start from index 1 (skip program name)
  @docgen_cli.run(args, 1)
}
