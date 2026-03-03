///|
/// KGF Registry - Dynamic language/extension mapping from KGF specs.
/// Loads specs from filesystem and provides lookup by extension or language name.

///|
/// KGFRegistry holds loaded specs and provides lookup functions.
pub struct KGFRegistry {
  /// Language name -> KGFSpec
  specs : Map[String, @types.KGFSpec]
  /// Extension (with dot) -> language name
  ext_to_lang : Map[String, String]
  /// Language name -> doc spec name (if separate -doc spec exists)
  lang_to_doc_spec : Map[String, String]
}

///|
/// Create an empty registry.
pub fn KGFRegistry::new() -> KGFRegistry {
  { specs: {}, ext_to_lang: {}, lang_to_doc_spec: {} }
}

///|
/// Load all KGF specs from a directory.
pub fn KGFRegistry::load_from_dir(dir : String) -> KGFRegistry {
  let registry = KGFRegistry::new()
  try {
    if not(@fs.is_dir(dir)) {
      return registry
    }
    let entries = @fs.read_dir(dir)
    for entry in entries {
      if entry.has_suffix(".kgf") {
        let path = dir + "/" + entry
        let content = @fs.read_file_to_string(path)
        match @parser.parse_kgf(content) {
          Some(spec) => registry.register_spec(spec)
          None => ()
        }
      }
    }
  } catch {
    _ => ()
  }
  registry
}

///|
/// Register a single spec into the registry.
pub fn KGFRegistry::register_spec(
  self : KGFRegistry,
  spec : @types.KGFSpec,
) -> Unit {
  let lang = spec.get_language()
  self.specs.set(lang, spec)

  // Check if this is a doc spec (e.g., typescript-doc)
  if lang.has_suffix("-doc") {
    let base_lang = substr(lang, 0, lang.length() - 4)
    self.lang_to_doc_spec.set(base_lang, lang)
  }

  // Map extensions to language
  let resolver = spec.get_resolver()
  let sources = resolver.get_sources()
  for ext in sources {
    // sources contains extensions like ".ts", ".tsx"
    self.ext_to_lang.set(ext, lang)
  }
}

///|
/// Get spec by language name.
pub fn KGFRegistry::get_spec(
  self : KGFRegistry,
  lang : String,
) -> @types.KGFSpec? {
  self.specs.get(lang)
}

///|
/// Get language name from file extension (with or without dot).
pub fn KGFRegistry::get_lang_from_ext(
  self : KGFRegistry,
  ext : String,
) -> String? {
  let normalized = if ext.has_prefix(".") { ext } else { "." + ext }
  self.ext_to_lang.get(normalized)
}

///|
/// Get the doc spec name for a language (returns language-doc if exists, otherwise the language itself).
pub fn KGFRegistry::get_doc_spec_name(
  self : KGFRegistry,
  lang : String,
) -> String {
  match self.lang_to_doc_spec.get(lang) {
    Some(doc_spec) => doc_spec
    None => lang
  }
}

///|
/// Get all registered language names.
pub fn KGFRegistry::get_languages(self : KGFRegistry) -> Array[String] {
  let result : Array[String] = []
  for entry in self.specs {
    result.push(entry.0)
  }
  result
}

///|
/// Get all registered extensions.
pub fn KGFRegistry::get_extensions(self : KGFRegistry) -> Array[String] {
  let result : Array[String] = []
  for entry in self.ext_to_lang {
    result.push(entry.0)
  }
  result
}

///|
/// Check if an extension is supported.
pub fn KGFRegistry::supports_ext(self : KGFRegistry, ext : String) -> Bool {
  let normalized = if ext.has_prefix(".") { ext } else { "." + ext }
  self.ext_to_lang.contains(normalized)
}

///|
/// Detect language from file path using extension.
pub fn KGFRegistry::detect_from_path(
  self : KGFRegistry,
  path : String,
) -> String? {
  let ext = extract_extension(path)
  if ext.length() == 0 {
    return None
  }
  self.get_lang_from_ext(ext)
}

///|
/// Get total number of registered specs.
pub fn KGFRegistry::spec_count(self : KGFRegistry) -> Int {
  self.specs.length()
}

// Helper functions

///|
/// Extract file extension from path (with dot).
fn extract_extension(path : String) -> String {
  let chars = path.to_array()
  let mut last_dot = -1
  let mut last_slash = -1
  for i = 0; i < chars.length(); i = i + 1 {
    if chars[i] == '.' {
      last_dot = i
    } else if chars[i] == '/' || chars[i] == '\\' {
      last_slash = i
    }
  }
  if last_dot > last_slash && last_dot < chars.length() - 1 {
    let result : Array[Char] = []
    result.push('.')
    for i = last_dot + 1; i < chars.length(); i = i + 1 {
      result.push(chars[i])
    }
    String::from_array(result)
  } else {
    ""
  }
}

///|
/// Substring helper.
fn substr(s : String, start : Int, end : Int) -> String {
  let chars = s.to_array()
  let result : Array[Char] = []
  let actual_end = if end > chars.length() { chars.length() } else { end }
  for i = start; i < actual_end; i = i + 1 {
    result.push(chars[i])
  }
  String::from_array(result)
}
