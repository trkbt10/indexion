///|
/// Stub for non-native targets.
pub fn command() -> @argparse.Command {
  @argparse.Command("update", about="Check for updates (native only)")
}

///|
/// Stub for non-native targets.
pub fn run_matches(_matches : @argparse.Matches) -> Unit {
  println("indexion update is only supported on native target")
}
