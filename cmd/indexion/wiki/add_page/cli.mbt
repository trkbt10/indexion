///|
/// # indexion wiki add-page
///
/// Add a new page to the wiki manifest and write the .md file.

///|
pub fn command() -> @argparse.Command {
  @argparse.Command(
    "add-page",
    about="Add a new page to the wiki",
    options=[
      @argparse.OptionArg("id", about="Page ID (slug, e.g. 'my-page')"),
      @argparse.OptionArg("title", about="Page title"),
      @argparse.OptionArg(
        "content",
        about="Path to .md file with page content",
      ),
      @argparse.OptionArg("parent", about="Parent page ID"),
      @argparse.OptionArg("sources", about="Comma-separated source file paths"),
      @argparse.OptionArg(
        "provenance",
        about="Content provenance: extracted, synthesized, manual",
      ),
      @argparse.OptionArg(
        "actor",
        about="Who is adding: indexion, agent:<name>, user",
        default_values=["user"],
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
  let id = match matches.values.get("id") {
    Some(arr) => if arr.length() > 0 { arr[0] } else { "" }
    _ => ""
  }
  let title = match matches.values.get("title") {
    Some(arr) => if arr.length() > 0 { arr[0] } else { "" }
    _ => ""
  }
  let content_path = match matches.values.get("content") {
    Some(arr) => if arr.length() > 0 { arr[0] } else { "" }
    _ => ""
  }
  if id.length() == 0 || title.length() == 0 || content_path.length() == 0 {
    println("Error: --id, --title, and --content are required.")
    println(
      "Usage: indexion wiki add-page --id=<id> --title=<title> --content=<file.md>",
    )
    return
  }
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
  let parent = match matches.values.get("parent") {
    Some(arr) => if arr.length() > 0 { Some(arr[0]) } else { None }
    _ => None
  }
  let sources_str = match matches.values.get("sources") {
    Some(arr) => if arr.length() > 0 { arr[0] } else { "" }
    _ => ""
  }
  let provenance : String? = match matches.values.get("provenance") {
    Some(arr) => if arr.length() > 0 { Some(arr[0]) } else { None }
    _ => None
  }
  let actor = match matches.values.get("actor") {
    Some(arr) => if arr.length() > 0 { arr[0] } else { "user" }
    _ => "user"
  }
  // Read content
  let content = try {
    @fs.read_file_to_string(content_path)
  } catch {
    e => {
      println("Error reading content file: " + e.to_string())
      return
    }
  }
  // Load existing manifest
  let manifest_path = @wiki_types.wiki_manifest_path(wiki_dir_resolved)
  if !@fs.path_exists(manifest_path) {
    println("Error: No wiki manifest found at " + manifest_path)
    return
  }
  let manifest_content = try {
    @fs.read_file_to_string(manifest_path)
  } catch {
    e => {
      println("Error reading manifest: " + e.to_string())
      return
    }
  }
  let manifest_json = try {
    @json.parse(manifest_content)
  } catch {
    e => {
      println("Error parsing manifest: " + e.to_string())
      return
    }
  }
  let manifest : @wiki_types.WikiManifest = try {
    @json.from_json!(manifest_json)
  } catch {
    e => {
      println("Error decoding manifest: " + e.to_string())
      return
    }
  }
  // Check for duplicate ID
  for mp in manifest.pages {
    if mp.id == id {
      println("Error: Page with ID '" + id + "' already exists.")
      return
    }
  }
  // Parse sources
  let sources : Array[String] = if sources_str.length() > 0 {
    @common.parse_comma_list(sources_str)
  } else {
    []
  }
  // Create new manifest page
  let new_page = @wiki_types.ManifestPage::new(
    id=id,
    title=title,
    file=id + ".md",
    sources=sources,
    provenance=provenance,
    last_actor=Some(actor),
  )
  // Build updated pages array
  let new_pages : Array[@wiki_types.ManifestPage] = []
  for mp in manifest.pages {
    // If this page is the parent, add the new page ID as a child
    if parent is Some(pid) && mp.id == pid {
      let updated_children : Array[String] = mp.children.copy()
      updated_children.push(id)
      new_pages.push(mp.with_updates(children=updated_children))
    } else {
      new_pages.push(mp)
    }
  }
  new_pages.push(new_page)
  // Write updated manifest
  let new_manifest = @wiki_types.WikiManifest::new(
    title=manifest.title,
    pages=new_pages,
  )
  let new_manifest_json = new_manifest
    .to_json()
    .stringify(indent=2)
  @fs.write_string_to_file(manifest_path, new_manifest_json) catch {
    e => {
      println("Error writing manifest: " + e.to_string())
      return
    }
  }
  // Write page content
  let page_path = wiki_dir_resolved + "/" + id + ".md"
  @fs.write_string_to_file(page_path, content) catch {
    e => {
      println("Error writing page file: " + e.to_string())
      return
    }
  }
  println("Added page '" + title + "' (" + id + ")")
  // Log the operation
  let log = @wiki_log.WikiLog::load(wiki_dir_resolved)
  log.append(
    @wiki_log.WikiLogEntry::new(
      timestamp=@env.now(),
      operation="add-page",
      actor=actor,
      summary="Added page: " + title,
      affected_pages=[id],
    ),
  )
  log.save(wiki_dir_resolved)
}
