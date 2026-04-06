///|
/// # indexion doc wiki
///
/// Convert wiki between indexion format and external wiki formats (GitHub, GitLab).
///
/// ## Subcommands
///
/// - `export` - Export indexion wiki to an external wiki format
/// - `import` - Import external wiki into indexion format

///|
pub fn command() -> @argparse.Command {
  @argparse.Command(
    "wiki",
    about="Convert wiki between indexion and external formats (github, gitlab)",
    subcommand_required=true,
    subcommands=[export_command(), import_command()],
  )
}

///|
fn export_command() -> @argparse.Command {
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
fn import_command() -> @argparse.Command {
  @argparse.Command(
    "import",
    about="Import external wiki into indexion format",
    flags=[
      @argparse.FlagArg("force", short='f', about="Overwrite existing files"),
    ],
    options=[
      @argparse.OptionArg(
        "format",
        about="Source format: github, gitlab, auto (default: auto)",
        default_values=["auto"],
      ),
      @argparse.OptionArg("input", short='i', about="Input wiki directory"),
      @argparse.OptionArg(
        "output",
        short='o',
        about="Output directory (default: .indexion/wiki)",
        default_values=[".indexion/wiki"],
      ),
      @argparse.OptionArg("title", about="Wiki title for manifest", default_values=[
        "Wiki",
      ]),
    ],
  )
}

///|
pub fn dispatch(matches : @argparse.Matches) -> Unit {
  guard matches.subcommand is Some((name, sub)) else { return }
  match name {
    "export" => run_export(sub)
    "import" => run_import(sub)
    _ => ()
  }
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
fn run_export(matches : @argparse.Matches) -> Unit {
  let format = get_option(matches, "format", "")
  if format.length() == 0 {
    println("Error: --format is required for export.")
    println(
      "Usage: indexion doc wiki export --format=github|gitlab [--input=DIR] [--output=DIR]",
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

///|
fn run_import(matches : @argparse.Matches) -> Unit {
  let format = get_option(matches, "format", "auto")
  let input_dir = get_option(matches, "input", "")
  if input_dir.length() == 0 {
    println("Error: --input is required for import.")
    println(
      "Usage: indexion doc wiki import --input=DIR [--format=github|gitlab|auto]",
    )
    return
  }
  let output_dir = get_option(matches, "output", ".indexion/wiki")
  let output_resolved = if output_dir == ".indexion/wiki" {
    match @config.resolve_project_indexion_dir(".", "wiki") {
      Some(dir) => dir
      None => {
        println("Error: Could not find project root directory.")
        return
      }
    }
  } else {
    output_dir
  }
  let wiki_title = get_option(matches, "title", "Wiki")
  let force = has_flag(matches, "force")
  let data = match format {
    "github" => @wiki_interop.load_github_wiki(input_dir)
    "gitlab" => @wiki_interop.load_gitlab_wiki(input_dir)
    "auto" => @wiki_interop.load_wiki_auto(input_dir)
    _ => {
      println(
        "Error: Unknown format '" + format + "'. Use github, gitlab, or auto.",
      )
      return
    }
  }
  let data = match data {
    Some(d) => d
    None => {
      println("Error: No wiki found at " + input_dir)
      return
    }
  }
  let wiki_mp = @wiki_types.wiki_manifest_path(output_resolved)
  if @fs.path_exists(wiki_mp) && !force {
    println(
      "Error: " +
      @wiki_types.WIKI_MANIFEST_FILE +
      " already exists at " +
      output_resolved +
      "\nUse --force to overwrite.",
    )
    return
  }
  @config.ensure_dir_recursive(output_resolved)
  let manifest = @wiki_interop.generate_manifest_json(data, wiki_title)
  @fs.write_string_to_file(wiki_mp, manifest) catch {
    e => {
      println(
        "Error writing " + @wiki_types.WIKI_MANIFEST_FILE + ": " + e.to_string(),
      )
      return
    }
  }
  let mut count = 0
  for entry in data.pages {
    let (id, page) = (entry.0, entry.1)
    let path = output_resolved + "/" + id + ".md"
    @config.ensure_parent_dir(path)
    @fs.write_string_to_file(path, page.content) catch {
      e => {
        println("Error writing " + id + ".md: " + e.to_string())
        continue
      }
    }
    count += 1
  }
  println(
    "Imported " + count.to_string() + " pages to " + output_resolved + "/",
  )
}
