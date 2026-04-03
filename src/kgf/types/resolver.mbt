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
pub(all) enum ResolveStepType {
  /// Check if the target path exists as-is (exact match)
  Exact
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
  /// Walk ancestor directories searching for a package directory (node_modules/, vendor/)
  Ancestors
  /// Apply fallback prefix for unresolved modules (npm:, pip:)
  Fallback
} derive(Eq, Show)

///|
/// Converts a string to ResolveStepType.
pub fn ResolveStepType::from_string(s : String) -> ResolveStepType? {
  match s {
    "exact" => Some(Exact)
    "manifest" => Some(Manifest)
    "marker" => Some(Marker)
    "index" => Some(Index)
    "ext" => Some(Ext)
    "sibling" => Some(Sibling)
    "ancestors" => Some(Ancestors)
    "fallback" => Some(Fallback)
    _ => None
  }
}

///|
/// Converts ResolveStepType to string representation.
pub fn ResolveStepType::as_string(self : ResolveStepType) -> String {
  match self {
    Exact => "exact"
    Manifest => "manifest"
    Marker => "marker"
    Index => "index"
    Ext => "ext"
    Sibling => "sibling"
    Ancestors => "ancestors"
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
/// Creates an Exact resolve step (checks target path as-is).
pub fn ResolveStep::exact() -> ResolveStep {
  ResolveStep::new(Exact)
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
/// Creates an Ancestors resolve step (walks up from file to root).
pub fn ResolveStep::ancestors(dirs : Array[String]) -> ResolveStep {
  ResolveStep::new(Ancestors, files=dirs)
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
  /// Resolution chain for conditional/manifest-based resolution
  resolve_chain : Array[ResolveStep]
  /// Project-level config file (moon.mod.json, package.json, Cargo.toml, etc.)
  project_config : String
  /// Install command template. Use {name} as placeholder for package name.
  install_cmd : String
  /// Build command template.
  build_cmd : String
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
  resolve_chain? : Array[ResolveStep] = [],
  project_config? : String = "",
  install_cmd? : String = "",
  build_cmd? : String = "",
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
    resolve_chain,
    project_config,
    install_cmd,
    build_cmd,
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

///|
/// Returns the project config file name (e.g., moon.mod.json).
pub fn ResolverSpec::get_project_config(self : ResolverSpec) -> String {
  self.project_config
}

///|
/// Returns the install command template.
pub fn ResolverSpec::get_install_cmd(self : ResolverSpec) -> String {
  self.install_cmd
}

///|
/// Returns the build command template.
pub fn ResolverSpec::get_build_cmd(self : ResolverSpec) -> String {
  self.build_cmd
}

///|
/// ResolutionStats tracks statistics for module resolution performance.
pub struct ResolutionStats {
  /// Number of cache hits
  mut cache_hits : Int
  /// Number of cache misses
  mut cache_misses : Int
  /// Number of file existence checks
  mut file_checks : Int
  /// Number of circular references detected
  mut circular_detected : Int
} derive(Eq, Show)

///|
/// Creates a new ResolutionStats with zero counts.
pub fn ResolutionStats::new() -> ResolutionStats {
  { cache_hits: 0, cache_misses: 0, file_checks: 0, circular_detected: 0 }
}

///|
/// ResolutionCache caches module resolution results for performance.
pub struct ResolutionCache {
  /// Cache of resolved paths: cache_key -> resolved_path
  resolved_paths : Map[String, String]
  /// Cache of file existence checks: path -> exists
  file_exists_cache : Map[String, Bool]
  /// Stack of modules currently being resolved (for circular detection)
  resolution_stack : Array[String]
  /// Set of modules currently being resolved (O(1) circular detection)
  resolving_set : Map[String, Bool]
  /// Detected circular references: (from_file, module_path)
  circular_refs : Array[(String, String)]
  /// Statistics
  stats : ResolutionStats
}

///|
/// Creates a new empty ResolutionCache.
pub fn ResolutionCache::new() -> ResolutionCache {
  {
    resolved_paths: {},
    file_exists_cache: {},
    resolution_stack: [],
    resolving_set: {},
    circular_refs: [],
    stats: ResolutionStats::new(),
  }
}

///|
/// Generates a cache key from from_file and module_path.
pub fn ResolutionCache::make_key(
  from_file : String,
  module_path : String,
) -> String {
  from_file + "::" + module_path
}

///|
/// Gets a cached resolution result.
pub fn ResolutionCache::get(self : ResolutionCache, key : String) -> String? {
  self.resolved_paths.get(key)
}

///|
/// Sets a cached resolution result.
pub fn ResolutionCache::set(
  self : ResolutionCache,
  key : String,
  value : String,
) -> Unit {
  self.resolved_paths.set(key, value)
}

///|
/// Checks if a module is currently being resolved (circular detection).
pub fn ResolutionCache::is_resolving(
  self : ResolutionCache,
  key : String,
) -> Bool {
  self.resolving_set.contains(key)
}

///|
/// Pushes a module onto the resolution stack.
pub fn ResolutionCache::push_resolving(
  self : ResolutionCache,
  key : String,
) -> Unit {
  self.resolution_stack.push(key)
  self.resolving_set.set(key, true)
}

///|
/// Pops a module from the resolution stack.
pub fn ResolutionCache::pop_resolving(self : ResolutionCache) -> Unit {
  if self.resolution_stack.length() > 0 {
    let key = self.resolution_stack.pop().unwrap()
    self.resolving_set.remove(key)
  }
}

///|
/// Records a circular reference.
pub fn ResolutionCache::record_circular(
  self : ResolutionCache,
  from_file : String,
  module_path : String,
) -> Unit {
  self.circular_refs.push((from_file, module_path))
  self.stats.circular_detected += 1
}

///|
/// Returns detected circular references.
pub fn ResolutionCache::get_circular_refs(
  self : ResolutionCache,
) -> Array[(String, String)] {
  self.circular_refs
}

///|
/// Records a cache hit.
pub fn ResolutionCache::record_hit(self : ResolutionCache) -> Unit {
  self.stats.cache_hits += 1
}

///|
/// Records a cache miss.
pub fn ResolutionCache::record_miss(self : ResolutionCache) -> Unit {
  self.stats.cache_misses += 1
}

///|
/// Records a file check.
pub fn ResolutionCache::record_file_check(self : ResolutionCache) -> Unit {
  self.stats.file_checks += 1
}

///|
/// Gets the statistics.
pub fn ResolutionCache::get_stats(self : ResolutionCache) -> ResolutionStats {
  self.stats
}

///|
/// Checks file existence with caching.
pub fn ResolutionCache::check_file_exists(
  self : ResolutionCache,
  path : String,
  file_exists_fn : (String) -> Bool,
) -> Bool {
  match self.file_exists_cache.get(path) {
    Some(exists) => exists
    None => {
      self.record_file_check()
      let exists = file_exists_fn(path)
      self.file_exists_cache.set(path, exists)
      exists
    }
  }
}

///|
/// Sentinel prefix for circular dependency detection.
pub let circular_sentinel_prefix : String = "circular:"
