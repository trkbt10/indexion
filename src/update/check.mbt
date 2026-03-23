///|
/// Result of checking for updates.
pub struct UpdateCheckResult {
  current_version : String
  latest_version : String
  has_update : Bool
}

///|
/// Check the latest release version from GitHub Releases API.
pub async fn check_latest_version() -> String raise UpdateError {
  let url = "https://api.github.com/repos/" + repo + "/releases/latest"
  let headers : Map[String, String] = {
    "Accept": "application/vnd.github.v3+json",
    "User-Agent": "indexion/" + current_version,
  }
  let body_str = @http.fetch_text(url, headers~) catch {
    @http.FetchError(msg) => raise UpdateError::ApiError(msg)
  }
  extract_tag_name(body_str)
}

///|
/// Check for updates and return structured result.
pub async fn check_for_update() -> UpdateCheckResult raise UpdateError {
  let latest = check_latest_version()
  let has_update = compare_versions(latest, current_version) > 0
  { current_version, latest_version: latest, has_update }
}

///|
/// Extract "tag_name" value from GitHub API JSON response.
fn extract_tag_name(json_str : String) -> String raise UpdateError {
  let json = @json.parse(json_str) catch {
    _ => raise UpdateError::ParseError("Failed to parse GitHub API response")
  }
  match json {
    Json::Object(map) =>
      match map.get("tag_name") {
        Some(Json::String(tag)) => tag
        _ =>
          raise UpdateError::ParseError(
            "tag_name not found in GitHub API response",
          )
      }
    _ =>
      raise UpdateError::ParseError("Unexpected JSON structure from GitHub API")
  }
}
