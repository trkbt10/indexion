///|
fn common_options() -> Array[@argparse.OptionArg] {
  [
    @argparse.OptionArg("output", short='o', about=@help.output),
    @argparse.OptionArg(
      "spec-format",
      about="SDD KGF spec language or auto (for example: sdd-requirement)",
      default_values=["auto"],
    ),
    @argparse.OptionArg(
      "algorithm",
      about="Similarity algorithm: tfidf, ncd, hybrid",
      default_values=["hybrid"],
    ),
    @argparse.OptionArg("threshold", about="Similarity threshold (0.0-1.0)", default_values=[
      "0.6",
    ]),
    @argparse.OptionArg("git-base", about="Git base ref for incremental mode", default_values=[
      "HEAD",
    ]),
    @argparse.OptionArg("specs-dir", about=@help.specs_dir),
    @argparse.OptionArg(
      "cache-dir",
      about="Cache directory (default: .indexion/cache/spec/align)",
    ),
  ]
}

///|
fn common_flags() -> Array[@argparse.FlagArg] {
  [
    @argparse.FlagArg::new(
      "incremental",
      about="Restrict results to files changed from git base",
    ),
  ]
}

///|
fn common_positionals() -> Array[@argparse.PositionArg] {
  [
    @argparse.PositionArg("spec-path", about="Specification file or directory"),
    @argparse.PositionArg("impl-path", about="Implementation file or directory"),
  ]
}

///|
fn diff_command() -> @argparse.Command {
  @argparse.Command(
    "diff",
    about="Detect spec and implementation drift",
    options=common_options() +
      [
        @argparse.OptionArg(
          "format",
          about="Output format: json, markdown, summary",
          default_values=["markdown"],
        ),
      ],
    flags=common_flags(),
    positionals=common_positionals(),
  )
}

///|
fn trace_command() -> @argparse.Command {
  @argparse.Command(
    "trace",
    about="Generate requirement to implementation traceability",
    options=common_options() +
      [
        @argparse.OptionArg(
          "format",
          about="Output format: json, yaml, mermaid",
          default_values=["json"],
        ),
      ],
    flags=common_flags(),
    positionals=common_positionals(),
  )
}

///|
fn suggest_command() -> @argparse.Command {
  @argparse.Command(
    "suggest",
    about="Generate provenance-backed reconciliation suggestions",
    options=common_options() +
      [
        @argparse.OptionArg(
          "format",
          about="Output format: markdown, tasks, delta-spec, json",
          default_values=["markdown"],
        ),
        @argparse.OptionArg(
          "direction",
          about="Suggestion direction: spec-wins, impl-wins, both",
          default_values=["both"],
        ),
        @argparse.OptionArg(
          "agent",
          about="Agent hint for task rendering: generic, claude, copilot",
          default_values=["generic"],
        ),
      ],
    flags=common_flags(),
    positionals=common_positionals(),
  )
}

///|
fn status_command() -> @argparse.Command {
  @argparse.Command(
    "status",
    about="Summarize alignment status for CI",
    options=common_options() +
      [
        @argparse.OptionArg(
          "format",
          about="Output format: text, json, badge",
          default_values=["text"],
        ),
        @argparse.OptionArg(
          "fail-on",
          about="Failure condition: none, drifted, spec-only, shallow, any",
          default_values=["none"],
        ),
      ],
    flags=common_flags(),
    positionals=common_positionals(),
  )
}

///|
fn watch_command() -> @argparse.Command {
  @argparse.Command(
    "watch",
    about="Watch spec and implementation inputs and rerun alignment on changes",
    options=common_options() +
      [
        @argparse.OptionArg(
          "mode",
          about="Watched subcommand: diff, trace, suggest, status",
          default_values=["diff"],
        ),
        @argparse.OptionArg(
          "format",
          about="Output format for the watched subcommand",
          default_values=["markdown"],
        ),
        @argparse.OptionArg("interval", about="Polling interval in seconds", default_values=[
          "2",
        ]),
        @argparse.OptionArg(
          "limit",
          about="Maximum number of emitted updates (0 = unlimited)",
          default_values=["0"],
        ),
      ],
    flags=common_flags(),
    positionals=common_positionals(),
  )
}

///|
pub fn command() -> @argparse.Command {
  @argparse.Command(
    "align",
    about="Align SDD-style specification documents with implementation",
    subcommand_required=true,
    subcommands=[
      diff_command(),
      trace_command(),
      suggest_command(),
      status_command(),
      watch_command(),
    ],
  )
}

///|
fn resolve_config(
  matches : @argparse.Matches,
  subcommand : String,
) -> @spec_align.SpecAlignConfig {
  let mut config = { ..@spec_align.SpecAlignConfig::default(), subcommand, }
  match matches.values.get("spec-path") {
    Some(values) =>
      if values.length() > 0 {
        config = { ..config, spec_path: values[0] }
      }
    None => ()
  }
  match matches.values.get("impl-path") {
    Some(values) =>
      if values.length() > 0 {
        config = { ..config, impl_path: values[0] }
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
  match matches.values.get("spec-format") {
    Some(values) =>
      if values.length() > 0 {
        config = { ..config, spec_format: values[0] }
      }
    None => ()
  }
  match matches.values.get("algorithm") {
    Some(values) =>
      if values.length() > 0 {
        config = { ..config, algorithm: values[0] }
      }
    None => ()
  }
  match matches.values.get("threshold") {
    Some(values) =>
      if values.length() > 0 {
        config = { ..config, threshold: @common.parse_double(values[0]) }
      }
    None => ()
  }
  match matches.values.get("git-base") {
    Some(values) =>
      if values.length() > 0 {
        config = { ..config, git_base: values[0] }
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
  match matches.values.get("cache-dir") {
    Some(values) =>
      if values.length() > 0 {
        config = { ..config, cache_dir: values[0] }
      }
    None => ()
  }
  match matches.values.get("direction") {
    Some(values) =>
      if values.length() > 0 {
        config = { ..config, direction: values[0] }
      }
    None => ()
  }
  match matches.values.get("agent") {
    Some(values) =>
      if values.length() > 0 {
        config = { ..config, agent: values[0] }
      }
    None => ()
  }
  match matches.values.get("fail-on") {
    Some(values) =>
      if values.length() > 0 {
        config = { ..config, fail_on: values[0] }
      }
    None => ()
  }
  match matches.values.get("mode") {
    Some(values) =>
      if values.length() > 0 {
        config = { ..config, watch_mode: values[0] }
      }
    None => ()
  }
  match matches.values.get("interval") {
    Some(values) =>
      if values.length() > 0 {
        config = { ..config, watch_interval: @common.parse_int(values[0]) }
      }
    None => ()
  }
  match matches.values.get("limit") {
    Some(values) =>
      if values.length() > 0 {
        config = { ..config, watch_limit: @common.parse_int(values[0]) }
      }
    None => ()
  }
  { ..config, incremental: matches.flags.get("incremental").unwrap_or(false) }
}

///|
async fn render_subcommand(config : @spec_align.SpecAlignConfig) -> String? {
  match config.subcommand {
    "diff" =>
      match @spec_align.diff_report_async(config) {
        Some(report) => Some(render_diff(report, config.format))
        None => None
      }
    "trace" =>
      match @spec_align.trace_report_async(config) {
        Some(report) => Some(render_trace(report, config.format))
        None => None
      }
    "suggest" =>
      match @spec_align.suggest_report_async(config) {
        Some(report) => Some(render_suggest(report, config.format))
        None => None
      }
    "status" =>
      match @spec_align.status_report_async(config) {
        Some(report) => Some(render_status(report, config.format))
        None => None
      }
    _ => None
  }
}

///|
async fn render_watch_target(
  config : @spec_align.SpecAlignConfig,
) -> (String, String, Bool)? {
  let target = { ..config, subcommand: config.watch_mode }
  match config.watch_mode {
    "diff" =>
      match @spec_align.diff_report_async(target) {
        Some(report) =>
          Some(
            (
              render_diff(report, target.format),
              report.source_fingerprint,
              false,
            ),
          )
        None => None
      }
    "trace" =>
      match @spec_align.trace_report_async(target) {
        Some(report) =>
          Some(
            (
              render_trace(report, target.format),
              report.source_fingerprint,
              false,
            ),
          )
        None => None
      }
    "suggest" =>
      match @spec_align.suggest_report_async(target) {
        Some(report) =>
          Some(
            (
              render_suggest(report, target.format),
              report.source_fingerprint,
              false,
            ),
          )
        None => None
      }
    "status" =>
      match @spec_align.status_report_async(target) {
        Some(report) =>
          Some(
            (
              render_status(report, target.format),
              report.source_fingerprint,
              report.should_fail,
            ),
          )
        None => None
      }
    _ => None
  }
}

///|
async fn sleep_seconds(seconds : Int) -> Bool {
  let interval = if seconds <= 0 { 1 } else { seconds }
  let (exit_code, _) = @process.collect_stdout(
    "sleep",
    [interval.to_string()][:],
  )
  if exit_code != 0 {
    println("Error: failed to sleep for watch interval.")
    return false
  }
  true
}

///|
async fn run_watch(matches : @argparse.Matches) -> Unit {
  let config = resolve_config(matches, "watch")
  if config.spec_path.length() == 0 || config.impl_path.length() == 0 {
    println("Error: spec-path and impl-path are required.")
    println("")
    println(command().render_help())
    return
  }
  let mut last_fingerprint = ""
  let mut last_probe = ""
  let mut emitted = 0
  while true {
    let probe = match @spec_align.watch_probe_async(config) {
      Some(value) => value
      None => {
        println("No alignment data found.")
        return
      }
    }
    if emitted > 0 && probe == last_probe {
      if !sleep_seconds(config.watch_interval) {
        return
      }
      continue
    }
    last_probe = probe
    match render_watch_target(config) {
      Some((rendered, fingerprint, should_fail)) =>
        if fingerprint != last_fingerprint {
          last_fingerprint = fingerprint
          let heading = "Spec align watch (" + config.watch_mode + ")"
          @common.write_output(config.output, rendered, label=heading)
          emitted += 1
          if config.watch_limit > 0 && emitted >= config.watch_limit {
            if should_fail {
              @parallel.exit(1)
            }
            return
          }
        }
      None => {
        println("No alignment data found.")
        return
      }
    }
    if !sleep_seconds(config.watch_interval) {
      return
    }
  }
}

///|
async fn run_subcommand(
  matches : @argparse.Matches,
  subcommand : String,
) -> Unit {
  let config = resolve_config(matches, subcommand)
  if config.spec_path.length() == 0 || config.impl_path.length() == 0 {
    println("Error: spec-path and impl-path are required.")
    println("")
    println(command().render_help())
    return
  }
  if subcommand == "status" {
    match @spec_align.status_report_async(config) {
      Some(report) => {
        @common.write_output(
          config.output,
          render_status(report, config.format),
          label="Spec align report",
        )
        if report.should_fail {
          @parallel.exit(1)
        }
      }
      None => println("No alignment data found.")
    }
    return
  }
  match render_subcommand(config) {
    Some(rendered) =>
      @common.write_output(config.output, rendered, label="Spec align report")
    None => println("No alignment data found.")
  }
}

///|
pub async fn run_matches(matches : @argparse.Matches) -> Unit {
  guard matches.subcommand is Some((name, sub)) else { return }
  match name {
    "diff" => run_subcommand(sub, "diff")
    "trace" => run_subcommand(sub, "trace")
    "suggest" => run_subcommand(sub, "suggest")
    "status" => run_subcommand(sub, "status")
    "watch" => run_watch(sub)
    _ => ()
  }
}

///|
pub async fn run_to_string(config : @spec_align.SpecAlignConfig) -> String? {
  render_subcommand(config)
}
