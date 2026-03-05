// HTTP client wrapper using mizchi/x/http

///|
/// POST JSON request (async)
/// Returns (status_code, response_body_string)
pub async fn post_json(
  url : String,
  body : String,
  headers : Map[String, String],
) -> (Int, String) raise @mhttp.HttpError {
  let (response, body_data) = @mhttp.post(url, body, headers~)
  let body_bytes = body_data.binary()
  let body_str = bytes_to_string(body_bytes)
  (response.code, body_str)
}

///|
/// GET request (async)
pub async fn http_get(
  url : String,
  headers : Map[String, String],
) -> (Int, String) raise @mhttp.HttpError {
  let (response, body_data) = @mhttp.get(url, headers~)
  let body_bytes = body_data.binary()
  let body_str = bytes_to_string(body_bytes)
  (response.code, body_str)
}

///|
/// Convert bytes to string (UTF-8)
fn bytes_to_string(bytes : Bytes) -> String {
  let chars : Array[Char] = []
  for i = 0; i < bytes.length(); i = i + 1 {
    chars.push(bytes[i].to_int().unsafe_to_char())
  }
  String::from_array(chars)
}
