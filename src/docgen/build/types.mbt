// Types for documentation build configuration.

///|
/// Documentation generation configuration.
pub struct DocConfig {
  files : Array[(String, String)]
  specs : Map[String, @kgf_types.KGFSpec]
  options : @render.RenderOptions
  root_path : String
}

///|
/// Create a new DocConfig.
pub fn DocConfig::new(
  files : Array[(String, String)],
  specs : Map[String, @kgf_types.KGFSpec],
  options? : @render.RenderOptions = @render.RenderOptions::default(),
  root_path? : String = "",
) -> DocConfig {
  { files, specs, options, root_path }
}

// Getters

///|
/// Get the files to process as (path, content) pairs.
pub fn DocConfig::get_files(self : DocConfig) -> Array[(String, String)] {
  self.files
}

///|
/// Get the KGF specs map by language name.
pub fn DocConfig::get_specs(
  self : DocConfig,
) -> Map[String, @kgf_types.KGFSpec] {
  self.specs
}

///|
/// Get the render options.
pub fn DocConfig::get_options(self : DocConfig) -> @render.RenderOptions {
  self.options
}

///|
/// Get the root path for resolution.
pub fn DocConfig::get_root_path(self : DocConfig) -> String {
  self.root_path
}
