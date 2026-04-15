// HTTP client wrapper using mizchi/x/http

///|
/// Extract a human-readable message from an HttpError.
pub fn http_error_message(err : @mhttp.HttpError) -> String {
  match err {
    NetworkError(msg) => msg
    InvalidUrl(msg) => msg
    TimeoutError => "timeout"
    NotSupported => "not supported"
  }
}

///|
/// POST JSON request (async)
/// Returns (status_code, response_body_string)
pub async fn post_json(
  url : String,
  body : String,
  headers : Map[String, String],
) -> (Int, String) raise @mhttp.HttpError {
  let (response, body_data) = @mhttp.post(url, body, headers~)
  let body_str = body_data.text() catch { _ => "" }
  (response.code, body_str)
}

///|
/// GET request (async)
pub async fn http_get(
  url : String,
  headers : Map[String, String],
) -> (Int, String) raise @mhttp.HttpError {
  let (response, body_data) = @mhttp.get(url, headers~)
  let body_str = body_data.text() catch { _ => "" }
  (response.code, body_str)
}
