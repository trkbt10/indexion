///|
/// # indexion spec vocabulary
///
/// Compare vocabulary across one or more source documents and one or more
/// target documents using the KGF registry as the language abstraction layer.
///
/// KGF supplies language detection and token classes. This command only
/// decides which vocabulary sets to compare:
///
/// - required source terms must be observed in the target group.
/// - observed target terms must be allowed by the source group.
/// - `--direction` chooses whether one or both checks gate the exit status.

///|
pub fn command() -> @argparse.Command {
  @argparse.Command(
    "vocabulary",
    about="Check n:m vocabulary coverage/drift using KGF-backed tokenization",
    options=[
      @argparse.OptionArg(
        role_source,
        action=Append,
        about="Source/spec file. Repeat for n:m comparison.",
      ),
      @argparse.OptionArg(
        role_target,
        action=Append,
        about="Target/conformance/implementation file. Repeat for n:m comparison.",
      ),
      @argparse.OptionArg(
        "direction",
        about="Check direction: both, source-to-target, target-to-source",
        default_values=[direction_both],
      ),
      @argparse.OptionArg(
        "specs-dir",
        about="KGF specs directory (default: auto-detect)",
      ),
      @argparse.OptionArg("format", about="Output format: text, md, json", default_values=[
        output_format_text,
      ]),
      @argparse.OptionArg("output", short='o', about=@help.output),
    ],
  )
}

///|
fn config_from_matches(matches : @argparse.Matches) -> VocabularyConfig {
  let mut config = VocabularyConfig::default()
  config = { ..config, source_paths: @common.arg_list(matches, role_source), }
  config = { ..config, target_paths: @common.arg_list(matches, role_target), }
  config = {
    ..config,
    direction: @common.get_option(matches, "direction", direction_both),
  }
  config = {
    ..config,
    format: @common.get_option(matches, "format", output_format_text),
  }
  config = { ..config, output: @common.get_option(matches, "output", ""), }
  match matches.values.get("specs-dir") {
    Some(vals) =>
      if vals.length() > 0 && vals[0].length() > 0 {
        config = { ..config, specs_dir: Some(vals[0]), }
      }
    None => ()
  }
  config
}

///|
pub fn run_matches(matches : @argparse.Matches) -> Unit {
  let config = config_from_matches(matches)
  if config.source_paths.length() == 0 {
    println("Error: at least one --source is required.")
    println("")
    println(command().render_help())
    return
  }
  if config.target_paths.length() == 0 {
    println("Error: at least one --target is required.")
    println("")
    println(command().render_help())
    return
  }
  let report = match build_report(config) {
    Some(r) => r
    None => return
  }
  @common.write_output(
    config.output,
    render_output(report, config.format),
    label="vocabulary drift report",
  )
  if !report.passed {
    @common.exit_with_code(1)
  }
}

///|
pub fn run_to_string(config : VocabularyConfig) -> String? {
  if config.source_paths.length() == 0 || config.target_paths.length() == 0 {
    return None
  }
  match build_report(config) {
    Some(report) => Some(render_output(report, config.format))
    None => None
  }
}
