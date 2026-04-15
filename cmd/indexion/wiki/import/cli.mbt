///|
/// # indexion wiki import
///
/// Import external wiki into indexion format.

///|
pub fn command() -> @argparse.Command {
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
pub fn run_matches(matches : @argparse.Matches) -> Unit {
  let format = @common.get_option(matches, "format", "auto")
  let input_dir = @common.get_option(matches, "input", "")
  if input_dir.length() == 0 {
    println("Error: --input is required for import.")
    println(
      "Usage: indexion wiki import --input=DIR [--format=github|gitlab|auto]",
    )
    return
  }
  let output_resolved = match
    @common.resolve_wiki_dir(
      @common.get_option(matches, "output", ".indexion/wiki"),
    ) {
    Some(dir) => dir
    None => {
      println("Error: Could not find project root directory.")
      return
    }
  }
  let wiki_title = @common.get_option(matches, "title", "Wiki")
  let force = @common.get_flag(matches, "force")
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
    @fs.IOError(msg) => {
      println("Error writing " + @wiki_types.WIKI_MANIFEST_FILE + ": " + msg)
      return
    }
  }
  let mut count = 0
  for entry in data.pages {
    let (id, page) = (entry.0, entry.1)
    let path = output_resolved + "/" + id + ".md"
    @config.ensure_parent_dir(path)
    @fs.write_string_to_file(path, page.content) catch {
      @fs.IOError(msg) => {
        println("Error writing " + id + ".md: " + msg)
        continue
      }
    }
    count += 1
  }
  println(
    "Imported " + count.to_string() + " pages to " + output_resolved + "/",
  )
}
