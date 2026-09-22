///|
/// # indexion update
///
/// Check for updates and install the latest version.
///
/// ## Usage
///
/// ```bash
/// indexion update [options]
/// ```

///|
/// Configuration for update command.
pub struct UpdateConfig {
  check_only : Bool
  force : Bool
}

///|
/// Create a default UpdateConfig with all options disabled.
pub fn UpdateConfig::default() -> UpdateConfig {
  { check_only: false, force: false, }
}

///|
/// Create UpdateConfig from argparse Matches.
pub fn UpdateConfig::from_matches(matches : @argparse.Matches) -> UpdateConfig {
  let mut config = UpdateConfig::default()
  match matches.flags.get("check") {
    Some(true) => config = { ..config, check_only: true, }
    _ => ()
  }
  match matches.flags.get("force") {
    Some(true) => config = { ..config, force: true, }
    _ => ()
  }
  config
}

///|
/// Define the update command for argparse.
pub fn command() -> @argparse.Command {
  @argparse.Command(
    "update",
    about="Check for updates and install the latest version",
    flags=[
      @argparse.FlagArg(
        "check",
        about="Check for updates only (do not download)",
      ),
      @argparse.FlagArg(
        "force",
        about="Reinstall even if already on latest version",
      ),
    ],
  )
}

///|
/// Entry point for the update subcommand using argparse Matches.
pub async fn run_matches(matches : @argparse.Matches) -> Unit {
  let config = UpdateConfig::from_matches(matches)
  run_async(config)
}

///|
async fn run_async(config : UpdateConfig) -> Unit {
  let result = @update_core.check_for_update() catch {
    err => {
      println("Error checking for updates: " + err.to_string())
      return
    }
  }
  println("Current version: " + result.current_version)
  println("Latest version:  " + result.latest_version)
  if config.check_only {
    if result.has_update {
      println("")
      println("Update available! Run 'indexion update' to install.")
    } else {
      println("")
      println("You are on the latest version.")
    }
    return
  }
  if !result.has_update && !config.force {
    println("")
    println("Already up to date.")
    return
  }
  println("")
  @update_core.perform_update(result.latest_version) catch {
    err => {
      println("Update failed: " + err.to_string())
      return
    }
  }
}
