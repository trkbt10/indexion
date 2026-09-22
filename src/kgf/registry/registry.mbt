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
  /// Source pattern -> every language that declared it in `resolver.sources`,
  /// in registration order. `ext_to_lang` keeps only the winner; this keeps
  /// the full claim list so the conflict can be reported instead of being
  /// silently resolved (see `get_source_conflicts`).
  source_claims : Map[String, Array[String]]
}

///|
/// Create an empty registry.
pub fn KGFRegistry::new() -> KGFRegistry {
  { specs: {}, ext_to_lang: {}, lang_to_doc_spec: {}, source_claims: {}, }
}

///|
/// Load all KGF specs from a directory (recursively including subdirectories).
///
/// Loading is two-phase because of `extends:`. A derived spec's base may live
/// in a sibling subdirectory that has not been traversed yet, so phase one
/// only splits each `.kgf` file into its raw sections, and phase two resolves
/// inheritance and registers the fully merged specs. Every spec handed out by
/// the registry is therefore already resolved — no consumer has to know that
/// `extends:` exists.
pub fn KGFRegistry::load_from_dir(dir : String) -> KGFRegistry {
  let registry = KGFRegistry::new()
  let sources : Array[@parser.KGFSpecSource] = []
  collect_spec_sources(sources, dir)
  registry.register_spec_sources(sources)
  registry
}

///|
/// Recursively split every `.kgf` file under `dir` into its raw sections.
fn collect_spec_sources(
  sources : Array[@parser.KGFSpecSource],
  dir : String,
) -> Unit {
  try {
    if !@fs.is_dir(dir) {
      return
    }
    let entries = @fs.read_dir(dir).to_owned()
    // Sort entries alphabetically before iterating so spec registration order
    // is platform-independent. `@fs.read_dir` returns entries in filesystem
    // order, which differs between macOS APFS and Linux ext4. When multiple
    // specs claim the same `sources` extension (e.g. both `dsl/npm-package-json.kgf`
    // and `project/package-json.kgf` claim `package.json`), the last general
    // spec to register wins (see `register_spec`), so traversal order decides
    // the winner. Sorting first makes the choice deterministic across CI and
    // local dev environments.
    entries.sort()
    for entry in entries {
      let path = dir + "/" + entry
      if entry.has_suffix(".kgf") {
        let content = @fs.read_file_to_string(path)
        sources.push(@parser.parse_kgf_source(content))
      } else if @fs.is_dir(path) && !entry.has_prefix(".") {
        // Recurse into subdirectory
        collect_spec_sources(sources, path)
      }
    }
  } catch {
    _ => ()
  }
}

///|
/// Resolve `extends:` across a whole set of spec sources and register the
/// resulting specs, preserving the order the sources were collected in.
///
/// A spec whose `extends:` names a missing base, or takes part in a cycle, is
/// registered with its own sections only. Loading cannot report diagnostics —
/// it is on the hot path of every command — so reporting is left to
/// `kgf check`, which re-runs the same resolution through
/// `resolve_spec_source` and names the problem.
pub fn KGFRegistry::register_spec_sources(
  self : KGFRegistry,
  sources : Array[@parser.KGFSpecSource],
) -> Unit {
  let by_language : Map[String, @parser.KGFSpecSource] = Map([])
  for source in sources {
    by_language.set(source.get_language(), source)
  }
  for source in sources {
    let (resolved, _) = resolve_spec_source(source, by_language)
    self.register_spec(resolved.to_spec())
  }
}

///|
/// Why a spec's `extends:` chain could not be followed to the end.
pub enum ExtendsError {
  /// `extends:` names a spec that is not in the set. Carries the deriving
  /// spec's language and the missing base name.
  UnknownBase(String, String)
  /// Following `extends:` revisits a spec. Carries the chain, starting at the
  /// spec being resolved and ending at the repeated one.
  Cycle(Array[String])
  /// `extends:` is declared with an empty value. Carries the spec's language.
  EmptyBase(String)
} derive(Eq, Debug)

///|
/// Renders the error as the message `kgf check` reports.
pub fn ExtendsError::message(self : ExtendsError) -> String {
  match self {
    UnknownBase(lang, base) =>
      "Spec '" + lang + "' extends unknown spec '" + base + "'"
    Cycle(chain) => "Spec inheritance cycle: " + chain.join(" -> ")
    EmptyBase(lang) => "Spec '" + lang + "' declares 'extends:' with no value"
  }
}

///|
/// Merge a spec source with every ancestor named by `extends:`.
///
/// Walks the chain from the derived spec upwards, applying
/// `KGFSpecSource::merge_onto` at each step, so a section is taken from the
/// nearest ancestor that declares it. Returns the merged source together with
/// the first error that stopped the walk, if any; on error the merge keeps
/// whatever was resolved up to that point, which for an unknown base or an
/// empty `extends:` is the spec's own sections.
pub fn resolve_spec_source(
  source : @parser.KGFSpecSource,
  by_language : Map[String, @parser.KGFSpecSource],
) -> (@parser.KGFSpecSource, ExtendsError?) {
  let chain = [source.get_language()]
  let seen : Map[String, Bool] = Map([])
  seen.set(source.get_language(), true)
  let mut merged = source
  let mut current = source
  // The chain visits each spec at most once (`seen` stops a revisit), so the
  // number of specs bounds the walk; the count is the loop's termination
  // proof, not a tuning knob.
  for _ in 0..<(by_language.length() + 1) {
    let base_name = match current.get_extends() {
      Some(name) => name
      None => return (merged, None)
    }
    if base_name.length() == 0 {
      return (merged, Some(EmptyBase(current.get_language())))
    }
    if seen.contains(base_name) {
      chain.push(base_name)
      return (merged, Some(Cycle(chain)))
    }
    let base = match by_language.get(base_name) {
      Some(base) => base
      None =>
        return (merged, Some(UnknownBase(current.get_language(), base_name)))
    }
    chain.push(base_name)
    seen.set(base_name, true)
    merged = merged.merge_onto(base)
    current = base
  }
  (merged, None)
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
  let has_overlay_scope = match spec.get_feature("detection_scope") {
    Some(values) => values.length() > 0 && values[0] == "overlay"
    None => false
  }
  let is_domain_specific = spec.get_feature("special_files") is Some(_) ||
    has_overlay_scope
  let resolver = spec.get_resolver()
  let sources = resolver.get_sources()
  for ext in sources {
    // Record the claim before resolving it. Every general-purpose spec that
    // declares the pattern is kept, whether or not it ends up owning it, so
    // callers can report the conflict rather than only seeing the winner.
    // Domain-specific specs (overlays, wiki flavours) are selected by their
    // own commands and never compete for a pattern, so they are not claims.
    if !is_domain_specific {
      let claims = match self.source_claims.get(ext) {
        Some(existing) => existing
        None => {
          let fresh : Array[String] = []
          self.source_claims.set(ext, fresh)
          fresh
        }
      }
      if !contains_string(claims, lang) {
        claims.push(lang)
      }
    }
    // sources contains extensions like ".ts", ".tsx"
    match self.ext_to_lang.get(ext) {
      Some(_) =>
        // Extension already registered. Only overwrite if the new spec is
        // general-purpose (not domain-specific). Domain-specific specs
        // (with special_files) should not steal extensions from general ones.
        if !is_domain_specific {
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
fn match_extension_pattern_for_path(
  registry : KGFRegistry,
  path : String,
) -> (String, String)? {
  let mut best : (String, String)? = None
  let mut best_len = -1
  for entry in registry.ext_to_lang {
    let pattern = entry.0
    let lang = entry.1
    if !pattern.has_prefix(".") {
      continue
    }
    if !path.has_suffix(pattern) {
      continue
    }
    if pattern.length() > best_len {
      best = Some((pattern, lang))
      best_len = pattern.length()
    }
  }
  best
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
/// A source pattern claimed by more than one spec, and how the registry
/// resolved it.
///
/// Only one spec can own a pattern — `register_spec` lets the last
/// general-purpose spec win — so the rest are shadowed: files matching the
/// pattern are never analysed with them. That is a silent behavioural choice,
/// and this type is what makes it reportable.
pub struct SourceConflict {
  pattern : String
  /// The language `detect_from_path` will actually pick for this pattern.
  winner : String
  /// The languages that also declared it and lost, in registration order.
  losers : Array[String]
}

///|
pub fn SourceConflict::get_pattern(self : SourceConflict) -> String {
  self.pattern
}

///|
pub fn SourceConflict::get_winner(self : SourceConflict) -> String {
  self.winner
}

///|
pub fn SourceConflict::get_losers(self : SourceConflict) -> Array[String] {
  self.losers
}

///|
/// Every source pattern claimed by more than one registered spec, sorted by
/// pattern so the report is stable.
pub fn KGFRegistry::get_source_conflicts(
  self : KGFRegistry,
) -> Array[SourceConflict] {
  let conflicts : Array[SourceConflict] = []
  for entry in self.source_claims {
    let pattern = entry.0
    let claimants = entry.1
    if claimants.length() < 2 {
      continue
    }
    // The winner is whoever `ext_to_lang` ended up holding; if the pattern
    // somehow never made it there, fall back to the first claimant so the
    // report still names a concrete spec.
    let winner = match self.ext_to_lang.get(pattern) {
      Some(lang) => lang
      None => claimants[0]
    }
    let losers : Array[String] = []
    for lang in claimants {
      if lang != winner {
        losers.push(lang)
      }
    }
    if losers.length() > 0 {
      conflicts.push({ pattern, winner, losers, })
    }
  }
  conflicts.sort_by_key(fn(c) { c.pattern })
  conflicts
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
  match_extension_pattern_for_path(self, path) is Some(_)
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
  // Then try extension-based patterns, preferring the longest matching suffix.
  match match_extension_pattern_for_path(self, path) {
    Some((_pattern, lang)) => Some(lang)
    None => None
  }
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
  let specs : Map[String, @types.KGFSpec] = Map([])
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
