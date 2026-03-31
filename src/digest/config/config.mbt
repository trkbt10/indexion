// DigestConfig - Single Source of Truth for digest configuration.
// Consolidates all digest-related settings in one place.

///|
/// Default symbol kinds to exclude from indexing.
/// Param (function parameters) are excluded by default.
pub fn default_exclude_kinds() -> Array[String] {
  ["param"]
}

///|
/// Default index directory
pub const DEFAULT_INDEX_DIR : String = ".indexion/digest"

///|
/// Default TF-IDF dimension
pub const DEFAULT_TFIDF_DIM : Int = 256

///|
/// OpenAI text-embedding-3-small dimension
pub const OPENAI_EMBEDDING_DIM : Int = 1536

///|
/// Default impression model
pub const DEFAULT_IMPRESS_MODEL : String = "gpt-4o-mini"

///|
/// Default system prompt for impression generation
pub const DEFAULT_IMPRESS_PROMPT : String = "You are a code documentation expert. Given a function's metadata, generate a concise purpose description.\n\nOutput JSON with:\n- summary: One sentence describing what the function does\n- keywords: 3-5 key terms for search (English)\n\nBe specific and actionable. Focus on WHAT the function does, not HOW."

///|
/// Embedding source for function indexing.
pub(all) enum EmbeddingSource {
  /// Use raw function info (name + kind + namespace).
  Raw
  /// Use LLM-generated impressions (requires impression generation).
  Impression
  /// Use raw with callees context appended.
  RawWithContext
} derive(Eq, Show)

///|
/// Default embedding API key environment variable name.
pub const DEFAULT_API_KEY_ENV : String = "OPENAI_API_KEY"

///|
/// Default embedding API base URL.
pub const DEFAULT_API_BASE_URL : String = "https://api.openai.com/v1/embeddings"

///|
/// Default embedding model name.
pub const DEFAULT_EMBEDDING_MODEL : String = "text-embedding-3-small"

///|
/// Configuration for embedding API (OpenAI-compatible).
pub(all) struct EmbeddingApiConfig {
  /// API key.
  api_key : String
  /// Environment variable name the API key was resolved from.
  api_key_env : String
  /// API base URL for embeddings endpoint.
  base_url : String
  /// Embedding model name.
  model : String
  /// Embedding vector dimension.
  dim : Int
} derive(Eq, Show)

///|
/// Create EmbeddingApiConfig with defaults for OpenAI.
pub fn EmbeddingApiConfig::new(api_key : String) -> EmbeddingApiConfig {
  {
    api_key,
    api_key_env: DEFAULT_API_KEY_ENV,
    base_url: DEFAULT_API_BASE_URL,
    model: DEFAULT_EMBEDDING_MODEL,
    dim: OPENAI_EMBEDDING_DIM,
  }
}

///|
/// Embedding provider type.
pub(all) enum EmbeddingProvider {
  /// Local TF-IDF (no external dependencies).
  TfIdf(Int) // dimension
  /// OpenAI-compatible embedding API.
  OpenAI(EmbeddingApiConfig)
  /// Pre-computed embeddings from file.
  Precomputed(String) // file_path
} derive(Eq, Show)

///|
/// vcdb indexing strategy.
pub(all) enum VcdbStrategy {
  /// Brute force (exact, slow for large datasets).
  BruteForce
  /// HNSW (approximate, fast).
  Hnsw
  /// IVF (approximate, good for very large datasets).
  Ivf
} derive(Eq, Show)

///|
/// LLM configuration for impression generation.
pub(all) struct LlmConfig {
  /// API key for LLM provider.
  api_key : String
  /// Model name (e.g., "gpt-4o-mini", "gpt-4o").
  model : String
  /// System prompt for impression generation.
  system_prompt : String
  /// API base URL.
  base_url : String
  /// Temperature for generation (0.0-1.0).
  temperature : Double
} derive(Eq, Show)

///|
/// Default LLM config for OpenAI.
pub fn LlmConfig::openai(api_key : String) -> LlmConfig {
  {
    api_key,
    model: DEFAULT_IMPRESS_MODEL,
    system_prompt: DEFAULT_IMPRESS_PROMPT,
    base_url: "https://api.openai.com/v1/chat/completions",
    temperature: 0.3,
  }
}

///|
/// LLM config with custom prompt.
pub fn LlmConfig::with_prompt(
  api_key : String,
  system_prompt : String,
) -> LlmConfig {
  { ..LlmConfig::openai(api_key), system_prompt, }
}

///|
/// LLM config with custom model.
pub fn LlmConfig::with_model(api_key : String, model : String) -> LlmConfig {
  { ..LlmConfig::openai(api_key), model, }
}

///|
/// Unified digest configuration.
pub(all) struct DigestConfig {
  /// Embedding source: Raw, Impression, or RawWithContext.
  embedding_source : EmbeddingSource
  /// Embedding provider: TfIdf, OpenAI, or Precomputed.
  embedding_provider : EmbeddingProvider
  /// vcdb indexing strategy.
  vcdb_strategy : VcdbStrategy
  /// Include external packages (no source file).
  include_external : Bool
  /// Symbol kinds to exclude from indexing.
  exclude_kinds : Array[String]
  /// Index directory for persistence.
  index_dir : String
  /// LLM config for impression generation (optional).
  llm_config : LlmConfig?
} derive(Eq, Show)

///|
/// Default config: TF-IDF, raw embedding, HNSW, internal only.
pub fn DigestConfig::default() -> DigestConfig {
  {
    embedding_source: Raw,
    embedding_provider: TfIdf(DEFAULT_TFIDF_DIM),
    vcdb_strategy: Hnsw,
    include_external: false,
    exclude_kinds: default_exclude_kinds(),
    index_dir: DEFAULT_INDEX_DIR,
    llm_config: None,
  }
}

///|
/// Config for native OpenAI embedding.
pub fn DigestConfig::openai(api_key : String) -> DigestConfig {
  {
    embedding_source: Raw,
    embedding_provider: OpenAI(EmbeddingApiConfig::new(api_key)),
    vcdb_strategy: Hnsw,
    include_external: false,
    exclude_kinds: default_exclude_kinds(),
    index_dir: DEFAULT_INDEX_DIR,
    llm_config: None,
  }
}

///|
/// Config with impressions (best quality, requires LLM).
pub fn DigestConfig::with_impressions(api_key : String) -> DigestConfig {
  {
    embedding_source: Impression,
    embedding_provider: OpenAI(EmbeddingApiConfig::new(api_key)),
    vcdb_strategy: Hnsw,
    include_external: false,
    exclude_kinds: default_exclude_kinds(),
    index_dir: DEFAULT_INDEX_DIR,
    llm_config: Some(LlmConfig::openai(api_key)),
  }
}

///|
/// Config for precomputed embeddings file.
pub fn DigestConfig::precomputed(embeddings_file : String) -> DigestConfig {
  {
    embedding_source: Raw,
    embedding_provider: Precomputed(embeddings_file),
    vcdb_strategy: Hnsw,
    include_external: false,
    exclude_kinds: default_exclude_kinds(),
    index_dir: DEFAULT_INDEX_DIR,
    llm_config: None,
  }
}

///|
/// Set custom LLM config.
pub fn DigestConfig::with_llm(
  self : DigestConfig,
  llm_config : LlmConfig,
) -> DigestConfig {
  { ..self, llm_config: Some(llm_config) }
}

///|
/// Set custom system prompt for impressions.
pub fn DigestConfig::with_impress_prompt(
  self : DigestConfig,
  prompt : String,
) -> DigestConfig {
  match self.llm_config {
    Some(cfg) => { ..self, llm_config: Some({ ..cfg, system_prompt: prompt }) }
    None =>
      match self.embedding_provider {
        OpenAI(cfg) =>
          {
            ..self,
            llm_config: Some(LlmConfig::with_prompt(cfg.api_key, prompt)),
          }
        _ => self
      }
  }
}

///|
/// Set custom model for impressions.
pub fn DigestConfig::with_impress_model(
  self : DigestConfig,
  model : String,
) -> DigestConfig {
  match self.llm_config {
    Some(cfg) => { ..self, llm_config: Some({ ..cfg, model, }) }
    None =>
      match self.embedding_provider {
        OpenAI(cfg) =>
          {
            ..self,
            llm_config: Some(LlmConfig::with_model(cfg.api_key, model)),
          }
        _ => self
      }
  }
}

///|
/// Set index directory.
pub fn DigestConfig::with_index_dir(
  self : DigestConfig,
  dir : String,
) -> DigestConfig {
  { ..self, index_dir: dir }
}

///|
/// Set exclude kinds.
pub fn DigestConfig::with_exclude_kinds(
  self : DigestConfig,
  kinds : Array[String],
) -> DigestConfig {
  { ..self, exclude_kinds: kinds }
}

///|
/// Get embedding dimension for this config.
pub fn DigestConfig::embedding_dim(self : DigestConfig) -> Int {
  match self.embedding_provider {
    TfIdf(dim) => dim
    OpenAI(cfg) => cfg.dim
    Precomputed(_) => OPENAI_EMBEDDING_DIM // assume OpenAI format
  }
}

///|
/// Check if this config uses remote API.
pub fn DigestConfig::is_remote(self : DigestConfig) -> Bool {
  self.embedding_provider is OpenAI(_)
}

///|
/// Check if this config uses impressions.
pub fn DigestConfig::uses_impressions(self : DigestConfig) -> Bool {
  self.embedding_source is Impression
}

///|
/// Convert to ExtractConfig.
pub fn DigestConfig::to_extract_config(
  self : DigestConfig,
) -> @extract.ExtractConfig {
  {
    include_external: self.include_external,
    min_body_length: 0,
    exclude_kinds: self.exclude_kinds,
  }
}

///|
/// Set embedding provider.
pub fn DigestConfig::with_provider(
  self : DigestConfig,
  provider : EmbeddingProvider,
) -> DigestConfig {
  { ..self, embedding_provider: provider }
}

///|
/// Get text for embedding from FunctionUnit based on embedding source.
/// For Raw mode: uses doc comment if available, otherwise name + kind + ns.
pub fn DigestConfig::get_embedding_text(
  self : DigestConfig,
  unit : @types.FunctionUnit,
) -> String {
  match self.embedding_source {
    Raw => {
      // Prefer doc comment when available for better semantic matching
      let base = unit.name() + " " + unit.symbol.kind + " " + unit.symbol.ns
      match unit.symbol.doc {
        Some(doc) => base + " " + doc
        None => base
      }
    }
    Impression =>
      match unit.impression {
        Some(imp) => imp.to_text()
        None => {
          let base = unit.name() + " " + unit.symbol.kind + " " + unit.symbol.ns
          match unit.symbol.doc {
            Some(doc) => base + " " + doc
            None => base
          }
        }
      }
    RawWithContext => {
      let base = unit.name() + " " + unit.symbol.kind + " " + unit.symbol.ns
      let with_doc = match unit.symbol.doc {
        Some(doc) => base + " " + doc
        None => base
      }
      if unit.callees.length() > 0 {
        with_doc + " calls " + unit.callees.join(" ")
      } else {
        with_doc
      }
    }
  }
}
