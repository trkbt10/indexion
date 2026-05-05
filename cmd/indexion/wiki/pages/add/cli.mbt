///|
/// # indexion wiki pages add
///
/// Add a new page to the wiki manifest and write the .md file.

///|
pub fn command() -> @argparse.Command {
  @argparse.Command("add", about="Add a new page to the wiki", options=[
    @argparse.OptionArg("id", about="Page ID (slug, e.g. 'my-page')"),
    @argparse.OptionArg("title", about="Page title"),
    @argparse.OptionArg("content", about="Path to .md file with page content"),
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
    @argparse.OptionArg("wiki-dir", about="Wiki directory", default_values=[
      @wiki_workspace.DEFAULT_WIKI_DIR,
    ]),
  ])
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
      "Usage: indexion wiki pages add --id=<id> --title=<title> --content=<file.md>",
    )
    return
  }
  let wiki_dir_resolved = match @wiki_cli_common.resolve_wiki_dir_arg(matches) {
    Some(dir) => dir
    None => {
      @wiki_cli_common.print_project_root_error()
      return
    }
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
  let content = @fs.read_file_to_string(content_path) catch {
    @fs.IOError(msg) => {
      println("Error reading content file: " + msg)
      return
    }
  }
  let manifest = match @wiki_manifest.load_manifest(wiki_dir_resolved) {
    Some(m) => m
    None => return
  }
  // Check for duplicate ID
  for mp in manifest.pages {
    if mp.id == id {
      println("Error: Page with ID '" + id + "' already exists.")
      return
    }
  }
  let sources : Array[String] = if sources_str.length() > 0 {
    @common.parse_comma_list(sources_str)
  } else {
    []
  }
  let new_page = @wiki_types.ManifestPage::new(
    id~,
    title~,
    file=id + ".md",
    sources~,
    provenance~,
    last_actor=Some(actor),
  )
  // Build updated pages array, wiring parent → child link
  let new_pages : Array[@wiki_types.ManifestPage] = []
  for mp in manifest.pages {
    if parent is Some(pid) && mp.id == pid {
      let updated_children : Array[String] = mp.children.copy()
      updated_children.push(id)
      new_pages.push(mp.with_updates(children=updated_children))
    } else {
      new_pages.push(mp)
    }
  }
  new_pages.push(new_page)
  let new_manifest = @wiki_types.WikiManifest::new(
    title=manifest.title,
    pages=new_pages,
  )
  if !@wiki_manifest.write_page(wiki_dir_resolved, new_manifest, id, content) {
    return
  }
  println("Added page '" + title + "' (" + id + ")")
  let log = @wiki_log.WikiLog::load(wiki_dir_resolved)
  log.append(
    @wiki_log.WikiLogEntry::new(
      timestamp=@env.now(),
      operation="pages add",
      actor~,
      summary="Added page: " + title,
      affected_pages=[id],
    ),
  )
  log.save(wiki_dir_resolved)
}
