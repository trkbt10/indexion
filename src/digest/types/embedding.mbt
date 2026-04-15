// EmbeddingProvider trait for text-to-vector conversion.
// This abstraction allows different embedding backends (TF-IDF, remote API, etc.).

///|
/// EmbeddingProvider trait defines the interface for text-to-vector conversion.
/// Implementations handle the actual embedding generation.
pub(open) trait EmbeddingProvider {
  /// Generate embedding vector for a single text.
  embed(Self, String) -> Array[Double]
  /// Get the embedding dimension.
  dim(Self) -> Int
  /// Batch embedding for efficiency (default: sequential).
  embed_batch(Self, Array[String]) -> Array[Array[Double]]
}

///|
/// Configuration for embedding providers.
pub struct EmbeddingConfig {
  /// Provider type ("tfidf", "remote").
  provider_type : String
  /// Embedding dimension.
  dim : Int
  /// Remote endpoint (for remote providers).
  endpoint : String?
  /// API key (for remote providers).
  api_key : String?
} derive(Eq, Debug, ToJson, @json.FromJson)

///|
/// Create a TF-IDF embedding config.
pub fn EmbeddingConfig::tfidf(dim : Int) -> EmbeddingConfig {
  { provider_type: "tfidf", dim, endpoint: None, api_key: None }
}

///|
/// Create a remote embedding config.
pub fn EmbeddingConfig::remote(
  endpoint : String,
  dim : Int,
  api_key? : String? = None,
) -> EmbeddingConfig {
  { provider_type: "remote", dim, endpoint: Some(endpoint), api_key }
}

///|
/// Default TF-IDF config with 256 dimensions.
pub fn EmbeddingConfig::default() -> EmbeddingConfig {
  EmbeddingConfig::tfidf(256)
}
