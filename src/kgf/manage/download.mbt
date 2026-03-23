///|
/// GitHub repository for KGF specs.
let kgf_repo : String = "trkbt10/indexion-kgf"

///|
/// Common HTTP headers for GitHub API requests.
fn github_headers() -> Map[String, String] {
  {
    "User-Agent": "indexion-kgf-manager",
    "Accept": "application/vnd.github.v3+json",
  }
}

///|
/// Fetch bytes from a URL (delegates to @http SoT).
async fn fetch(url : String) -> Bytes raise KgfManageError {
  @http.fetch_bytes(url, headers=github_headers()) catch {
    @http.FetchError(msg) => raise KgfManageError::ApiError(msg)
  }
}

///|
/// Fetch text from a URL (delegates to @http SoT).
async fn fetch_text_from(url : String) -> String raise KgfManageError {
  @http.fetch_text(url, headers=github_headers()) catch {
    @http.FetchError(msg) => raise KgfManageError::ApiError(msg)
  }
}

///|
/// Download all kgfs from GitHub and install to the OS-standard data directory.
pub async fn update_kgfs() -> Unit raise KgfManageError {
  println("Fetching KGF specs from GitHub...")
  let url = "https://api.github.com/repos/" + kgf_repo + "/tarball/main"
  let archive_data = fetch(url)
  let tmp_dir = @platform.create_temp_dir("indexion-kgf-update") catch {
    err =>
      raise KgfManageError::InstallError(
        "Failed to create temp directory: " + err.to_string(),
      )
  }
  let archive_path = @config.join_path(tmp_dir, "kgfs.tar.gz")
  @platform.write_bytes_async(archive_path, archive_data) catch {
    err =>
      raise KgfManageError::InstallError(
        "Failed to write archive: " + err.to_string(),
      )
  }
  println("Extracting...")
  @platform.extract_archive(archive_path, tmp_dir) catch {
    err =>
      raise KgfManageError::InstallError(
        "Failed to extract archive: " + err.to_string(),
      )
  }
  // GitHub tarballs extract to a prefix directory like "trkbt10-indexion-kgf-<hash>/"
  match find_extracted_dir(tmp_dir) {
    Some(dir) => install_kgfs_from_dir(dir)
    None =>
      raise KgfManageError::InstallError(
        "Could not find extracted kgfs directory",
      )
  }
  @platform.remove_dir_recursive(tmp_dir) catch {
    _ => ()
  }
}

///|
/// Find the extracted directory inside the temp dir (GitHub tarball prefix).
fn find_extracted_dir(tmp_dir : String) -> String? {
  try {
    let entries = @fs.read_dir(tmp_dir)
    for entry in entries {
      let path = @config.join_path(tmp_dir, entry)
      if @fs.is_dir(path) && not(entry.has_prefix(".")) {
        return Some(path)
      }
    }
    None
  } catch {
    _ => None
  }
}

///|
/// Download and install a single KGF spec by name.
/// Discovers the file path via the GitHub tree API.
pub async fn add_kgf(spec_name : String) -> Unit raise KgfManageError {
  println("Searching for spec: " + spec_name + "...")
  let target_filename = spec_name + ".kgf"
  let tree_url = "https://api.github.com/repos/" +
    kgf_repo +
    "/git/trees/main?recursive=1"
  let body_str = fetch_text_from(tree_url)
  match find_spec_in_tree(body_str, target_filename) {
    Some(path) => {
      println("Found: " + path)
      let raw_url = "https://raw.githubusercontent.com/" +
        kgf_repo +
        "/main/" +
        path
      let content = fetch(raw_url)
      install_single_kgf(path, content)
    }
    None =>
      raise KgfManageError::NotFoundError(
        "Spec '" + spec_name + "' not found in repository",
      )
  }
}

///|
/// Search the GitHub tree API response for a file matching the target filename.
fn find_spec_in_tree(json_str : String, target_filename : String) -> String? {
  let json = @json.parse(json_str) catch { _ => return None }
  match json {
    Object(map) =>
      match map.get("tree") {
        Some(Array(items)) => {
          for item in items {
            match item {
              Object(entry) =>
                match entry.get("path") {
                  Some(String(path)) =>
                    if path.has_suffix("/" + target_filename) ||
                      path == target_filename {
                      return Some(path)
                    }
                  _ => ()
                }
              _ => ()
            }
          }
          None
        }
        _ => None
      }
    _ => None
  }
}
