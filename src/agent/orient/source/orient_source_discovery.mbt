///|
type AgentOrientConfig = @types.AgentOrientConfig

///|
type AgentOrientMap = @types.AgentOrientMap

///|
type LocalFileBrief = @types.LocalFileBrief

///|
type AgentOrientMapFile = @types.AgentOrientMapFile

///|
fn task_tokens(text : String) -> Array[String] {
  @matching.task_tokens(text)
}

///|
fn infer_file_role(
  file : @pipeline.SupportedFile,
  structural_terms : Array[String],
  summary_terms : Array[String],
  outgoing_count : Int,
  incoming_count : Int,
  external_terms~ : Array[String],
) -> String {
  @matching.infer_file_role(
    file,
    structural_terms,
    summary_terms,
    outgoing_count,
    incoming_count,
    external_terms~,
  )
}

///|
fn role_is_cli_consumer(role : String) -> Bool {
  @matching.role_is_cli_consumer(role)
}

///|
fn role_is_documentation(role : String) -> Bool {
  @matching.role_is_documentation(role)
}

///|
fn owner_dir(path : String) -> String {
  @map.owner_dir(path)
}

///|
/// Discover supported source files, build a code graph, and derive structural
/// file briefs used by the agent orient map and report scoring.
pub fn discover_files(
  config : AgentOrientConfig,
  registry : @kgf_registry.KGFRegistry,
) -> Array[@pipeline.SupportedFile] {
  let kgf_ignore = registry.collect_ignore_patterns()
  let opts = @pipeline.DiscoverOptions::new(
    root_dir=@pipeline.root_dir_from_paths(config.paths),
    recursive=true,
    kgf_ignore~,
  )
  @pipeline.collect_supported_file_info(config.paths, opts, registry)
}

///|
pub fn build_graph(
  files : Array[@pipeline.SupportedFile],
  registry : @kgf_registry.KGFRegistry,
) -> @graph.CodeGraph {
  let inputs : Array[(String, String)] = []
  for file in files {
    inputs.push((file.path, file.content))
  }
  let doc_config = @build.DocConfig::new(inputs, registry.to_specs_map())
  @build.build_graph_only(doc_config)
}
