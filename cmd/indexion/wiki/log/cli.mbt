///|
/// # indexion wiki log
///
/// Display the wiki operation log.

///|
pub fn command() -> @argparse.Command {
  @argparse.Command(
    "log",
    about="Display wiki operation log",
    flags=[
      @argparse.FlagArg("json", about="Output as JSON"),
    ],
    options=[
      @argparse.OptionArg(
        "tail",
        about="Show last N entries (default: all)",
        default_values=[],
      ),
      @argparse.OptionArg(
        "wiki-dir",
        about="Wiki directory",
        default_values=[".indexion/wiki"],
      ),
    ],
  )
}

///|
pub fn run_matches(matches : @argparse.Matches) -> Unit {
  let wiki_dir = match matches.values.get("wiki-dir") {
    Some(arr) => if arr.length() > 0 { arr[0] } else { ".indexion/wiki" }
    _ => ".indexion/wiki"
  }
  let wiki_dir_resolved = if wiki_dir == ".indexion/wiki" {
    match @config.resolve_project_indexion_dir(".", "wiki") {
      Some(dir) => dir
      None => {
        println("Error: Could not find project root directory.")
        return
      }
    }
  } else {
    wiki_dir
  }
  let as_json = match matches.flags.get("json") {
    Some(v) => v
    _ => false
  }
  let tail_n = match matches.values.get("tail") {
    Some(arr) =>
      if arr.length() > 0 {
        @common.parse_int(arr[0])
      } else {
        0
      }
    _ => 0
  }
  let log = @wiki_log.WikiLog::load(wiki_dir_resolved)
  if log.length() == 0 {
    println("No wiki log entries found.")
    return
  }
  let entries = if tail_n > 0 {
    log.tail(tail_n)
  } else {
    log.entries
  }
  if as_json {
    let json_arr : Array[Json] = []
    for entry in entries {
      json_arr.push(entry.to_json())
    }
    println(Json::array(json_arr).stringify(indent=2))
  } else {
    for entry in entries {
      println(entry.to_display())
    }
  }
}
