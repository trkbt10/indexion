///|
type AgentOrientConfig = @types.AgentOrientConfig

///|
type AgentOrientMap = @types.AgentOrientMap

///|
type AgentOrientMapFile = @types.AgentOrientMapFile

///|
type AgentOrientMapOwner = @types.AgentOrientMapOwner

///|
type AgentOrientMapStatus = @types.AgentOrientMapStatus

///|
type LocalDocSource = @types.LocalDocSource

///|
type LocalFileBrief = @types.LocalFileBrief

///|
type LocalWikiManifest = @types.LocalWikiManifest

///|
type LocalWikiPage = @types.LocalWikiPage

///|
fn map_file_is_consumer(file : AgentOrientMapFile) -> Bool {
  @matching.map_file_is_consumer(file)
}

///|
pub fn version() -> String {
  "agent-orient-map-v1"
}

///|
/// Load and save the persisted agent orient map cache.
pub fn orient_map_path(config : AgentOrientConfig) -> String {
  config.cache_dir + "/orient-map.json"
}

///|
pub fn load_cached(config : AgentOrientConfig) -> AgentOrientMap? {
  let path = orient_map_path(config)
  let content = @fs.read_file_to_string(path) catch { _ => return None }
  let json = @json.parse(content) catch { _ => return None }
  let map : AgentOrientMap = @json.from_json(json) catch { _ => return None }
  if map.version == version() {
    Some(map)
  } else {
    None
  }
}

///|
pub fn save(config : AgentOrientConfig, map : AgentOrientMap) -> Unit {
  @config_paths.ensure_dir_recursive(config.cache_dir)
  @fs.write_string_to_file(
    orient_map_path(config),
    map.to_json().stringify(indent=2) + "\n",
  ) catch {
    _ => ()
  }
}
