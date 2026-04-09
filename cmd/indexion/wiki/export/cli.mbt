///|
/// # indexion wiki export
///
/// Export indexion wiki to an external wiki format (GitHub, GitLab).

///|
pub fn command() -> @argparse.Command {
  @argparse.Command(
    "export",
    about="Export indexion wiki to external format",
    flags=[
      @argparse.FlagArg("force", short='f', about="Overwrite existing files"),
    ],
    options=[
      @argparse.OptionArg("format", about="Target format: github, gitlab"),
      @argparse.OptionArg(
        "input",
        short='i',
        about="Input wiki directory (default: .indexion/wiki)",
        default_values=[".indexion/wiki"],
      ),
      @argparse.OptionArg("output", short='o', about="Output directory"),
    ],
  )
}

///|
fn get_option(
  matches : @argparse.Matches,
  key : String,
  default : String,
) -> String {
  match matches.values.get(key) {
    Some(arr) => if arr.length() > 0 { arr[0] } else { default }
    _ => default
  }
}

///|
fn has_flag(matches : @argparse.Matches, key : String) -> Bool {
  match matches.flags.get(key) {
    Some(v) => v
    _ => false
  }
}

///|
pub fn run_matches(matches : @argparse.Matches) -> Unit {
  let format = get_option(matches, "format", "")
  if format.length() == 0 {
    println("Error: --format is required for export.")
    println(
      "Usage: indexion wiki export --format=github|gitlab [--input=DIR] [--output=DIR]",
    )
    return
  }
  let input_dir = get_option(matches, "input", ".indexion/wiki")
  let input_resolved = if input_dir == ".indexion/wiki" {
    match @config.resolve_project_indexion_dir(".", "wiki") {
      Some(dir) => dir
      None => {
        println("Error: Could not find project root directory.")
        return
      }
    }
  } else {
    input_dir
  }
  let output_dir = get_option(matches, "output", format + "-wiki-export")
  let force = has_flag(matches, "force")
  // Load wiki (auto-detect input format)
  let data = match @wiki_interop.load_wiki_auto(input_resolved) {
    Some(d) => d
    None => {
      println("Error: No wiki found at " + input_resolved)
      return
    }
  }
  if @fs.path_exists(output_dir) && !force {
    println(
      "Error: Output directory already exists: " +
      output_dir +
      "\nUse --force to overwrite.",
    )
    return
  }
  let files = match format {
    "github" => @wiki_interop.export_github_wiki(data)
    "gitlab" => @wiki_interop.export_gitlab_wiki(data)
    _ => {
      println("Error: Unknown format '" + format + "'. Use github or gitlab.")
      return
    }
  }
  @config.ensure_dir_recursive(output_dir)
  let mut count = 0
  for file in files {
    let (filename, content) = file
    let path = output_dir + "/" + filename
    // Ensure parent directory exists (for nested GitLab pages)
    @config.ensure_parent_dir(path)
    @fs.write_string_to_file(path, content) catch {
      e => {
        println("Error writing " + filename + ": " + e.to_string())
        continue
      }
    }
    count += 1
  }
  println(
    "Exported " +
    count.to_string() +
    " files (" +
    format +
    " format) to " +
    output_dir +
    "/",
  )
}
