///|
/// Build the `indexion agent orient` command and translate argparse matches.
fn orient_command() -> @argparse.Command {
  @argparse.Command(
    "orient",
    about="Build a pre-edit structure brief for coding agents",
    flags=[
      @argparse.FlagArg::new(
        "no-update",
        about="Use the saved orientation map without refreshing changed files",
      ),
    ],
    options=[
      @argparse.OptionArg("specs-dir", about=@help.specs_dir, default_values=[
        "kgfs",
      ]),
      @argparse.OptionArg::new(
        "cache-dir",
        about="Directory for the prebuilt agent orientation map",
        default_values=[".indexion/cache/agent"],
      ),
      @argparse.OptionArg::new(
        "wiki-dir",
        about="Wiki directory used as curated project knowledge",
        default_values=[".indexion/wiki"],
      ),
      @argparse.OptionArg::new(
        "task",
        about="Task description text. Use --task-file for longer prompts.",
        default_values=[""],
      ),
      @argparse.OptionArg::new(
        "task-file",
        about="Path to a file containing the task description.",
        default_values=[""],
      ),
      @argparse.OptionArg::new("format", about="Output format: md | json", default_values=[
        "md",
      ]),
      @argparse.OptionArg::new(
        "output",
        about="Output file path (- or empty = stdout)",
        default_values=[""],
      ),
      @argparse.OptionArg::new("limit", about="Maximum entries per section", default_values=[
        "12",
      ]),
    ],
    positionals=[
      @argparse.PositionArg(
        "paths",
        num_args=@argparse.ValueRange(lower=0),
        about="Input files or directories",
      ),
    ],
  )
}

///|
extern "c" fn agent_orient_native_exit(code : Int) = "exit"

///|
fn agent_orient_exit_with_code(code : Int) -> Unit {
  agent_orient_native_exit(code)
  panic()
}

///|
fn agent_orient_fail(message : String) -> Unit {
  println("error: " + message)
  agent_orient_exit_with_code(1)
}

///|
async fn run_orient(matches : @argparse.Matches) -> Unit {
  let config = orient_config_from_matches(matches)
  let report = @agent_orient.orient_agent(config) catch {
    @cache.WriterAlreadyActive(path) => {
      agent_orient_fail(
        "agent orient: another writer holds the cache lock at `" +
        path +
        "`. Re-run after it finishes or pass --no-update.",
      )
      return
    }
    @cache.WriterLockStorageError(message) => {
      agent_orient_fail("agent orient: writer lock failed: " + message)
      return
    }
    @cache.Unavailable(message) => {
      agent_orient_fail("agent orient: cache unavailable: " + message)
      return
    }
    @cache.StorageFailure(message) => {
      agent_orient_fail("agent orient: cache storage failure: " + message)
      return
    }
    @cache.ReplayFailure(message) => {
      agent_orient_fail("agent orient: cache replay failure: " + message)
      return
    }
    @cache.DatabaseFailure(message) => {
      agent_orient_fail("agent orient: cache database failure: " + message)
      return
    }
    @cache.CheckpointFailure(message) => {
      agent_orient_fail("agent orient: cache checkpoint failure: " + message)
      return
    }
    @cache.RecordFailure(message) => {
      agent_orient_fail("agent orient: cache record failure: " + message)
      return
    }
    err => {
      agent_orient_fail("agent orient: " + err.to_string())
      return
    }
  }
  let rendered = match @common.arg_str(matches, "format", "md") {
    "json" => report.to_json().stringify(indent=2) + "\n"
    _ => render_markdown(report)
  }
  @common.write_output(
    @common.arg_str(matches, "output", ""),
    rendered,
    label="Agent orientation brief",
  )
}

///|
fn orient_config_from_matches(
  matches : @argparse.Matches,
) -> @agent_orient.AgentOrientConfig {
  let base = @agent_orient.AgentOrientConfig::default()
  {
    task: task_from_matches(matches),
    paths: match matches.values.get("paths") {
      Some(arr) if arr.length() > 0 => arr
      _ => base.paths
    },
    specs_dir: @common.arg_str(matches, "specs-dir", base.specs_dir),
    cache_dir: @common.arg_str(matches, "cache-dir", base.cache_dir),
    wiki_dir: @common.arg_str(matches, "wiki-dir", base.wiki_dir),
    no_update: @common.arg_flag(matches, "no-update", base.no_update),
    limit: @common.arg_int(matches, "limit", base.limit),
  }
}

///|
fn task_from_matches(matches : @argparse.Matches) -> String {
  let task_file = @common.arg_str(matches, "task-file", "")
  if task_file.length() > 0 {
    return @fs.read_file_to_string(task_file) catch { _ => "" }
  }
  @common.arg_str(matches, "task", "")
}
