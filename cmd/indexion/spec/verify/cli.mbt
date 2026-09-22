///|
/// # indexion spec verify
///
/// Check spec-to-implementation conformance using vocabulary analysis.
///
/// Tokenizes both specification documents and implementation code using KGF,
/// builds TF-IDF vectors, and identifies spec terms that are absent from
/// the implementation. Uses the same NLP approach as `plan reconcile`'s
/// vocabulary divergence detection, but in the reverse direction:
/// spec → code instead of code → docs.
///
/// ## Usage
///
/// ```bash
/// indexion spec verify --spec='docs/spec/*.md' src/
/// ```

///|
/// Define the spec verify command for argparse.
pub fn command() -> @argparse.Command {
  @argparse.Command(
    "verify",
    about="Check spec-to-implementation conformance",
    options=[
      @argparse.OptionArg(
        "spec",
        action=Append,
        about="Spec document glob pattern (repeatable, required)",
      ),
      @argparse.OptionArg(
        "format",
        about="Output format: json, md, github-issue, lcov, cobertura",
        default_values=["json"],
      ),
      @argparse.OptionArg(
        "focus",
        about="Filter by token kind (e.g., ident, text, vocab, all)",
        default_values=["all"],
      ),
      @argparse.OptionArg("max-candidates", about="Maximum items in output", default_values=[
        "200",
      ]),
      @argparse.OptionArg("specs-dir", about=@help.specs_dir),
      @argparse.OptionArg("output", short='o', about=@help.output),
    ],
    positionals=[
      @argparse.PositionArg(
        "directory",
        num_args=@argparse.ValueRange(lower=0),
        about="Target implementation directory to verify against",
      ),
    ],
  )
}

///|
/// Parse CLI arguments into VerifyConfig.
fn resolve_config_from_matches(matches : @argparse.Matches) -> VerifyConfig {
  let mut config = VerifyConfig::default()
  match matches.values.get("spec") {
    Some(arr) => config = { ..config, spec_patterns: arr.copy(), }
    _ => ()
  }
  match matches.values.get("format") {
    Some(arr) => if arr.length() > 0 { config = { ..config, format: arr[0], } }
    _ => ()
  }
  match matches.values.get("focus") {
    Some(arr) => if arr.length() > 0 { config = { ..config, focus: arr[0], } }
    _ => ()
  }
  match matches.values.get("max-candidates") {
    Some(arr) =>
      if arr.length() > 0 {
        config = { ..config, max_candidates: @common.parse_int(arr[0]), }
      }
    _ => ()
  }
  match matches.values.get("specs-dir") {
    Some(arr) =>
      if arr.length() > 0 {
        config = { ..config, specs_dir: arr[0], }
      }
    _ => ()
  }
  match matches.values.get("output") {
    Some(arr) => if arr.length() > 0 { config = { ..config, output: arr[0], } }
    _ => ()
  }
  match matches.values.get("directory") {
    Some(arr) =>
      if arr.length() > 0 {
        config = { ..config, target_dir: arr[0], }
      }
    _ => ()
  }
  config
}

///|
/// Entry point for the spec verify subcommand.
pub fn run_matches(matches : @argparse.Matches) -> Unit {
  let config = resolve_config_from_matches(matches)
  if config.spec_patterns.length() == 0 {
    println(
      "Error: --spec is required. Provide one or more glob patterns for spec documents.",
    )
    println("")
    println(command().render_help())
    return
  }
  if config.target_dir.length() == 0 {
    println(@help.dir_required)
    println("")
    println(command().render_help())
    return
  }
  let report = run_analysis(config)
  let rendered = render_output(report, config.format)
  @common.write_output(config.output, rendered, label="Spec verify report")
}

///|
/// Run spec verify analysis and return rendered output as a string.
pub fn run_to_string(config : VerifyConfig) -> String? {
  if config.spec_patterns.length() == 0 || config.target_dir.length() == 0 {
    return None
  }
  let report = run_analysis(config)
  Some(render_output(report, config.format))
}
