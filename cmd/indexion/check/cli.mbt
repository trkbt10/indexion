///|
/// CLI configuration for `indexion check`.
priv struct CheckConfig {
  paths : Array[String]
  includes : Array[String]
  excludes : Array[String]
  format : String
  specs_dir : String
  quiet : Bool
}

///|
fn get_str(
  matches : @argparse.Matches,
  key : String,
  default_ : String,
) -> String {
  match matches.values.get(key) {
    Some(values) => if values.length() > 0 { values[0] } else { default_ }
    None => default_
  }
}

///|
fn get_all(matches : @argparse.Matches, key : String) -> Array[String] {
  match matches.values.get(key) {
    Some(values) => values
    None => []
  }
}

///|
fn CheckConfig::from_matches(matches : @argparse.Matches) -> CheckConfig {
  {
    paths: get_all(matches, "paths"),
    includes: get_all(matches, "include"),
    excludes: get_all(matches, "exclude"),
    format: get_str(matches, "format", "human"),
    specs_dir: get_str(matches, "specs-dir", "kgfs"),
    quiet: matches.flags.get("quiet").unwrap_or(false),
  }
}

///|
/// Defines the `indexion check` command.
pub fn command() -> @argparse.Command {
  @argparse.Command::new(
    "check",
    about="Validate source files against KGF specs",
    flags=[
      @argparse.FlagArg::new(
        "quiet",
        short='q',
        about="Only output errors, suppress warnings",
      ),
    ],
    options=[
      @argparse.OptionArg("include", action=Append, about=@help.include_pattern),
      @argparse.OptionArg("exclude", action=Append, about=@help.exclude_pattern),
      @argparse.OptionArg("format", about="Output format: human, json", default_values=[
        "human",
      ]),
      @argparse.OptionArg("specs-dir", about=@help.specs_dir, default_values=[
        "kgfs",
      ]),
    ],
    positionals=[
      @argparse.PositionArg(
        "paths",
        about="Files or directories to check",
        num_args=@argparse.ValueRange(lower=1),
      ),
    ],
  )
}

///|
/// Entry point for the check command.
pub async fn run_matches(matches : @argparse.Matches) -> Unit {
  let config = CheckConfig::from_matches(matches)
  if config.paths.length() == 0 {
    println(command().render_help())
    return
  }
  let registry = @kgf_features.load_registry(
    specs_dir=config.specs_dir,
    target_dirs=config.paths,
  )
  let files = @common.collect_files(
    config.paths,
    includes=config.includes,
    excludes=config.excludes,
    registry~,
  )
  let diagnostics : Array[@kgf_check.CheckDiagnostic] = []
  match registry {
    Some(reg) =>
      for file in files {
        let path = file.0
        let content = file.1
        match reg.detect_from_path(path) {
          Some(language) =>
            match reg.get_spec(language) {
              Some(spec) => {
                let file_diagnostics = @kgf_check.check_source(
                  content, path, spec,
                )
                for diagnostic in file_diagnostics {
                  diagnostics.push(diagnostic)
                }
              }
              None => ()
            }
          None => ()
        }
      }
    None => ()
  }
  diagnostics.sort_by(fn(a, b) { a.compare(b) })
  if config.format == "json" {
    println(@kgf_check.diagnostics_to_json(diagnostics))
  } else {
    for diagnostic in diagnostics {
      if config.quiet && diagnostic.get_severity() == "warning" {
        continue
      }
      println(diagnostic.format_human())
    }
  }
}
