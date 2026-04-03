///|
/// # GitHub Wiki Backend
///
/// GitHub Wiki format: Home.md, _Sidebar.md, [[wiki links]], flat file structure.

///|
fn github_config() -> WikiBackendConfig {
  WikiBackendConfig::{
    spec_name: "github-wiki",
    file_to_id: slug_to_id,
    title_to_name: fn(title) { title_to_slug(title, lowercase=false) },
    name_to_title: slug_to_title,
    recursive: false,
  }
}

///|
pub fn load_github_wiki(wiki_dir : String) -> @types.WikiData? {
  load_external_wiki(wiki_dir, github_config())
}

///|
pub fn export_github_wiki(data : @types.WikiData) -> Array[(String, String)] {
  export_external_wiki(data, github_config())
}
