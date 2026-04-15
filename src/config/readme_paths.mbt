///|
/// Path constants and helpers for the README documentation system.
/// This is the Single Source of Truth for readme directory/file names.
/// Follow the wiki pattern: constants + path builder functions.

///|
/// Subdirectory name under `.indexion/` for README artifacts.
pub const README_SUBDIR : String = "readme"

///|
/// README template filename.
pub const README_TEMPLATE_FILE : String = "template.md"

///|
/// Documentation configuration filename.
pub const README_DOC_CONFIG_FILE : String = "doc.json"

///|
/// Construct the full path to the readme directory under an indexion dir.
pub fn readme_dir(indexion_dir : String) -> String {
  join_path(indexion_dir, README_SUBDIR)
}

///|
/// Construct the full path to the readme template file.
pub fn readme_template_path(indexion_dir : String) -> String {
  join_path(readme_dir(indexion_dir), README_TEMPLATE_FILE)
}

///|
/// Construct the full path to the readme doc.json config file.
pub fn readme_doc_config_path(indexion_dir : String) -> String {
  join_path(readme_dir(indexion_dir), README_DOC_CONFIG_FILE)
}

///|
/// Relative path to the readme template from the project root.
/// Used in generated config files and user-facing messages.
pub fn readme_template_relative() -> String {
  ".indexion/" + README_SUBDIR + "/" + README_TEMPLATE_FILE
}

///|
/// Relative path to the readme doc.json from the project root.
/// Used in user-facing messages.
pub fn readme_doc_config_relative() -> String {
  ".indexion/" + README_SUBDIR + "/" + README_DOC_CONFIG_FILE
}

///|
/// Subdirectory name under `.indexion/readme/` for static content files.
pub const README_DOCS_SUBDIR : String = "docs"

///|
/// Construct the full path to the docs subdirectory under the readme dir.
pub fn readme_docs_dir(indexion_dir : String) -> String {
  join_path(readme_dir(indexion_dir), README_DOCS_SUBDIR)
}

///|
/// Relative path prefix for doc includes from the readme dir.
/// Used in template {{include:...}} placeholders.
pub fn readme_docs_relative() -> String {
  README_DOCS_SUBDIR
}
