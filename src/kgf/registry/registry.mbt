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
/// Load all KGF specs from a directory (recursively including subdirectories).
pub fn KGFRegistry::load_from_dir(dir : String) -> KGFRegistry {
  let registry = KGFRegistry::new()
  load_specs_recursive(registry, dir)
  registry
}

///|
/// Recursively load KGF specs from a directory.
fn load_specs_recursive(registry : KGFRegistry, dir : String) -> Unit {
  try {
    if !@fs.is_dir(dir) {
      return
    }
    let entries = @fs.read_dir(dir)
    for entry in entries {
      let path = dir + "/" + entry
      if entry.has_suffix(".kgf") {
        // Load KGF spec file
        let content = @fs.read_file_to_string(path)
        match @parser.parse_kgf(content) {
          Some(spec) => registry.register_spec(spec)
          None => ()
        }
      } else if @fs.is_dir(path) && !entry.has_prefix(".") {
        // Recurse into subdirectory
        load_specs_recursive(registry, path)
      }
    }
  } catch {
    _ => ()
  }
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
    let base_lang = @config.substring(lang, 0, lang.length() - 4)
    self.lang_to_doc_spec.set(base_lang, lang)
  }

  // Map extensions to language.
  // When multiple specs claim the same extension, prefer the more general spec.
  // A spec with `special_files` feature is domain-specific (e.g., wiki specs)
  // and should not override a general-purpose spec for the same extension.
  let is_domain_specific = spec.get_feature("special_files") is Some(_)
  let resolver = spec.get_resolver()
  let sources = resolver.get_sources()
  for ext in sources {
    // sources contains extensions like ".ts", ".tsx"
    match self.ext_to_lang.get(ext) {
      Some(_) =>
        // Extension already registered. Only overwrite if the new spec is
        // general-purpose (not domain-specific). Domain-specific specs
        // (with special_files) should not steal extensions from general ones.
        if !(is_domain_specific) {
          self.ext_to_lang.set(ext, lang)
        }
      None => self.ext_to_lang.set(ext, lang)
    }
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
/// Check if a file path is supported by any registered spec.
/// Handles both extension-based matching (e.g., ".ts") and filename-based matching (e.g., "moon.pkg").
pub fn KGFRegistry::is_file_supported(
  self : KGFRegistry,
  path : String,
) -> Bool {
  for entry in self.ext_to_lang {
    let pattern = entry.0
    // Extension-based: pattern starts with "." (e.g., ".ts", ".tsx")
    if pattern.has_prefix(".") {
      if path.has_suffix(pattern) {
        return true
      }
      // Filename-based: pattern is a filename (e.g., "moon.pkg")
      // Match if path ends with /pattern or path equals pattern
    } else if path == pattern ||
      path.has_suffix("/" + pattern) ||
      path.has_suffix("\\" + pattern) {
      return true
    }
  }
  false
}

///|
/// Detect language from file path.
/// Handles both extension-based patterns (e.g., ".ts") and filename-based patterns (e.g., "moon.pkg").
pub fn KGFRegistry::detect_from_path(
  self : KGFRegistry,
  path : String,
) -> String? {
  // First try filename-based patterns
  for entry in self.ext_to_lang {
    let pattern = entry.0
    let lang = entry.1
    if !pattern.has_prefix(".") {
      // Filename pattern (e.g., "moon.pkg")
      if path == pattern ||
        path.has_suffix("/" + pattern) ||
        path.has_suffix("\\" + pattern) {
        return Some(lang)
      }
    }
  }
  // Then try extension-based patterns
  let ext = @config.extension(path)
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

///|
/// Get a copy of all loaded specs as language -> spec map.
pub fn KGFRegistry::to_specs_map(
  self : KGFRegistry,
) -> Map[String, @types.KGFSpec] {
  let specs : Map[String, @types.KGFSpec] = {}
  for entry in self.specs {
    specs.set(entry.0, entry.1)
  }
  specs
}

///|
/// Get all external prefixes (bare_prefix values) from registered specs.
/// These prefixes indicate external dependencies (e.g., "pkg:", "npm:", "pip:").
pub fn KGFRegistry::get_external_prefixes(self : KGFRegistry) -> Array[String] {
  let prefixes : Array[String] = []
  for entry in self.specs {
    let spec = entry.1
    let resolver = spec.get_resolver()
    let prefix = resolver.get_bare_prefix()
    if prefix.length() > 0 {
      // Check if already in list
      let mut exists = false
      for p in prefixes {
        if p == prefix {
          exists = true
          break
        }
      }
      if !exists {
        prefixes.push(prefix)
      }
    }
  }
  prefixes
}

///|
/// Get project/root marker patterns derived from loaded KGF specs.
/// This collects filename-based `sources`, resolver `project_config`, and
/// `manifest` / `marker` resolve steps so callers do not hardcode ecosystem
/// manifests.
pub fn KGFRegistry::get_project_markers(self : KGFRegistry) -> Array[String] {
  let markers : Array[String] = []
  for entry in self.specs {
    let spec = entry.1
    let resolver = spec.get_resolver()
    add_project_marker(markers, resolver.get_project_config())
    for source in resolver.get_sources() {
      if is_filename_pattern(source) {
        add_project_marker(markers, source)
      }
    }
    for step in resolver.get_resolve_chain() {
      match step.get_step_type() {
        @types.ResolveStepType::Manifest =>
          add_project_marker(markers, step.get_file())
        @types.ResolveStepType::Marker =>
          for file in step.get_files() {
            add_project_marker(markers, file)
          }
        _ => ()
      }
    }
  }
  markers.sort()
  markers
}

// Helper functions

///|
fn contains_string(values : Array[String], value : String) -> Bool {
  for current in values {
    if current == value {
      return true
    }
  }
  false
}

///|
fn is_filename_pattern(pattern : String) -> Bool {
  pattern.length() > 0 &&
  !pattern.has_prefix(".") &&
  !pattern.contains("/") &&
  !pattern.contains("\\")
}

///|
fn add_project_marker(markers : Array[String], marker : String) -> Unit {
  if !is_filename_pattern(marker) || contains_string(markers, marker) {
    return
  }
  markers.push(marker)
}

///|
/// Collect all ignore patterns from loaded KGF specs.
/// Returns (pattern, language) pairs.
pub fn KGFRegistry::collect_ignore_patterns(
  self : KGFRegistry,
) -> Array[(String, String)] {
  let result : Array[(String, String)] = []
  for entry in self.specs {
    let lang = entry.0
    let spec = entry.1
    match spec.get_ignore() {
      Some(patterns) =>
        for p in patterns {
          result.push((p, lang))
        }
      None => ()
    }
  }
  result
}
