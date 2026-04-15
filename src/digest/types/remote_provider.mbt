// Remote embedding provider that reads pre-computed embeddings from file.
// Works with scripts/embed.py to get OpenAI embeddings.

///|
/// Remote embedding configuration.
pub struct RemoteEmbeddingConfig {
  /// Path to embeddings JSONL file (id, embedding pairs).
  embeddings_file : String
  /// Embedding dimension (1536 for text-embedding-3-small).
  dim : Int
} derive(Eq, Debug)

///|
/// Create default remote config for OpenAI text-embedding-3-small.
pub fn RemoteEmbeddingConfig::default() -> RemoteEmbeddingConfig {
  let base_dir = match @config.resolve_project_indexion_dir(".", "digest") {
    Some(dir) => dir
    None => ".indexion/digest"
  }
  { embeddings_file: base_dir + "/embeddings.jsonl", dim: 1536 }
}

///|
/// Remote embedding provider that loads pre-computed embeddings.
pub struct RemoteEmbeddingProvider {
  /// Configuration.
  config : RemoteEmbeddingConfig
  /// Cached embeddings: id -> vector.
  cache : Map[String, Array[Double]]
} derive(Eq, Debug)

///|
/// Create a new RemoteEmbeddingProvider.
pub fn RemoteEmbeddingProvider::new(
  config : RemoteEmbeddingConfig,
) -> RemoteEmbeddingProvider {
  { config, cache: {} }
}

///|
/// Load embeddings from JSONL file.
/// Each line: {"id": "function_id", "embedding": [0.1, 0.2, ...]}
pub fn RemoteEmbeddingProvider::load_from_file(
  self : RemoteEmbeddingProvider,
  content : String,
) -> Int {
  let mut count = 0
  let lines = split_lines(content)
  for line in lines {
    if line.length() == 0 {
      continue
    }
    match parse_embedding_line(line) {
      Some((id, embedding)) => {
        self.cache.set(id, embedding)
        count = count + 1
      }
      None => ()
    }
  }
  count
}

///|
/// Get embedding for a text (must be pre-computed and loaded).
pub fn RemoteEmbeddingProvider::get(
  self : RemoteEmbeddingProvider,
  id : String,
) -> Array[Double]? {
  self.cache.get(id)
}

///|
/// Get embedding dimension.
pub fn RemoteEmbeddingProvider::dim(self : RemoteEmbeddingProvider) -> Int {
  self.config.dim
}

///|
/// Check if embedding exists for id.
pub fn RemoteEmbeddingProvider::has(
  self : RemoteEmbeddingProvider,
  id : String,
) -> Bool {
  self.cache.contains(id)
}

///|
/// Get all cached IDs.
pub fn RemoteEmbeddingProvider::cached_ids(
  self : RemoteEmbeddingProvider,
) -> Array[String] {
  let ids : Array[String] = []
  for entry in self.cache {
    ids.push(entry.0)
  }
  ids
}

// Helper functions

///|
fn split_lines(s : String) -> Array[String] {
  let result : Array[String] = []
  let current : Array[Char] = []
  for c in s {
    if c == '\n' {
      result.push(String::from_array(current))
      current.clear()
    } else if c != '\r' {
      current.push(c)
    }
  }
  if current.length() > 0 {
    result.push(String::from_array(current))
  }
  result
}

///|
/// Parse a single embedding line: {"id": "...", "embedding": [...]}
fn parse_embedding_line(line : String) -> (String, Array[Double])? {
  // Simple JSON parsing for our specific format
  let json = @json.parse(line) catch { _ => return None }
  let obj = match json {
    Object(m) => m
    _ => return None
  }
  let id = match obj.get("id") {
    Some(String(s)) => s
    _ => return None
  }
  let embedding = match obj.get("embedding") {
    Some(Array(arr)) => {
      let vec : Array[Double] = []
      for item in arr {
        match item {
          Number(n, ..) => vec.push(n)
          _ => return None
        }
      }
      vec
    }
    _ => return None
  }
  Some((id, embedding))
}
