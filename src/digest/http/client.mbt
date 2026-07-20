// HTTP client wrapper over moonbitlang/async/http.

///|
/// POST JSON request (async)
/// Returns (status_code, response_body_string)
pub async fn post_json(
  url : String,
  body : String,
  headers : Map[String, String],
) -> (Int, String) {
  let (response, body_data) = @async_http.post(url, body, headers~)
  let body_str = body_data.text() catch { _ => "" }
  (response.code, body_str)
}

///|
/// GET request (async)
pub async fn http_get(
  url : String,
  headers : Map[String, String],
) -> (Int, String) {
  let (response, body_data) = @async_http.get(url, headers~)
  let body_str = body_data.text() catch { _ => "" }
  (response.code, body_str)
}
