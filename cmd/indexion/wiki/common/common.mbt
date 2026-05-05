///|
/// Shared CLI helpers for commands that operate on the project wiki.

///|
pub const WIKI_DIR_ARG : String = "wiki-dir"

///|
pub const PROJECT_ROOT_ERROR : String = "Error: Could not find project root directory."

///|
pub fn wiki_dir_arg(matches : @argparse.Matches) -> String {
  @cli_common.get_option(
    matches,
    WIKI_DIR_ARG,
    @wiki_workspace.DEFAULT_WIKI_DIR,
  )
}

///|
pub fn resolve_wiki_dir_arg(matches : @argparse.Matches) -> String? {
  @wiki_workspace.resolve_wiki_dir(wiki_dir_arg(matches))
}

///|
pub fn print_project_root_error() -> Unit {
  println(PROJECT_ROOT_ERROR)
}
