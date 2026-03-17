///|
/// Intermediate representation for unwrap candidate detection.

///|
/// Configuration summary.
pub struct UnwrapPlanConfig {
  target_dir : String
  includes : Array[String]
  excludes : Array[String]
}

///|
/// A single detected wrapper function to unwrap.
pub struct UnwrapEntry {
  file : String
  line : Int
  name : String
  delegate_target : String
  params : Array[String]
  delegate_args : Array[String]
  all_forwarded : Bool
}

///|
/// Summary statistics.
pub struct UnwrapSummary {
  total_files_scanned : Int
  total_functions_scanned : Int
  unwrap_count : Int
}

///|
/// Complete unwrap candidate plan.
pub struct UnwrapPlanJSON {
  config : UnwrapPlanConfig
  candidates : Array[UnwrapEntry]
  summary : UnwrapSummary
}

///|
/// Convert to JSON.
pub fn UnwrapPlanJSON::to_json(self : UnwrapPlanJSON) -> Json {
  let root : Map[String, Json] = Map::new()
  // Config
  let cfg : Map[String, Json] = Map::new()
  cfg.set("target_dir", self.config.target_dir.to_json())
  let inc_arr : Array[Json] = []
  for s in self.config.includes {
    inc_arr.push(s.to_json())
  }
  cfg.set("includes", Json::array(inc_arr))
  let exc_arr : Array[Json] = []
  for s in self.config.excludes {
    exc_arr.push(s.to_json())
  }
  cfg.set("excludes", Json::array(exc_arr))
  root.set("config", Json::object(cfg))
  // Candidates
  let cand_arr : Array[Json] = []
  for p in self.candidates {
    let obj : Map[String, Json] = Map::new()
    obj.set("file", p.file.to_json())
    obj.set("line", p.line.to_json())
    obj.set("name", p.name.to_json())
    obj.set("delegate_target", p.delegate_target.to_json())
    let params_arr : Array[Json] = []
    for s in p.params {
      params_arr.push(s.to_json())
    }
    obj.set("params", Json::array(params_arr))
    let args_arr : Array[Json] = []
    for s in p.delegate_args {
      args_arr.push(s.to_json())
    }
    obj.set("delegate_args", Json::array(args_arr))
    obj.set("all_forwarded", p.all_forwarded.to_json())
    cand_arr.push(Json::object(obj))
  }
  root.set("candidates", Json::array(cand_arr))
  // Summary
  let sum : Map[String, Json] = Map::new()
  sum.set("total_files_scanned", self.summary.total_files_scanned.to_json())
  sum.set(
    "total_functions_scanned",
    self.summary.total_functions_scanned.to_json(),
  )
  sum.set("unwrap_count", self.summary.unwrap_count.to_json())
  root.set("summary", Json::object(sum))
  Json::object(root)
}
