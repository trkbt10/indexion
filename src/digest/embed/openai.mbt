// OpenAI Embedding API client (native, async)

///|
/// Embedding error
pub(all) suberror EmbedError {
  ParseError(String)
  ApiError(Int, String)
  NoResult
}

///|
/// OpenAI API configuration
pub struct OpenAIConfig {
  api_key : String
  model : String
  base_url : String
} derive(Eq, Show)

///|
/// Default config for text-embedding-3-small (1536 dims)
pub fn OpenAIConfig::default(api_key : String) -> OpenAIConfig {
  {
    api_key,
    model: "text-embedding-3-small",
    base_url: "https://api.openai.com/v1/embeddings",
  }
}

///|
/// Build request body JSON
fn build_request_body(texts : Array[String], model : String) -> String {
  let escaped_texts : Array[String] = []
  for text in texts {
    escaped_texts.push("\"" + escape_json(text) + "\"")
  }
  "{\"input\":[" + escaped_texts.join(",") + "],\"model\":\"" + model + "\"}"
}

///|
/// Escape string for JSON
fn escape_json(s : String) -> String {
  let result : Array[Char] = []
  for c in s {
    if c == '"' {
      result.push('\\')
      result.push('"')
    } else if c == '\\' {
      result.push('\\')
      result.push('\\')
    } else if c == '\n' {
      result.push('\\')
      result.push('n')
    } else if c == '\r' {
      result.push('\\')
      result.push('r')
    } else if c == '\t' {
      result.push('\\')
      result.push('t')
    } else {
      result.push(c)
    }
  }
  String::from_array(result)
}

///|
/// Parse embedding response JSON
fn parse_embedding_response(json_str : String) -> Array[Array[Double]]? {
  let json = @json.parse(json_str) catch { _ => return None }
  let obj = match json {
    Object(m) => m
    _ => return None
  }
  let data = match obj.get("data") {
    Some(Array(arr)) => arr
    _ => return None
  }
  // Collect (index, embedding) pairs
  let indexed : Array[(Int, Array[Double])] = []
  for item in data {
    match item {
      Object(item_obj) => {
        let embedding = match item_obj.get("embedding") {
          Some(Array(emb_arr)) => {
            let vec : Array[Double] = []
            for v in emb_arr {
              match v {
                Number(n, ..) => vec.push(n)
                _ => ()
              }
            }
            vec
          }
          _ => continue
        }
        let index = match item_obj.get("index") {
          Some(Number(n, ..)) => n.to_int()
          _ => 0
        }
        indexed.push((index, embedding))
      }
      _ => ()
    }
  }
  // Sort by index
  indexed.sort_by(fn(a, b) { a.0.compare(b.0) })
  let result : Array[Array[Double]] = []
  for pair in indexed {
    result.push(pair.1)
  }
  Some(result)
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
  match parse_embedding_response(response_body) {
    Some(embeddings) => embeddings
    None => raise ParseError("Failed to parse embedding response")
  }
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
