///|
/// # indexion wiki index
///
/// Generate a category-based index page for the wiki.

///|
pub fn command() -> @argparse.Command {
  @argparse.Command(
    "index",
    about="Generate wiki index page (category catalog + hub pages)",
    flags=[
      @argparse.FlagArg(
        "dry-run",
        about="Output to stdout instead of writing to wiki",
      ),
    ],
    options=[
      @argparse.OptionArg(
        "wiki-dir",
        about="Wiki directory",
        default_values=[".indexion/wiki"],
      ),
      @argparse.OptionArg("output", short='o', about="Output file path"),
      @argparse.OptionArg("specs-dir", about=@help.specs_dir, default_values=[
        "kgfs",
      ]),
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
  let output = match matches.values.get("output") {
    Some(arr) => if arr.length() > 0 { arr[0] } else { "" }
    _ => ""
  }
  let specs_dir = match matches.values.get("specs-dir") {
    Some(arr) => if arr.length() > 0 { arr[0] } else { "kgfs" }
    _ => "kgfs"
  }
  let dry_run = match matches.flags.get("dry-run") {
    Some(v) => v
    _ => false
  }
  // Load wiki
  let registry = @kgf_features.load_registry(
    specs_dir=specs_dir,
    target_dir=".",
  )
  let wiki = match @wiki_reader.load_wiki(wiki_dir_resolved, registry~) {
    Some(w) => w
    None => {
      println("Error: No wiki found at " + wiki_dir_resolved)
      return
    }
  }
  // Load log for recent changes
  let log = @wiki_log.WikiLog::load(wiki_dir_resolved)
  let log_opt : @wiki_log.WikiLog? = if log.length() > 0 {
    Some(log)
  } else {
    None
  }
  // Build index
  let index = @wiki_index.build_index(wiki, log_opt)
  let content = index.to_markdown()
  if dry_run || output.length() > 0 {
    @common.write_output(output, content, label="Wiki index")
  } else {
    // Write index.md to wiki directory
    let index_path = wiki_dir_resolved + "/index.md"
    @fs.write_string_to_file(index_path, content) catch {
      e => {
        println("Error writing index.md: " + e.to_string())
        return
      }
    }
    println(
      "Generated index.md with " +
      index.total_pages.to_string() +
      " pages in " +
      index.categories.length().to_string() +
      " categories",
    )
  }
  // Log the operation
  let op_log = @wiki_log.WikiLog::load(wiki_dir_resolved)
  op_log.append(
    @wiki_log.WikiLogEntry::new(
      timestamp=@env.now(),
      operation="index",
      actor="indexion",
      summary="Generated index with " +
        index.categories.length().to_string() +
        " categories, " +
        index.hub_pages.length().to_string() +
        " hub pages",
    ),
  )
  op_log.save(wiki_dir_resolved)
}
