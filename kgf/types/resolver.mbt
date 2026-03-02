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
