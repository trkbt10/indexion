///|
/// Extract a human-readable message from an HttpError.
fn http_error_message(err : @mhttp.HttpError) -> String {
  match err {
    NetworkError(msg) => msg
    InvalidUrl(msg) => msg
    TimeoutError => "timeout"
    NotSupported => "not supported"
  }
}

///|
/// Maximum number of HTTP redirects to follow.
let max_redirects : Int = 5

///|
/// HTTP fetch error.
pub suberror FetchError {
  FetchError(String)
}

///|
/// Resolve the final URL after following HTTP 3xx redirects.
/// Returns the final URL that returned a non-redirect response.
async fn resolve_redirect_url(
  url : String,
  headers : Map[String, String],
) -> String raise FetchError {
  let mut current_url = url
  for i = 0; i < max_redirects; i = i + 1 {
    let req_headers = copy_headers(headers)
    let (response, _) = @mhttp.get(current_url, headers=req_headers) catch {
      err => raise FetchError(http_error_message(err))
    }
    if response.code >= 200 && response.code < 300 {
      return current_url
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
/// Fetch bytes from a URL, following HTTP 3xx redirects.
pub async fn fetch_bytes(
  url : String,
  headers~ : Map[String, String],
) -> Bytes raise FetchError {
  let final_url = resolve_redirect_url(url, headers)
  let req_headers = copy_headers(headers)
  let (_, body_data) = @mhttp.get(final_url, headers=req_headers) catch {
    err => raise FetchError(http_error_message(err))
  }
  body_data.binary()
}

///|
/// Fetch text from a URL, following HTTP 3xx redirects.
pub async fn fetch_text(
  url : String,
  headers~ : Map[String, String],
) -> String raise FetchError {
  let final_url = resolve_redirect_url(url, headers)
  let req_headers = copy_headers(headers)
  let (_, body_data) = @mhttp.get(final_url, headers=req_headers) catch {
    err => raise FetchError(http_error_message(err))
  }
  body_data.text() catch {
    _ => raise FetchError("Failed to decode response as text")
  }
}

///|
/// Copy a headers map to avoid ownership issues across redirect requests.
fn copy_headers(headers : Map[String, String]) -> Map[String, String] {
  let result : Map[String, String] = {}
  for k, v in headers {
    result[k] = v
  }
  result
}
