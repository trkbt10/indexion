///|
pub fn command() -> @argparse.Command {
  @argparse.Command(
    "draft",
    about="Generate an SDD draft from usage or README documents",
    options=[
      @argparse.OptionArg("output", short='o', about=@help.output),
      @argparse.OptionArg("format", about="Output format: markdown, json", default_values=[
        "markdown",
      ]),
      @argparse.OptionArg("specs-dir", about=@help.specs_dir),
      @argparse.OptionArg("profile", about="Draft profile: sdd-requirement", default_values=[
        "sdd-requirement",
      ]),
      @argparse.OptionArg(
        "max-requirements",
        about="Maximum drafted requirements",
        default_values=["64"],
      ),
    ],
    positionals=[
      @argparse.PositionArg(
        "source-path",
        about="Usage or README file/directory to draft from",
      ),
    ],
  )
}

///|
fn resolve_config(matches : @argparse.Matches) -> @spec_draft.DraftConfig {
  let mut config = @spec_draft.DraftConfig::default()
  match matches.values.get("source-path") {
    Some(values) =>
      if values.length() > 0 {
        config = { ..config, source_path: values[0] }
      }
    None => ()
  }
  match matches.values.get("output") {
    Some(values) =>
      if values.length() > 0 {
        config = { ..config, output: values[0] }
      }
    None => ()
  }
  match matches.values.get("format") {
    Some(values) =>
      if values.length() > 0 {
        config = { ..config, format: values[0] }
      }
    None => ()
  }
  match matches.values.get("specs-dir") {
    Some(values) =>
      if values.length() > 0 {
        config = { ..config, specs_dir: values[0] }
      }
    None => ()
  }
  match matches.values.get("profile") {
    Some(values) =>
      if values.length() > 0 {
        config = { ..config, profile: values[0] }
      }
    None => ()
  }
  match matches.values.get("max-requirements") {
    Some(values) =>
      if values.length() > 0 {
        config = { ..config, max_requirements: @common.parse_int(values[0]) }
      }
    None => ()
  }
  config
}

///|
pub fn run_matches(matches : @argparse.Matches) -> Unit {
  let config = resolve_config(matches)
  if config.source_path.length() == 0 {
    println("Error: source-path is required.")
    println("")
    println(command().render_help())
    return
  }
  match @spec_draft.run_to_string(config) {
    Some(rendered) =>
      @common.write_output(config.output, rendered, label="Spec draft")
    None => println("No draftable SDD requirements found.")
  }
}

///|
pub fn run_to_string(config : @spec_draft.DraftConfig) -> String? {
  if config.source_path.length() == 0 {
    return None
  }
  @spec_draft.run_to_string(config)
}
