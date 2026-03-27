///|
/// Maximum number of HTTP redirects to follow.
let max_redirects : Int = 5

///|
/// HTTP fetch error.
pub suberror FetchError {
  FetchError(String)
}

///|
/// Fetch bytes from a URL, following HTTP 3xx redirects.
pub async fn fetch_bytes(
  url : String,
  headers~ : Map[String, String],
) -> Bytes raise FetchError {
  let mut current_url = url
  for i = 0; i < max_redirects; i = i + 1 {
    let (response, body_data) = @mhttp.get(current_url, headers~) catch {
      err => raise FetchError(err.to_string())
    }
    if response.code == 200 {
      return body_data.binary()
    }
    if response.code >= 300 && response.code < 400 {
      match response.headers.get("location") {
        Some(location) => current_url = location
        None =>
          raise FetchError("Redirect without Location header: " + current_url)
      }
      continue
    }
    raise FetchError("HTTP " + response.code.to_string() + ": " + current_url)
  }
  raise FetchError("Too many redirects: " + url)
}

///|
/// Fetch text from a URL, following HTTP 3xx redirects.
pub async fn fetch_text(
  url : String,
  headers~ : Map[String, String],
) -> String raise FetchError {
  let mut current_url = url
  for i = 0; i < max_redirects; i = i + 1 {
    let (response, body_data) = @mhttp.get(current_url, headers~) catch {
      err => raise FetchError(err.to_string())
    }
    if response.code == 200 {
      return body_data.text() catch {
        _ => raise FetchError("Failed to decode response as text")
      }
    }
    if response.code >= 300 && response.code < 400 {
      match response.headers.get("location") {
        Some(location) => current_url = location
        None =>
          raise FetchError("Redirect without Location header: " + current_url)
      }
      continue
    }
    raise FetchError("HTTP " + response.code.to_string() + ": " + current_url)
  }
  raise FetchError("Too many redirects: " + url)
}
