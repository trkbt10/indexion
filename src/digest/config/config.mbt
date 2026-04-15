// DigestConfig - digest-specific configuration.
// Embedding types (EmbeddingApiConfig, ProviderConfig, VcdbStrategy, etc.)
// are defined in @embed_config (src/embedding/config/) — the shared SoT.
// This module only contains digest-specific settings.

///|
/// Default symbol kinds to exclude from indexing.
pub fn default_exclude_kinds() -> Array[String] {
  ["param"]
}

///|
/// Default index directory
pub const DEFAULT_INDEX_DIR : String = ".indexion/digest"

// --- Re-exports from @embed_config for backward compatibility ---
// Consumers that already import @dconfig can still use these.
// New code should import @embed_config directly.

///|
pub const DEFAULT_TFIDF_DIM : Int = @embed_config.DEFAULT_TFIDF_DIM

///|
pub const OPENAI_EMBEDDING_DIM : Int = @embed_config.OPENAI_EMBEDDING_DIM

///|
pub const DEFAULT_API_KEY_ENV : String = @embed_config.DEFAULT_API_KEY_ENV

///|
pub const DEFAULT_API_BASE_URL : String = @embed_config.DEFAULT_API_BASE_URL

///|
pub const DEFAULT_EMBEDDING_MODEL : String = @embed_config.DEFAULT_EMBEDDING_MODEL

///|
pub const DEFAULT_TFIDF_KEY : String = @embed_config.DEFAULT_TFIDF_KEY

// Type aliases for backward compatibility.
// Callers that use @dconfig.EmbeddingApiConfig etc. continue to work.

///|
pub type EmbeddingApiConfig = @embed_config.EmbeddingApiConfig

///|
pub type EmbeddingProvider = @embed_config.EmbeddingProvider

///|
pub type VcdbStrategy = @embed_config.VcdbStrategy

///|
pub type EmbeddingSource = @embed_config.EmbeddingSource

///|
pub type ProviderConfig = @embed_config.ProviderConfig

// --- Index file path functions (digest-specific SoT) ---

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
pub fn vectors_db_path(index_dir : String, provider_key : String) -> String {
  index_path(index_dir, "vectors_" + provider_key + ".db")
}

///|
/// Path to the vocabulary file for a given provider key (TF-IDF only).
pub fn vocabulary_json_path(
  index_dir : String,
  provider_key : String,
) -> String {
  index_path(index_dir, "vocabulary_" + provider_key + ".json")
}

///|
/// Compute the list of all index file names for a given set of provider keys.
pub fn compute_index_file_names(provider_keys : Array[String]) -> Array[String] {
  let names : Array[String] = [INDEX_MANIFEST_FILE, INDEX_GRAPH_FILE]
  for key in provider_keys {
    names.push("vectors_" + key + ".db")
    names.push("vocabulary_" + key + ".json")
  }
  for name in legacy_file_names {
    names.push(name)
  }
  names
}

// --- Digest-specific types ---

///|
/// Default impression model
pub const DEFAULT_IMPRESS_MODEL : String = "gpt-4o-mini"

///|
/// Default system prompt for impression generation
pub const DEFAULT_IMPRESS_PROMPT : String = "You are a code documentation expert. Given a function's metadata, generate a concise purpose description.\n\nOutput JSON with:\n- summary: One sentence describing what the function does\n- keywords: 3-5 key terms for search (English)\n\nBe specific and actionable. Focus on WHAT the function does, not HOW."

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
} derive(Eq, Debug)

///|
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
pub fn LlmConfig::with_prompt(
  api_key : String,
  system_prompt : String,
) -> LlmConfig {
  { ..LlmConfig::openai(api_key), system_prompt, }
}

///|
pub fn LlmConfig::with_model(api_key : String, model : String) -> LlmConfig {
  { ..LlmConfig::openai(api_key), model, }
}

///|
/// Unified digest configuration.
pub(all) struct DigestConfig {
  /// Embedding source: Raw, Impression, or RawWithContext.
  embedding_source : @embed_config.EmbeddingSource
  /// Ordered list of embedding providers.
  providers : Array[@embed_config.ProviderConfig]
  /// vcdb indexing strategy.
  vcdb_strategy : @embed_config.VcdbStrategy
  /// Include external packages (no source file).
  include_external : Bool
  /// Symbol kinds to exclude from indexing.
  exclude_kinds : Array[String]
  /// Index directory for persistence.
  index_dir : String
  /// LLM config for impression generation (optional).
  llm_config : LlmConfig?
} derive(Eq, Debug)

///|
pub fn DigestConfig::default() -> DigestConfig {
  {
    embedding_source: @embed_config.Raw,
    providers: [@embed_config.ProviderConfig::tfidf()],
    vcdb_strategy: @embed_config.Hnsw,
    include_external: false,
    exclude_kinds: default_exclude_kinds(),
    index_dir: DEFAULT_INDEX_DIR,
    llm_config: None,
  }
}

///|
pub fn DigestConfig::openai(api_key : String) -> DigestConfig {
  {
    embedding_source: @embed_config.Raw,
    providers: [
      @embed_config.ProviderConfig::tfidf(),
      @embed_config.ProviderConfig::remote(
        @embed_config.EmbeddingApiConfig::new(api_key),
      ),
    ],
    vcdb_strategy: @embed_config.Hnsw,
    include_external: false,
    exclude_kinds: default_exclude_kinds(),
    index_dir: DEFAULT_INDEX_DIR,
    llm_config: None,
  }
}

///|
pub fn DigestConfig::with_impressions(api_key : String) -> DigestConfig {
  {
    embedding_source: @embed_config.Impression,
    providers: [
      @embed_config.ProviderConfig::tfidf(),
      @embed_config.ProviderConfig::remote(
        @embed_config.EmbeddingApiConfig::new(api_key),
      ),
    ],
    vcdb_strategy: @embed_config.Hnsw,
    include_external: false,
    exclude_kinds: default_exclude_kinds(),
    index_dir: DEFAULT_INDEX_DIR,
    llm_config: Some(LlmConfig::openai(api_key)),
  }
}

///|
pub fn DigestConfig::with_llm(
  self : DigestConfig,
  llm_config : LlmConfig,
) -> DigestConfig {
  { ..self, llm_config: Some(llm_config) }
}

///|
pub fn DigestConfig::with_impress_prompt(
  self : DigestConfig,
  prompt : String,
) -> DigestConfig {
  match self.llm_config {
    Some(cfg) => { ..self, llm_config: Some({ ..cfg, system_prompt: prompt }) }
    None => {
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
pub fn DigestConfig::with_index_dir(
  self : DigestConfig,
  dir : String,
) -> DigestConfig {
  { ..self, index_dir: dir }
}

///|
pub fn DigestConfig::with_exclude_kinds(
  self : DigestConfig,
  kinds : Array[String],
) -> DigestConfig {
  { ..self, exclude_kinds: kinds }
}

///|
pub fn DigestConfig::first_of_kind(
  self : DigestConfig,
  kind : String,
) -> @embed_config.ProviderConfig? {
  for p in self.providers {
    if p.kind == kind {
      return Some(p)
    }
  }
  None
}

///|
pub fn DigestConfig::get_provider(
  self : DigestConfig,
  key : String,
) -> @embed_config.ProviderConfig? {
  for p in self.providers {
    if p.key == key {
      return Some(p)
    }
  }
  None
}

///|
pub fn DigestConfig::provider_keys(self : DigestConfig) -> Array[String] {
  let keys : Array[String] = []
  for p in self.providers {
    keys.push(p.key)
  }
  keys
}

///|
pub fn DigestConfig::uses_impressions(self : DigestConfig) -> Bool {
  self.embedding_source is @embed_config.Impression
}

///|
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
pub fn DigestConfig::from_provider(
  provider : @embed_config.EmbeddingProvider,
) -> DigestConfig {
  match provider {
    @embed_config.TfIdf(dim) =>
      {
        ..DigestConfig::default(),
        providers: [@embed_config.ProviderConfig::tfidf(dim~)],
      }
    @embed_config.OpenAI(cfg) =>
      {
        ..DigestConfig::default(),
        providers: [
          @embed_config.ProviderConfig::tfidf(),
          @embed_config.ProviderConfig::remote(cfg),
        ],
      }
    @embed_config.Precomputed(_) => DigestConfig::default()
  }
}

///|
/// Get text for embedding from FunctionUnit based on embedding source.
pub fn DigestConfig::get_embedding_text(
  self : DigestConfig,
  unit : @types.FunctionUnit,
) -> String {
  match self.embedding_source {
    @embed_config.Raw => {
      let base = unit.name() + " " + unit.symbol.kind + " " + unit.symbol.ns
      match unit.symbol.doc {
        Some(doc) => base + " " + doc
        None => base
      }
    }
    @embed_config.Impression =>
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
    @embed_config.RawWithContext => {
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
