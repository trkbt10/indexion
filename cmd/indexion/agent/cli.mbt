///|
/// # indexion agent
///
/// Agent-facing orientation and workflow helpers.

///|
pub fn command() -> @argparse.Command {
  @argparse.Command(
    "agent",
    about="Generate agent orientation context before coding",
    subcommand_required=true,
    subcommands=[orient_command()],
  )
}

///|
pub async fn dispatch(matches : @argparse.Matches) -> Unit {
  guard matches.subcommand is Some((name, sub)) else { return }
  match name {
    "orient" => run_orient(sub)
    _ => ()
  }
}
