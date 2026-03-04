///|
/// ModulePathStyle represents the style of module path separators.
pub enum ModulePathStyle {
  Slash // "slash" - path/to/module
  Dot // "dot" - path.to.module
  ColonColon // "coloncol" - path::to::module
} derive(Eq, Show)

///|
/// Converts a string to ModulePathStyle.
pub fn ModulePathStyle::from_string(s : String) -> ModulePathStyle? {
  match s {
    "slash" => Some(Slash)
    "dot" => Some(Dot)
    "coloncol" => Some(ColonColon)
    _ => None
  }
}

///|
/// Converts ModulePathStyle to string representation.
pub fn ModulePathStyle::as_string(self : ModulePathStyle) -> String {
  match self {
    Slash => "slash"
    Dot => "dot"
    ColonColon => "coloncol"
  }
}

///|
/// ResolveStepType represents the type of resolution step.
pub enum ResolveStepType {
  /// Read a field from a manifest file (package.json, Cargo.toml)
  Manifest
  /// Check if a marker file exists (__init__.py)
  Marker
  /// Try index files in a directory (/index.ts, /index.js)
  Index
  /// Try adding file extensions (.ts, .js)
  Ext
  /// Try sibling file with same name (foo/ -> foo.rs)
  Sibling
  /// Apply fallback prefix for unresolved modules (npm:, pip:)
  Fallback
} derive(Eq, Show)

///|
/// Converts a string to ResolveStepType.
pub fn ResolveStepType::from_string(s : String) -> ResolveStepType? {
  match s {
    "manifest" => Some(Manifest)
    "marker" => Some(Marker)
    "index" => Some(Index)
    "ext" => Some(Ext)
    "sibling" => Some(Sibling)
    "fallback" => Some(Fallback)
    _ => None
  }
}

///|
/// Converts ResolveStepType to string representation.
pub fn ResolveStepType::as_string(self : ResolveStepType) -> String {
  match self {
    Manifest => "manifest"
    Marker => "marker"
    Index => "index"
    Ext => "ext"
    Sibling => "sibling"
    Fallback => "fallback"
  }
}

///|
/// ResolveStep represents a single step in the resolution chain.
pub struct ResolveStep {
  /// Type of this resolution step
  step_type : ResolveStepType
  /// For Manifest: the manifest file name (package.json, Cargo.toml)
  file : String
  /// For Manifest: JSONPath-like query (exports["."].types, main)
  query : String
  /// For Marker/Index/Ext/Sibling: list of files or extensions
  files : Array[String]
  /// For Fallback: the prefix to apply (npm:, pip:)
  prefix : String
  /// Optional condition (type, value, browser, node)
  when_condition : String
}

///|
/// Creates a new ResolveStep with the specified parameters.
pub fn ResolveStep::new(
  step_type : ResolveStepType,
  file? : String = "",
  query? : String = "",
  files? : Array[String] = [],
  prefix? : String = "",
  when_condition? : String = "",
) -> ResolveStep {
  { step_type, file, query, files, prefix, when_condition }
}

///|
/// Creates a Manifest resolve step.
pub fn ResolveStep::manifest(
  file : String,
  query : String,
  when_condition? : String = "",
) -> ResolveStep {
  ResolveStep::new(Manifest, file~, query~, when_condition~)
}

///|
/// Creates a Marker resolve step.
pub fn ResolveStep::marker(files : Array[String]) -> ResolveStep {
  ResolveStep::new(Marker, files~)
}

///|
/// Creates an Index resolve step.
pub fn ResolveStep::index(files : Array[String]) -> ResolveStep {
  ResolveStep::new(Index, files~)
}

///|
/// Creates an Ext resolve step.
pub fn ResolveStep::ext(files : Array[String]) -> ResolveStep {
  ResolveStep::new(Ext, files~)
}

///|
/// Creates a Sibling resolve step.
pub fn ResolveStep::sibling(files : Array[String]) -> ResolveStep {
  ResolveStep::new(Sibling, files~)
}

///|
/// Creates a Fallback resolve step.
pub fn ResolveStep::fallback(prefix : String) -> ResolveStep {
  ResolveStep::new(Fallback, prefix~)
}

///|
/// Returns the step type.
pub fn ResolveStep::get_step_type(self : ResolveStep) -> ResolveStepType {
  self.step_type
}

///|
/// Returns the manifest file name.
pub fn ResolveStep::get_file(self : ResolveStep) -> String {
  self.file
}

///|
/// Returns the query string.
pub fn ResolveStep::get_query(self : ResolveStep) -> String {
  self.query
}

///|
/// Returns the files list.
pub fn ResolveStep::get_files(self : ResolveStep) -> Array[String] {
  self.files
}

///|
/// Returns the prefix.
pub fn ResolveStep::get_prefix(self : ResolveStep) -> String {
  self.prefix
}

///|
/// Returns the when condition.
pub fn ResolveStep::get_when_condition(self : ResolveStep) -> String {
  self.when_condition
}

///|
/// Checks if this step has a condition.
pub fn ResolveStep::has_condition(self : ResolveStep) -> Bool {
  self.when_condition.length() > 0
}

///|
/// ResolverAlias represents a path alias for module resolution.
pub struct ResolverAlias {
  pattern : String
  replace : String
}

///|
/// Creates a new ResolverAlias with the specified parameters.
pub fn ResolverAlias::new(pattern : String, replace : String) -> ResolverAlias {
  { pattern, replace }
}

///|
/// Returns the pattern of the alias.
pub fn ResolverAlias::get_pattern(self : ResolverAlias) -> String {
  self.pattern
}

///|
/// Returns the replacement of the alias.
pub fn ResolverAlias::get_replace(self : ResolverAlias) -> String {
  self.replace
}

///|
/// ResolverSpec represents the configuration for module resolution.
pub struct ResolverSpec {
  sources : Array[String]
  relative_prefixes : Array[String]
  exts : Array[String]
  indexes : Array[String]
  bare_prefix : String
  module_path_style : ModulePathStyle
  aliases : Array[ResolverAlias]
  ns_prefix : String?
  ns_segments : Int
  rust_mod_mode : Bool
  cargo_auto_from_roots : Array[String]
  /// Resolution chain for conditional/manifest-based resolution
  resolve_chain : Array[ResolveStep]
}

///|
/// Creates a new ResolverSpec with the specified parameters.
pub fn ResolverSpec::new(
  sources? : Array[String] = [],
  relative_prefixes? : Array[String] = [],
  exts? : Array[String] = [],
  indexes? : Array[String] = [],
  bare_prefix? : String = "",
  module_path_style? : ModulePathStyle = Slash,
  aliases? : Array[ResolverAlias] = [],
  ns_prefix? : String? = None,
  ns_segments? : Int = 0,
  rust_mod_mode? : Bool = false,
  cargo_auto_from_roots? : Array[String] = [],
  resolve_chain? : Array[ResolveStep] = [],
) -> ResolverSpec {
  {
    sources,
    relative_prefixes,
    exts,
    indexes,
    bare_prefix,
    module_path_style,
    aliases,
    ns_prefix,
    ns_segments,
    rust_mod_mode,
    cargo_auto_from_roots,
    resolve_chain,
  }
}

///|
/// Returns the sources directories.
pub fn ResolverSpec::get_sources(self : ResolverSpec) -> Array[String] {
  self.sources
}

///|
/// Returns the relative prefixes.
pub fn ResolverSpec::get_relative_prefixes(
  self : ResolverSpec,
) -> Array[String] {
  self.relative_prefixes
}

///|
/// Returns the file extensions.
pub fn ResolverSpec::get_exts(self : ResolverSpec) -> Array[String] {
  self.exts
}

///|
/// Returns the index file names.
pub fn ResolverSpec::get_indexes(self : ResolverSpec) -> Array[String] {
  self.indexes
}

///|
/// Returns the bare prefix.
pub fn ResolverSpec::get_bare_prefix(self : ResolverSpec) -> String {
  self.bare_prefix
}

///|
/// Returns the module path style.
pub fn ResolverSpec::get_module_path_style(
  self : ResolverSpec,
) -> ModulePathStyle {
  self.module_path_style
}

///|
/// Returns the aliases.
pub fn ResolverSpec::get_aliases(self : ResolverSpec) -> Array[ResolverAlias] {
  self.aliases
}

///|
/// Returns the namespace prefix.
pub fn ResolverSpec::get_ns_prefix(self : ResolverSpec) -> String? {
  self.ns_prefix
}

///|
/// Returns the namespace segments count.
pub fn ResolverSpec::get_ns_segments(self : ResolverSpec) -> Int {
  self.ns_segments
}

///|
/// Returns whether rust mod mode is enabled.
pub fn ResolverSpec::is_rust_mod_mode(self : ResolverSpec) -> Bool {
  self.rust_mod_mode
}

///|
/// Returns the cargo auto from roots.
pub fn ResolverSpec::get_cargo_auto_from_roots(
  self : ResolverSpec,
) -> Array[String] {
  self.cargo_auto_from_roots
}

///|
/// Returns the resolve chain.
pub fn ResolverSpec::get_resolve_chain(
  self : ResolverSpec,
) -> Array[ResolveStep] {
  self.resolve_chain
}

///|
/// Checks if the resolver has a resolve chain defined.
pub fn ResolverSpec::has_resolve_chain(self : ResolverSpec) -> Bool {
  self.resolve_chain.length() > 0
}
