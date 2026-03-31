// OpenAI-compatible Embedding API client (native, async)

///|
/// Embedding error
pub(all) suberror EmbedError {
  ParseError(String)
  ApiError(Int, String)
  NoResult
}

///|
/// OpenAI-compatible API configuration
pub(all) struct OpenAIConfig {
  api_key : String
  model : String
  base_url : String
} derive(Eq, Show)

///|
/// Default config for text-embedding-3-small (1536 dims)
pub fn OpenAIConfig::default(api_key : String) -> OpenAIConfig {
  {
    api_key,
    model: @config.DEFAULT_EMBEDDING_MODEL,
    base_url: @config.DEFAULT_API_BASE_URL,
  }
}

///|
/// Build request body JSON using @json library.
fn build_request_body(texts : Array[String], model : String) -> String {
  let input = Json::array(texts.map(Json::string))
  let request = Json::object({ "input": input, "model": Json::string(model) })
  request.stringify()
}

///|
/// Parse embedding response JSON.
/// Expected format: { "data": [{ "index": 0, "embedding": [...] }, ...] }
fn parse_embedding_response(
  json_str : String,
) -> Array[Array[Double]] raise EmbedError {
  let json = @json.parse(json_str) catch {
    _ => raise ParseError("Invalid JSON response")
  }
  guard json is { "data": Array(data), .. } else {
    raise ParseError("Missing 'data' array in response")
  }
  let indexed : Array[(Int, Array[Double])] = []
  for item in data {
    guard item is { "embedding": Array(emb_arr), "index": Number(idx, ..), .. } else {
      continue
    }
    let vec : Array[Double] = []
    for v in emb_arr {
      guard v is Number(n, ..) else { continue }
      vec.push(n)
    }
    indexed.push((idx.to_int(), vec))
  }
  if indexed.is_empty() {
    raise ParseError("No embeddings in response")
  }
  indexed.sort_by(fn(a, b) { a.0.compare(b.0) })
  indexed.map(fn(pair) { pair.1 })
}

///|
/// Get embeddings for texts (async, batch)
pub async fn get_embeddings(
  config : OpenAIConfig,
  texts : Array[String],
) -> Array[Array[Double]] raise EmbedError {
  let headers : Map[String, String] = {}
  headers.set("Authorization", "Bearer " + config.api_key)
  headers.set("Content-Type", "application/json")
  let body = build_request_body(texts, config.model)
  let (status, response_body) = @http.post_json(config.base_url, body, headers) catch {
    err => raise ApiError(0, err.to_string())
  }
  if status != 200 {
    raise ApiError(status, response_body)
  }
  parse_embedding_response(response_body)
}

///|
/// Get embedding for single text (async)
pub async fn get_embedding(
  config : OpenAIConfig,
  text : String,
) -> Array[Double] raise EmbedError {
  let results = get_embeddings(config, [text])
  if results.length() > 0 {
    results[0]
  } else {
    raise NoResult
  }
}
