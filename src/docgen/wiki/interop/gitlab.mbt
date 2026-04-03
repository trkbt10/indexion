///|
/// # GitLab Wiki Backend
///
/// GitLab Wiki format: home.md (lowercase), _sidebar.md, [[wiki links]],
/// nested directory structure supported.

///|
fn gitlab_config() -> WikiBackendConfig {
  WikiBackendConfig::{
    spec_name: "gitlab-wiki",
    file_to_id: fn(slug) { slug },
    title_to_name: fn(title) { title_to_slug(title, lowercase=true) },
    name_to_title: slug_to_title,
    recursive: true,
  }
}

///|
pub fn load_gitlab_wiki(wiki_dir : String) -> @types.WikiData? {
  load_external_wiki(wiki_dir, gitlab_config())
}

///|
pub fn export_gitlab_wiki(data : @types.WikiData) -> Array[(String, String)] {
  export_external_wiki(data, gitlab_config())
}
