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
pub fn DocConfig::get_files(self : DocConfig) -> Array[(String, String)] {
  self.files
}

///|
pub fn DocConfig::get_specs(
  self : DocConfig,
) -> Map[String, @kgf_types.KGFSpec] {
  self.specs
}

///|
pub fn DocConfig::get_options(self : DocConfig) -> @render.RenderOptions {
  self.options
}

///|
pub fn DocConfig::get_root_path(self : DocConfig) -> String {
  self.root_path
}
