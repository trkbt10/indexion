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
#cfg(any(target="native", target="llvm"))
extern "c" fn native_exit(code : Int) = "exit"

///|
#cfg(any(target="native", target="llvm"))
fn exit_with_code(code : Int) -> Unit {
  native_exit(code)
  panic()
}

///|
#cfg(any(target="wasm", target="wasm-gc"))
fn wasm_exit(code : Int) -> Unit = "__moonbit_sys_unstable" "exit"

///|
#cfg(any(target="wasm", target="wasm-gc"))
fn exit_with_code(code : Int) -> Unit {
  wasm_exit(code)
}

///|
#cfg(target="js")
extern "js" fn js_try_exit(code : Int) -> Bool =
  #| () => {
  #|   if (typeof process !== "undefined" && typeof process.exit === "function") {
  #|     process.exit(code);
  #|     return true;
  #|   }
  #|   return false;
  #| }

///|
#cfg(target="js")
fn exit_with_code(code : Int) -> Unit {
  if !js_try_exit(code) {
    panic()
  }
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
  @argparse.Command(
    "check",
    about="Validate source files against KGF specs",
    flags=[
      @argparse.FlagArg(
        "quiet",
        short='q',
        about="Only output errors, suppress warnings",
      ),
    ],
    options=[
      @argparse.OptionArg("include", action=Append, about=@help.include_pattern),
      @argparse.OptionArg("exclude", action=Append, about=@help.exclude_pattern),
      @argparse.OptionArg(
        "format",
        about="Output format: human, json, lcov, cobertura",
        default_values=["human"],
      ),
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
pub fn run_matches(matches : @argparse.Matches) -> Unit {
  let config = CheckConfig::from_matches(matches)
  if config.paths.length() == 0 {
    println(command().render_help())
    return
  }
  let registry = @kgf_features.load_registry(
    specs_dir=config.specs_dir,
    target_dirs=config.paths,
  )
  let reg = match registry {
    Some(reg) => reg
    None => {
      println("error: failed to load KGF registry")
      exit_with_code(1)
      return
    }
  }
  let files = @common.collect_files(
    config.paths,
    includes=config.includes,
    excludes=config.excludes,
    registry=Some(reg),
  )
  let diagnostics : Array[@kgf_check.CheckDiagnostic] = []
  for file in files {
    let path = file.0
    let content = file.1
    match reg.detect_from_path(path) {
      Some(language) =>
        match reg.get_spec(language) {
          Some(spec) => {
            let file_diagnostics = @kgf_check.check_source(content, path, spec)
            for diagnostic in file_diagnostics {
              diagnostics.push(diagnostic)
            }
          }
          None => ()
        }
      None => ()
    }
  }
  diagnostics.sort_by(fn(a, b) { a.compare(b) })
  let mut has_errors = false
  for diagnostic in diagnostics {
    if diagnostic.get_severity() == "error" {
      has_errors = true
    }
  }
  let exit_code = if has_errors { 1 } else { 0 }
  if @common.is_coverage_format(config.format) {
    let source_root = if config.paths.length() > 0 {
      config.paths[0]
    } else {
      "."
    }
    let report = diagnostics_to_coverage_report(
      source_root,
      diagnostics,
      include_warnings=!config.quiet,
    )
    match @common.render_coverage_format(config.format, report) {
      Some(s) => println(s)
      None => ()
    }
  } else if config.format == "json" {
    println(@kgf_check.diagnostics_to_json(diagnostics))
  } else {
    for diagnostic in diagnostics {
      if config.quiet && diagnostic.get_severity() == "warning" {
        continue
      }
      println(diagnostic.format_human())
    }
  }
  if exit_code != 0 {
    exit_with_code(exit_code)
  }
}

///|
/// Convert check diagnostics to the `@coverage` IR.
///
/// Semantics — what "covered" means for `indexion check`:
///
/// - Each `CheckDiagnostic` → finding at `(file, line)` with the
///   diagnostic's source rule attached as the symbol name. Severity
///   filtering follows the same rule as the human-readable renderer:
///   warnings are dropped when `include_warnings` is false (i.e. `-q`).
///
/// Files with no diagnostics do not appear (static-analysis convention).
fn diagnostics_to_coverage_report(
  source_root : String,
  diagnostics : Array[@kgf_check.CheckDiagnostic],
  include_warnings~ : Bool,
) -> @coverage.CoverageReport {
  let b = @coverage.ScanBuilder::new()
  for d in diagnostics {
    if !include_warnings && d.get_severity() == "warning" {
      continue
    }
    let line = if d.get_line() > 0 { d.get_line() } else { 1 }
    b.record(d.get_file(), line, name=d.get_source())
  }
  b.to_coverage_report("indexion-check", source_root)
}
