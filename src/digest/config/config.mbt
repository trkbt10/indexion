// DigestConfig - Single Source of Truth for digest configuration.
// Consolidates all digest-related settings in one place.
//
// N-provider design: Any number of embedding providers (TF-IDF, remote APIs)
// coexist in a single index. Each provider is identified by a stable string key
// and persisted independently (separate vector DB files).

///|
/// Default symbol kinds to exclude from indexing.
/// Param (function parameters) are excluded by default.
pub fn default_exclude_kinds() -> Array[String] {
  ["param"]
}

///|
/// Default index directory
pub const DEFAULT_INDEX_DIR : String = ".indexion/digest"

// --- Index file name constants (SoT) ---
// Static file names are defined here. Provider-specific file names are dynamic.

///|
/// Manifest file name within the index directory.
pub const INDEX_MANIFEST_FILE : String = "manifest.json"

///|
/// Code graph file name within the index directory.
pub const INDEX_GRAPH_FILE : String = "graph.json"

///|
/// Build lock file name within the index directory.
pub const INDEX_LOCK_FILE : String = "build.lock"

///|
/// Legacy file names from previous versions — used for cleanup only.
let legacy_file_names : Array[String] = [
  "vectors.db", // v2
  "vectors_tfidf.db", // v3
  "vectors_remote.db", // v3
  "vocabulary.json", // v3 (non-keyed)
]

///|
/// Construct a full path by joining index_dir with a file name.
pub fn index_path(index_dir : String, file_name : String) -> String {
  index_dir + "/" + file_name
}

///|
/// Path to the manifest file within the given index directory.
pub fn manifest_path(index_dir : String) -> String {
  index_path(index_dir, INDEX_MANIFEST_FILE)
}

///|
/// Path to the code graph within the given index directory.
pub fn graph_path(index_dir : String) -> String {
  index_path(index_dir, INDEX_GRAPH_FILE)
}

///|
/// Path to the build lock file within the given index directory.
pub fn lock_path(index_dir : String) -> String {
  index_path(index_dir, INDEX_LOCK_FILE)
}

///|
/// Path to the vector database for a given provider key.
/// e.g. vectors_tfidf.db, vectors_text-embedding-3-small.db
pub fn vectors_db_path(
  index_dir : String,
  provider_key : String,
) -> String {
  index_path(index_dir, "vectors_" + provider_key + ".db")
}

///|
/// Path to the vocabulary file for a given provider key (TF-IDF only).
/// e.g. vocabulary_tfidf.json
pub fn vocabulary_json_path(
  index_dir : String,
  provider_key : String,
) -> String {
  index_path(index_dir, "vocabulary_" + provider_key + ".json")
}

///|
/// Compute the list of all index file names for a given set of provider keys.
/// Used for cleanup (delete_index_files).
pub fn compute_index_file_names(
  provider_keys : Array[String],
) -> Array[String] {
  let names : Array[String] = [INDEX_MANIFEST_FILE, INDEX_GRAPH_FILE]
  for key in provider_keys {
    names.push("vectors_" + key + ".db")
    names.push("vocabulary_" + key + ".json")
  }
  // Legacy cleanup
  for name in legacy_file_names {
    names.push(name)
  }
  names
}

///|
/// Default TF-IDF dimension
pub const DEFAULT_TFIDF_DIM : Int = 256

///|
/// OpenAI text-embedding-3-small dimension
pub const OPENAI_EMBEDDING_DIM : Int = 1536

///|
/// Default TF-IDF provider key
pub const DEFAULT_TFIDF_KEY : String = "tfidf"

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
/// Used for CLI parsing and display. The actual config uses providers array.
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
/// Per-provider configuration.
/// Each provider is identified by a unique key and has a kind ("tfidf" or "remote").
pub(all) struct ProviderConfig {
  /// Stable identifier used for file naming and manifest tracking.
  key : String
  /// Provider kind: "tfidf" for local TF-IDF, "remote" for API-based embedding.
  kind : String
  /// Embedding vector dimension.
  dim : Int
  /// API configuration (required for kind="remote", None for kind="tfidf").
  api_config : EmbeddingApiConfig?
} derive(Eq, Show)

///|
/// Create a default TF-IDF provider config.
pub fn ProviderConfig::tfidf(
  dim? : Int = DEFAULT_TFIDF_DIM,
) -> ProviderConfig {
  { key: DEFAULT_TFIDF_KEY, kind: "tfidf", dim, api_config: None }
}

///|
/// Create a remote provider config from an EmbeddingApiConfig.
/// Key defaults to the model name.
pub fn ProviderConfig::remote(api_config : EmbeddingApiConfig) -> ProviderConfig {
  {
    key: sanitize_provider_key(api_config.model),
    kind: "remote",
    dim: api_config.dim,
    api_config: Some(api_config),
  }
}

///|
/// Sanitize a string for use as a provider key (filesystem-safe).
/// Replaces non-alphanumeric chars (except hyphen, underscore, dot) with hyphen.
pub fn sanitize_provider_key(raw : String) -> String {
  let buf = StringBuilder::new()
  for ch in raw {
    if (ch >= 'a' && ch <= 'z') ||
      (ch >= 'A' && ch <= 'Z') ||
      (ch >= '0' && ch <= '9') ||
      ch == '-' ||
      ch == '_' ||
      ch == '.' {
      buf.write_char(ch)
    } else {
      buf.write_char('-')
    }
  }
  buf.to_string()
}

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
///
/// N-provider design: `providers` is an ordered list of embedding providers.
/// Each provider runs independently. The first provider is preferred for queries.
/// Providers can be TF-IDF (local) or remote API (OpenAI-compatible).
pub(all) struct DigestConfig {
  /// Embedding source: Raw, Impression, or RawWithContext.
  embedding_source : EmbeddingSource
  /// Ordered list of embedding providers. First is preferred for queries.
  providers : Array[ProviderConfig]
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
/// Default config: TF-IDF only, raw embedding, HNSW, internal only.
pub fn DigestConfig::default() -> DigestConfig {
  {
    embedding_source: Raw,
    providers: [ProviderConfig::tfidf()],
    vcdb_strategy: Hnsw,
    include_external: false,
    exclude_kinds: default_exclude_kinds(),
    index_dir: DEFAULT_INDEX_DIR,
    llm_config: None,
  }
}

///|
/// Config with OpenAI embedding (TF-IDF + OpenAI).
pub fn DigestConfig::openai(api_key : String) -> DigestConfig {
  {
    embedding_source: Raw,
    providers: [
      ProviderConfig::tfidf(),
      ProviderConfig::remote(EmbeddingApiConfig::new(api_key)),
    ],
    vcdb_strategy: Hnsw,
    include_external: false,
    exclude_kinds: default_exclude_kinds(),
    index_dir: DEFAULT_INDEX_DIR,
    llm_config: None,
  }
}

///|
/// Config with impressions (best quality, requires LLM + remote embeddings).
pub fn DigestConfig::with_impressions(api_key : String) -> DigestConfig {
  {
    embedding_source: Impression,
    providers: [
      ProviderConfig::tfidf(),
      ProviderConfig::remote(EmbeddingApiConfig::new(api_key)),
    ],
    vcdb_strategy: Hnsw,
    include_external: false,
    exclude_kinds: default_exclude_kinds(),
    index_dir: DEFAULT_INDEX_DIR,
    llm_config: Some(LlmConfig::openai(api_key)),
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
    None => {
      // Try to find a remote provider's API key
      for p in self.providers {
        match p.api_config {
          Some(cfg) =>
            return {
              ..self,
              llm_config: Some(LlmConfig::with_prompt(cfg.api_key, prompt)),
            }
          None => ()
        }
      }
      self
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
    None => {
      for p in self.providers {
        match p.api_config {
          Some(cfg) =>
            return {
              ..self,
              llm_config: Some(LlmConfig::with_model(cfg.api_key, model)),
            }
          None => ()
        }
      }
      self
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
/// Get the first provider of a given kind, if any.
pub fn DigestConfig::first_of_kind(
  self : DigestConfig,
  kind : String,
) -> ProviderConfig? {
  for p in self.providers {
    if p.kind == kind {
      return Some(p)
    }
  }
  None
}

///|
/// Get a provider by key.
pub fn DigestConfig::get_provider(
  self : DigestConfig,
  key : String,
) -> ProviderConfig? {
  for p in self.providers {
    if p.key == key {
      return Some(p)
    }
  }
  None
}

///|
/// Get all provider keys.
pub fn DigestConfig::provider_keys(self : DigestConfig) -> Array[String] {
  let keys : Array[String] = []
  for p in self.providers {
    keys.push(p.key)
  }
  keys
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
/// Construct DigestConfig from a resolved EmbeddingProvider enum.
/// Used by CLI to convert the legacy provider selection into providers array.
pub fn DigestConfig::from_provider(provider : EmbeddingProvider) -> DigestConfig {
  match provider {
    TfIdf(dim) =>
      { ..DigestConfig::default(), providers: [ProviderConfig::tfidf(dim~)] }
    OpenAI(cfg) =>
      {
        ..DigestConfig::default(),
        providers: [ProviderConfig::tfidf(), ProviderConfig::remote(cfg)],
      }
    Precomputed(_) => DigestConfig::default()
  }
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
