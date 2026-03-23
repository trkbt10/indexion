///|
/// Determine the platform asset name for the current OS, delegating to config SoT.
pub fn get_platform_asset() -> String raise UpdateError {
  match @config.get_platform_asset_name() {
    Some(name) => name
    None => raise UpdateError::PlatformError("Unsupported platform")
  }
}

///|
/// Build the download URL for a release asset.
pub fn build_download_url(version : String, asset : String) -> String {
  "https://github.com/" +
  repo +
  "/releases/download/" +
  version +
  "/" +
  asset +
  @config.get_archive_extension()
}

///|
/// Build the checksum URL for a release asset.
pub fn build_checksum_url(version : String, asset : String) -> String {
  build_download_url(version, asset) + ".sha256"
}

///|
/// Common HTTP headers for update requests.
fn update_headers() -> Map[String, String] {
  { "User-Agent": "indexion/" + current_version }
}

///|
/// Download a file from URL and return its content as Bytes (delegates to @http SoT).
pub async fn download_bytes(url : String) -> Bytes raise UpdateError {
  @http.fetch_bytes(url, headers=update_headers()) catch {
    @http.FetchError(msg) => raise UpdateError::DownloadError(msg)
  }
}

///|
/// Download a text file from URL (delegates to @http SoT).
pub async fn download_text(url : String) -> String raise UpdateError {
  @http.fetch_text(url, headers=update_headers()) catch {
    @http.FetchError(msg) => raise UpdateError::DownloadError(msg)
  }
}

///|
/// Verify SHA-256 checksum of data against expected hash.
pub fn verify_checksum(
  data : Bytes,
  expected_hex : String,
) -> Unit raise UpdateError {
  let hash = @crypto.sha256(data)
  let actual_hex = @crypto.bytes_to_hex_string(hash)
  let expected_trimmed = extract_hash_from_checksum(expected_hex)
  if actual_hex != expected_trimmed {
    raise UpdateError::ChecksumError(
      "Checksum mismatch: expected " + expected_trimmed + ", got " + actual_hex,
    )
  }
}

///|
/// Extract the hash from a checksum file line (first whitespace-delimited field).
fn extract_hash_from_checksum(line : String) -> String {
  let trimmed = trim_string(line)
  let chars = trimmed.to_array()
  let result : Array[Char] = []
  for ch in chars {
    if ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r' {
      break
    }
    result.push(ch)
  }
  String::from_array(result)
}

///|
fn trim_string(s : String) -> String {
  let chars = s.to_array()
  let mut start = 0
  let mut end = chars.length()
  while start < end &&
        (
          chars[start] == ' ' ||
          chars[start] == '\t' ||
          chars[start] == '\n' ||
          chars[start] == '\r'
        ) {
    start += 1
  }
  while end > start &&
        (
          chars[end - 1] == ' ' ||
          chars[end - 1] == '\t' ||
          chars[end - 1] == '\n' ||
          chars[end - 1] == '\r'
        ) {
    end -= 1
  }
  let result : Array[Char] = []
  for i in start..<end {
    result.push(chars[i])
  }
  String::from_array(result)
}
