///|
/// ToolkitRegistry wraps a KGFRegistry and caches LanguageToolkit instances
/// per language. This ensures that derived artifacts (Lexer, identifier sets,
/// etc.) are built exactly once per language, regardless of how many files
/// of that language are processed.
pub struct ToolkitRegistry {
  registry : @registry.KGFRegistry
  cache : Map[String, LanguageToolkit]
}

///|
/// Create a ToolkitRegistry from a KGFRegistry.
pub fn ToolkitRegistry::new(
  registry : @registry.KGFRegistry,
) -> ToolkitRegistry {
  { registry, cache: {}, }
}

///|
/// Access the underlying KGFRegistry.
pub fn ToolkitRegistry::get_registry(
  self : ToolkitRegistry,
) -> @registry.KGFRegistry {
  self.registry
}

///|
/// Get the LanguageToolkit for a language name.
/// Builds and caches on first access.
pub fn ToolkitRegistry::get(
  self : ToolkitRegistry,
  lang : String,
) -> LanguageToolkit? {
  match self.cache.get(lang) {
    Some(toolkit) => Some(toolkit)
    None =>
      match self.registry.get_spec(lang) {
        Some(spec) => {
          let toolkit = LanguageToolkit::from_spec(spec)
          self.cache.set(lang, toolkit)
          Some(toolkit)
        }
        None => None
      }
  }
}

///|
/// Detect language from file path and return the corresponding toolkit.
/// Convenience method combining detect_from_path + get.
pub fn ToolkitRegistry::for_path(
  self : ToolkitRegistry,
  path : String,
) -> LanguageToolkit? {
  match self.registry.detect_from_path(path) {
    Some(lang) => self.get(lang)
    None => None
  }
}

///|
/// Tokenize source content for a file path.
/// Returns None if no spec matches the file.
pub fn ToolkitRegistry::tokenize(
  self : ToolkitRegistry,
  content : String,
  path : String,
) -> Array[@types.Tok]? {
  match self.for_path(path) {
    Some(toolkit) => Some(toolkit.preprocess_and_tokenize(content))
    None => None
  }
}
