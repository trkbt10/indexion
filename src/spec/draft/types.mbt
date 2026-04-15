///|
pub(all) struct DraftConfig {
  source_path : String
  specs_dir : String
  output : String
  format : String
  profile : String
  max_requirements : Int
} derive(Eq, Show, ToJson, @json.FromJson)

///|
pub fn DraftConfig::default() -> DraftConfig {
  {
    source_path: "",
    specs_dir: "",
    output: "",
    format: "markdown",
    profile: "sdd-requirement",
    max_requirements: 64,
  }
}

///|
pub struct DraftRequirement {
  id : String
  title : String
  description : String
  criteria : Array[String]
  source_file : String
  source_line : Int
  level : Int
} derive(Eq, Show, ToJson, @json.FromJson)

///|
pub struct DraftReport {
  version : String
  generated_at : Int
  config : DraftConfig
  source_files : Array[String]
  requirements : Array[DraftRequirement]
} derive(Eq, Show, ToJson, @json.FromJson)
