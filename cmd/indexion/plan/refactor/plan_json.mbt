///|
/// Intermediate representation for refactoring plan.
/// Can be serialized to JSON and converted to Markdown, text, etc.

///|
/// Configuration summary for the refactoring analysis.
pub struct ConfigSummary {
  target_dir : String
  threshold : Double
  strategy : String
  includes : Array[String]
  excludes : Array[String]
}

///|
/// Similar file pair with similarity score and excerpt previews.
pub struct SimilarPairJSON {
  file1 : String
  file2 : String
  similarity : Double
  preview1 : String // excerpt from file1
  preview2 : String // excerpt from file2
}

///|
/// Duplicate code block found between files.
pub struct DuplicateBlockJSON {
  file1 : String
  file2 : String
  start_line1 : Int
  start_line2 : Int
  line_count : Int
  func_name : String?
  preview : String
}

///|
/// Refactoring suggestion for a cluster.
pub struct RefactorSuggestion {
  shared_module : String
  functions_to_extract : Array[String]
  affected_files : Array[String]
}

///|
/// Cluster of related files with suggestions.
pub struct ClusterJSON {
  group_id : Int
  files : Array[String]
  pairs : Array[SimilarPairJSON]
  duplicates : Array[DuplicateBlockJSON]
  suggestions : RefactorSuggestion
}

///|
/// A pair of structurally similar functions detected across or within files.
pub struct FunctionDuplicate {
  func1 : String
  func2 : String
  file1 : String
  file2 : String
  similarity : Double
  same_file : Bool
} derive(ToJson)

///|
/// Summary statistics for the plan.
pub struct PlanSummary {
  total_clusters : Int
  total_files_analyzed : Int
  max_similarity : Double
}

///|
/// Complete refactoring plan in intermediate format.
pub struct RefactorPlanJSON {
  config : ConfigSummary
  clusters : Array[ClusterJSON]
  function_duplicates : Array[FunctionDuplicate]
  mut summary : PlanSummary
}

///|
/// Create a new empty refactoring plan.
pub fn RefactorPlanJSON::new(config : ConfigSummary) -> RefactorPlanJSON {
  {
    config,
    clusters: [],
    function_duplicates: [],
    summary: { total_clusters: 0, total_files_analyzed: 0, max_similarity: 0.0 },
  }
}

///|
/// Add a cluster to the plan.
pub fn RefactorPlanJSON::add_cluster(
  self : RefactorPlanJSON,
  cluster : ClusterJSON,
) -> Unit {
  self.clusters.push(cluster)
}

///|
/// Update summary statistics.
pub fn RefactorPlanJSON::update_summary(
  self : RefactorPlanJSON,
  total_files : Int,
) -> Unit {
  let mut max_sim = 0.0
  for cluster in self.clusters {
    for pair in cluster.pairs {
      if pair.similarity > max_sim {
        max_sim = pair.similarity
      }
    }
  }
  self.summary = {
    total_clusters: self.clusters.length(),
    total_files_analyzed: total_files,
    max_similarity: max_sim,
  }
}

///|
/// Convert to JSON.
pub fn RefactorPlanJSON::to_json(self : RefactorPlanJSON) -> Json {
  let root : Map[String, Json] = Map::new()
  // Config
  let config_obj : Map[String, Json] = Map::new()
  config_obj.set("target_dir", self.config.target_dir.to_json())
  config_obj.set("threshold", self.config.threshold.to_json())
  config_obj.set("strategy", self.config.strategy.to_json())
  config_obj.set("includes", json_string_array(self.config.includes))
  config_obj.set("excludes", json_string_array(self.config.excludes))
  root.set("config", Json::object(config_obj))
  // Clusters
  let clusters_arr : Array[Json] = []
  for cluster in self.clusters {
    clusters_arr.push(cluster_to_json(cluster))
  }
  root.set("clusters", Json::array(clusters_arr))
  // Summary
  let summary_obj : Map[String, Json] = Map::new()
  summary_obj.set("total_clusters", self.summary.total_clusters.to_json())
  summary_obj.set(
    "total_files_analyzed",
    self.summary.total_files_analyzed.to_json(),
  )
  summary_obj.set("max_similarity", self.summary.max_similarity.to_json())
  root.set("summary", Json::object(summary_obj))
  Json::object(root)
}

///|
fn json_string_array(arr : Array[String]) -> Json {
  let result : Array[Json] = []
  for s in arr {
    result.push(s.to_json())
  }
  Json::array(result)
}

///|
fn cluster_to_json(cluster : ClusterJSON) -> Json {
  let obj : Map[String, Json] = Map::new()
  obj.set("group_id", cluster.group_id.to_json())
  obj.set("files", json_string_array(cluster.files))
  // Pairs
  let pairs_arr : Array[Json] = []
  for pair in cluster.pairs {
    let pair_obj : Map[String, Json] = Map::new()
    pair_obj.set("file1", pair.file1.to_json())
    pair_obj.set("file2", pair.file2.to_json())
    pair_obj.set("similarity", pair.similarity.to_json())
    pair_obj.set("preview1", pair.preview1.to_json())
    pair_obj.set("preview2", pair.preview2.to_json())
    pairs_arr.push(Json::object(pair_obj))
  }
  obj.set("pairs", Json::array(pairs_arr))
  // Duplicates
  let dups_arr : Array[Json] = []
  for dup in cluster.duplicates {
    let dup_obj : Map[String, Json] = Map::new()
    dup_obj.set("file1", dup.file1.to_json())
    dup_obj.set("file2", dup.file2.to_json())
    dup_obj.set("start_line1", dup.start_line1.to_json())
    dup_obj.set("start_line2", dup.start_line2.to_json())
    dup_obj.set("line_count", dup.line_count.to_json())
    match dup.func_name {
      Some(name) => dup_obj.set("func_name", name.to_json())
      None => ()
    }
    dup_obj.set("preview", dup.preview.to_json())
    dups_arr.push(Json::object(dup_obj))
  }
  obj.set("duplicates", Json::array(dups_arr))
  // Suggestions
  let sugg_obj : Map[String, Json] = Map::new()
  sugg_obj.set("shared_module", cluster.suggestions.shared_module.to_json())
  sugg_obj.set(
    "functions_to_extract",
    json_string_array(cluster.suggestions.functions_to_extract),
  )
  sugg_obj.set(
    "affected_files",
    json_string_array(cluster.suggestions.affected_files),
  )
  obj.set("suggestions", Json::object(sugg_obj))
  Json::object(obj)
}

///|
/// Parse from JSON.
pub fn RefactorPlanJSON::from_json(json : Json) -> RefactorPlanJSON? {
  match json {
    Object(root) => {
      // Parse config
      let config = match root.get("config") {
        Some(Object(cfg)) => parse_config(cfg)
        _ => return None
      }
      let plan = RefactorPlanJSON::new(config)
      // Parse clusters
      match root.get("clusters") {
        Some(Array(clusters_arr)) =>
          for cluster_json in clusters_arr {
            match parse_cluster(cluster_json) {
              Some(cluster) => plan.clusters.push(cluster)
              None => ()
            }
          }
        _ => ()
      }
      // Parse summary
      match root.get("summary") {
        Some(Object(sum)) => {
          let total_clusters = match sum.get("total_clusters") {
            Some(Number(n, ..)) => n.to_int()
            _ => plan.clusters.length()
          }
          let total_files = match sum.get("total_files_analyzed") {
            Some(Number(n, ..)) => n.to_int()
            _ => 0
          }
          let max_sim = match sum.get("max_similarity") {
            Some(Number(n, ..)) => n
            _ => 0.0
          }
          plan.summary = {
            total_clusters,
            total_files_analyzed: total_files,
            max_similarity: max_sim,
          }
        }
        _ => plan.update_summary(0)
      }
      Some(plan)
    }
    _ => None
  }
}

///|
fn parse_config(cfg : Map[String, Json]) -> ConfigSummary {
  let target_dir = match cfg.get("target_dir") {
    Some(String(s)) => s
    _ => ""
  }
  let threshold = match cfg.get("threshold") {
    Some(Number(n, ..)) => n
    _ => 0.7
  }
  let strategy = match cfg.get("strategy") {
    Some(String(s)) => s
    _ => "tfidf"
  }
  let includes = parse_string_array(cfg.get("includes"))
  let excludes = parse_string_array(cfg.get("excludes"))
  { target_dir, threshold, strategy, includes, excludes }
}

///|
fn parse_string_array(json : Json?) -> Array[String] {
  let result : Array[String] = []
  match json {
    Some(Array(arr)) =>
      for item in arr {
        match item {
          String(s) => result.push(s)
          _ => ()
        }
      }
    _ => ()
  }
  result
}

///|
fn parse_cluster(json : Json) -> ClusterJSON? {
  match json {
    Object(obj) => {
      let group_id = match obj.get("group_id") {
        Some(Number(n, ..)) => n.to_int()
        _ => 0
      }
      let files = parse_string_array(obj.get("files"))
      // Parse pairs
      let pairs : Array[SimilarPairJSON] = []
      match obj.get("pairs") {
        Some(Array(pairs_arr)) =>
          for pair_json in pairs_arr {
            match pair_json {
              Object(pair_obj) => {
                let file1 = match pair_obj.get("file1") {
                  Some(String(s)) => s
                  _ => continue
                }
                let file2 = match pair_obj.get("file2") {
                  Some(String(s)) => s
                  _ => continue
                }
                let similarity = match pair_obj.get("similarity") {
                  Some(Number(n, ..)) => n
                  _ => 0.0
                }
                let preview1 = match pair_obj.get("preview1") {
                  Some(String(s)) => s
                  _ => ""
                }
                let preview2 = match pair_obj.get("preview2") {
                  Some(String(s)) => s
                  _ => ""
                }
                pairs.push({ file1, file2, similarity, preview1, preview2 })
              }
              _ => ()
            }
          }
        _ => ()
      }
      // Parse duplicates
      let duplicates : Array[DuplicateBlockJSON] = []
      match obj.get("duplicates") {
        Some(Array(dups_arr)) =>
          for dup_json in dups_arr {
            match dup_json {
              Object(dup_obj) => {
                let file1 = match dup_obj.get("file1") {
                  Some(String(s)) => s
                  _ => continue
                }
                let file2 = match dup_obj.get("file2") {
                  Some(String(s)) => s
                  _ => continue
                }
                let start_line1 = match dup_obj.get("start_line1") {
                  Some(Number(n, ..)) => n.to_int()
                  _ => 0
                }
                let start_line2 = match dup_obj.get("start_line2") {
                  Some(Number(n, ..)) => n.to_int()
                  _ => 0
                }
                let line_count = match dup_obj.get("line_count") {
                  Some(Number(n, ..)) => n.to_int()
                  _ => 0
                }
                let func_name : String? = match dup_obj.get("func_name") {
                  Some(String(s)) => Some(s)
                  _ => None
                }
                let preview = match dup_obj.get("preview") {
                  Some(String(s)) => s
                  _ => ""
                }
                duplicates.push({
                  file1,
                  file2,
                  start_line1,
                  start_line2,
                  line_count,
                  func_name,
                  preview,
                })
              }
              _ => ()
            }
          }
        _ => ()
      }
      // Parse suggestions
      let suggestions = match obj.get("suggestions") {
        Some(Object(sugg_obj)) => {
          let shared_module = match sugg_obj.get("shared_module") {
            Some(String(s)) => s
            _ => ""
          }
          let functions_to_extract = parse_string_array(
            sugg_obj.get("functions_to_extract"),
          )
          let affected_files = parse_string_array(
            sugg_obj.get("affected_files"),
          )
          { shared_module, functions_to_extract, affected_files }
        }
        _ => { shared_module: "", functions_to_extract: [], affected_files: [] }
      }
      Some({ group_id, files, pairs, duplicates, suggestions })
    }
    _ => None
  }
}

///|
/// Extract preview text from content using sentence-aware splitting.
/// Uses segmentation/sentence to properly detect sentence boundaries
/// for both Japanese and English text.
fn extract_preview(content : String, max_chars : Int) -> String {
  // Use sentence splitter (supports Japanese and English)
  let sentences = @sentence.split_sentences_text(content)
  if sentences.length() == 0 {
    // Fallback: return truncated content
    let chars = content.to_array()
    if chars.length() <= max_chars {
      return trim_leading_whitespace(content)
    }
    let result : Array[Char] = []
    for i = 0; i < max_chars; i = i + 1 {
      result.push(chars[i])
    }
    return trim_leading_whitespace(String::from_array(result))
  }
  // Collect sentences until we reach max_chars
  let buf = StringBuilder::new()
  let mut total_len = 0
  for sentence in sentences {
    let sentence_len = sentence.to_array().length()
    if total_len + sentence_len > max_chars && total_len > 0 {
      break
    }
    buf.write_string(sentence)
    total_len = total_len + sentence_len
  }
  trim_leading_whitespace(buf.to_string())
}

///|
/// Trim leading whitespace from text.
fn trim_leading_whitespace(text : String) -> String {
  let chars = text.to_array()
  let mut start = 0
  while start < chars.length() &&
        (
          chars[start] == ' ' ||
          chars[start] == '\t' ||
          chars[start] == '\n' ||
          chars[start] == '\r' ||
          chars[start] == '　'
        ) {
    start = start + 1
  }
  if start == 0 {
    return text
  }
  let result : Array[Char] = []
  for i = start; i < chars.length(); i = i + 1 {
    result.push(chars[i])
  }
  String::from_array(result)
}

///|
/// Build a refactoring plan from analysis results.
pub fn build_refactor_plan(
  clusters : Array[FileCluster],
  config : RefactorPlanConfig,
  file_contents : Map[String, String],
  effective_threshold? : Double = 0.0,
  registry? : @kgf_registry.KGFRegistry? = None,
) -> RefactorPlanJSON {
  let threshold = if effective_threshold > 0.0 {
    effective_threshold
  } else {
    config.threshold
  }
  let plan_config : ConfigSummary = {
    target_dir: config.target_dir,
    threshold,
    strategy: config.strategy,
    includes: config.includes,
    excludes: config.excludes,
  }
  let plan = RefactorPlanJSON::new(plan_config)
  // Cache previews to avoid recomputing for the same file
  let preview_cache : Map[String, String] = {}
  for i, cluster in clusters {
    let group_id = i + 1
    // Convert all pairs with cached previews (for JSON output)
    let pairs : Array[SimilarPairJSON] = []
    for pair in cluster.pairs {
      let preview1 = match preview_cache.get(pair.file1) {
        Some(cached) => cached
        None => {
          let p = match file_contents.get(pair.file1) {
            Some(content) => extract_preview(content, 200)
            None => ""
          }
          preview_cache.set(pair.file1, p)
          p
        }
      }
      let preview2 = match preview_cache.get(pair.file2) {
        Some(cached) => cached
        None => {
          let p = match file_contents.get(pair.file2) {
            Some(content) => extract_preview(content, 200)
            None => ""
          }
          preview_cache.set(pair.file2, p)
          p
        }
      }
      pairs.push({
        file1: pair.file1,
        file2: pair.file2,
        similarity: pair.similarity,
        preview1,
        preview2,
      })
    }
    // Find duplicates using similarity pairs (already sorted by similarity desc).
    // Use the pairs list instead of all file combinations — this ensures we focus
    // on the most similar file pairs, and avoids O(n²) explosion for large clusters.
    let duplicates : Array[DuplicateBlockJSON] = []
    let func_names : Array[String] = []
    let mut shared_module = ""
    let seen_file_pairs : Map[String, Bool] = {}
    // Cache line->func maps per file (built from KGF, language-agnostic)
    let line_func_cache : Map[String, Map[Int, String]] = {}
    let max_dup_comparisons = 200
    let mut dup_count = 0
    for pair in cluster.pairs {
      if dup_count >= max_dup_comparisons {
        break
      }
      // Deduplicate file pairs (pairs may contain near-duplicates)
      let pair_key = pair.file1 + "\t" + pair.file2
      match seen_file_pairs.get(pair_key) {
        Some(_) => continue
        None => seen_file_pairs.set(pair_key, true)
      }
      let file1 = pair.file1
      let file2 = pair.file2
      let content1 = file_contents.get(file1)
      let content2 = file_contents.get(file2)
      match (content1, content2) {
        (Some(c1), Some(c2)) => {
          // Build KGF line->func maps (cached per file)
          let lf1 = match line_func_cache.get(file1) {
            Some(m) => m
            None => {
              let m = @kgf_features.build_line_func_map(c1, file1, registry)
              line_func_cache.set(file1, m)
              m
            }
          }
          let lf2 = match line_func_cache.get(file2) {
            Some(m) => m
            None => {
              let m = @kgf_features.build_line_func_map(c2, file2, registry)
              line_func_cache.set(file2, m)
              m
            }
          }
          let blocks = find_duplicate_blocks(
            c1,
            c2,
            5,
            line_funcs1=lf1,
            line_funcs2=lf2,
          )
          for block in blocks {
            duplicates.push({
              file1,
              file2,
              start_line1: block.start_line1,
              start_line2: block.start_line2,
              line_count: block.line_count,
              func_name: block.func_name,
              preview: block.preview,
            })
            match block.func_name {
              Some(name) => {
                let mut exists = false
                for existing in func_names {
                  if existing == name {
                    exists = true
                    break
                  }
                }
                if not(exists) {
                  func_names.push(name)
                }
              }
              None => ()
            }
          }
          if shared_module.length() == 0 {
            shared_module = suggest_shared_module(file1, file2)
          }
        }
        _ => ()
      }
      dup_count = dup_count + 1
    }
    let suggestions : RefactorSuggestion = {
      shared_module,
      functions_to_extract: func_names,
      affected_files: cluster.files,
    }
    plan.add_cluster({
      group_id,
      files: cluster.files,
      pairs,
      duplicates,
      suggestions,
    })
  }
  plan.update_summary(file_contents.length())
  plan
}
