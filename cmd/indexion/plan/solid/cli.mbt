///|
/// # indexion plan solid
///
/// Generate solidification plan for extracting common code across packages.
///
/// ## Usage
///
/// ```bash
/// indexion plan solid --from=pkg1/,pkg2/ --to=components/
/// indexion plan solid --from=pkg1/,pkg2/ --rules=.solidrc
/// indexion plan solid --from=pkg1/,pkg2/ --to=components/ --rule="auth/** -> auth/"
/// ```

///|
/// CLI configuration.
pub(all) struct SolidConfig {
  from_dirs : Array[String] // source directories to compare
  to_dir : String // target directory for extraction
  rules_file : String // path to rules file (.solidrc)
  inline_rules : Array[String] // inline rules (--rule=...)
  threshold : Double // similarity threshold (default: 0.9)
  strategy : String // similarity strategy: tfidf, apted, tsed
  includes : Array[String] // glob patterns to include
  excludes : Array[String] // glob patterns to exclude
  output : String // output file path (empty = stdout)
  format : String // output format: "md", "json"
  specs_dir : String // KGF specs directory
}

///|
/// Create default configuration.
pub fn SolidConfig::default() -> SolidConfig {
  {
    from_dirs: [],
    to_dir: "",
    rules_file: "",
    inline_rules: [],
    threshold: 0.9,
    strategy: "tfidf",
    includes: [],
    excludes: [],
    output: "",
    format: "md",
    specs_dir: "kgfs",
  }
}

///|
/// Solidification rule: pattern -> target.
pub struct SolidRule {
  pattern : String // glob pattern (e.g., "auth/**")
  target : String // target path (relative or absolute with @)
}

///|
/// File match result.
priv struct FileMatch {
  _source1 : String // file from first source (dirname:path)
  _source2 : String // file from second source (dirname:path)
  similarity : Double
  relative_path : String // common relative path
  _matched_rule : SolidRule? // rule that matched, if any
}

///|
/// Create SolidConfig from argparse matches.
pub fn SolidConfig::from_matches(matches : @argparse.Matches) -> SolidConfig {
  // --from supports comma-separated values for backwards compatibility
  let from_dirs : Array[String] = []
  match matches.values.get("from") {
    Some(arr) =>
      for v in arr {
        let parts = @common.parse_comma_list(v)
        for d in parts {
          from_dirs.push(d)
        }
      }
    _ => ()
  }
  let to_dir = match matches.values.get("to") {
    Some(arr) => if arr.length() > 0 { arr[0] } else { "" }
    _ => ""
  }
  let rules_file = match matches.values.get("rules") {
    Some(arr) => if arr.length() > 0 { arr[0] } else { "" }
    _ => ""
  }
  let inline_rules = match matches.values.get("rule") {
    Some(arr) => arr
    _ => []
  }
  let threshold = match matches.values.get("threshold") {
    Some(arr) =>
      if arr.length() > 0 {
        @common.parse_double(arr[0])
      } else {
        0.9
      }
    _ => 0.9
  }
  let strategy = match matches.values.get("strategy") {
    Some(arr) => if arr.length() > 0 { arr[0] } else { "tfidf" }
    _ => "tfidf"
  }
  let includes = match matches.values.get("include") {
    Some(arr) => arr
    _ => []
  }
  let excludes = match matches.values.get("exclude") {
    Some(arr) => arr
    _ => []
  }
  let output = match matches.values.get("output") {
    Some(arr) => if arr.length() > 0 { arr[0] } else { "" }
    _ => ""
  }
  let format = match matches.values.get("format") {
    Some(arr) => if arr.length() > 0 { arr[0] } else { "md" }
    _ => "md"
  }
  let specs_dir = match matches.values.get("specs-dir") {
    Some(arr) => if arr.length() > 0 { arr[0] } else { "kgfs" }
    _ => "kgfs"
  }
  {
    from_dirs,
    to_dir,
    rules_file,
    inline_rules,
    threshold,
    strategy,
    includes,
    excludes,
    output,
    format,
    specs_dir,
  }
}

///|
/// Define the solid command for argparse.
pub fn command() -> @argparse.Command {
  @argparse.Command(
    "solid",
    about="Generate solidification plan for common code extraction",
    options=[
      @argparse.OptionArg(
        "from",
        action=Append,
        about="Source directories (comma-separated or repeatable)",
      ),
      @argparse.OptionArg("to", about="Target directory for extraction"),
      @argparse.OptionArg("rules", about="Rules file (.solidrc)"),
      @argparse.OptionArg(
        "rule",
        action=Append,
        about="Inline rule (repeatable)",
      ),
      @argparse.OptionArg("threshold", about="Similarity threshold (0.0-1.0)", default_values=[
        "0.9",
      ]),
      @argparse.OptionArg(
        "strategy",
        about="Similarity strategy: tfidf, apted, tsed",
        default_values=["tfidf"],
      ),
      @argparse.OptionArg("include", action=Append, about=@help.include_pattern),
      @argparse.OptionArg("exclude", action=Append, about=@help.exclude_pattern),
      @argparse.OptionArg("output", short='o', about=@help.output),
      @argparse.OptionArg(
        "format",
        about="Output format: md, json, github-issue",
        default_values=["md"],
      ),
      @argparse.OptionArg("specs-dir", about=@help.specs_dir, default_values=[
        "kgfs",
      ]),
    ],
  )
}

///|
/// Core solid analysis. Returns rendered output or None.
pub fn run_to_string(config : SolidConfig) -> String? {
  if config.from_dirs.length() < 2 {
    return None
  }
  let rules = load_rules(config)
  let matches = find_cross_matches(config)
  let categorized = categorize_matches(matches, rules, config.to_dir)
  let plan_json = build_plan_json(categorized, config, rules)
  let doc = solid_to_plan_document(plan_json)
  let output = match config.format {
    "github-issue" => {
      let issue = @plan_render.render_github_issue(doc)
      issue.format()
    }
    "json" => doc.to_json().stringify(indent=2)
    _ => @plan_render.render_markdown(doc)
  }
  Some(output)
}

///|
/// Entry point using argparse matches.
pub fn run_matches(matches : @argparse.Matches) -> Unit {
  let config = SolidConfig::from_matches(matches)
  match run_to_string(config) {
    Some(output) => @common.write_output(config.output, output, label="Plan")
    None =>
      println(
        "Error: At least 2 source directories required (--from=dir1,dir2)",
      )
  }
}

///|
/// Build intermediate JSON representation.
fn build_plan_json(
  categorized : CategorizedMatches,
  config : SolidConfig,
  rules : Array[SolidRule],
) -> SolidPlanJSON {
  // Extract unique source names (use parent dir if all are "src")
  let source_names = @common.extract_unique_dir_names(config.from_dirs)
  // Build extraction groups
  let extractions : Array[ExtractionGroup] = []
  for target, matches in categorized.by_target {
    let files : Array[ExtractionFile] = []
    for m in matches {
      let action = if m.similarity >= 0.99 {
        "Extract"
      } else {
        "Extract (review diff)"
      }
      files.push({
        relative_path: m.relative_path,
        similarity: m.similarity,
        action,
      })
    }
    extractions.push({ target_path: target, files })
  }
  // Build unmatched list
  let unmatched : Array[UnmatchedFile] = []
  for m in categorized.unmatched {
    unmatched.push({ relative_path: m.relative_path, similarity: m.similarity })
  }
  // Count matched
  let mut matched_count = 0
  for _, matches in categorized.by_target {
    matched_count = matched_count + matches.length()
  }
  {
    config: {
      sources: source_names,
      target: config.to_dir,
      threshold: config.threshold,
      rules_count: rules.length(),
    },
    summary: {
      total_matches: matched_count + unmatched.length(),
      matched_by_rules: matched_count,
      unmatched_count: unmatched.length(),
    },
    extractions,
    unmatched,
  }
}

// extract_unique_source_names, get_parent_dirname: use @common.extract_unique_dir_names (SoT)

// format_github_issue: use @plan_render.GitHubIssue::format (SoT)

///|
/// Load rules from file and inline arguments.
fn load_rules(config : SolidConfig) -> Array[SolidRule] {
  let rules : Array[SolidRule] = []
  // Load from rules file
  if config.rules_file.length() > 0 {
    try {
      let content = @fs.read_file_to_string(config.rules_file)
      let file_rules = parse_rules(content)
      for r in file_rules {
        rules.push(r)
      }
    } catch {
      _ => println("Warning: Could not read rules file: " + config.rules_file)
    }
  }
  // Add inline rules
  for rule_str in config.inline_rules {
    match parse_rule(rule_str) {
      Some(r) => rules.push(r)
      None => println("Warning: Invalid rule: " + rule_str)
    }
  }
  rules
}

///|
/// Parse rules from file content.
fn parse_rules(content : String) -> Array[SolidRule] {
  let rules : Array[SolidRule] = []
  let lines = @common.split_lines(content)
  for line in lines {
    let trimmed = @common.trim_ascii_spaces(line)
    // Skip empty lines and comments
    if trimmed.length() == 0 || trimmed.has_prefix("#") {
      continue
    }
    match parse_rule(trimmed) {
      Some(r) => rules.push(r)
      None => ()
    }
  }
  rules
}

///|
/// Parse single rule: "pattern -> target"
fn parse_rule(rule_str : String) -> SolidRule? {
  let chars = rule_str.to_array()
  // Find " -> "
  let mut arrow_pos = -1
  for i = 0; i < chars.length() - 3; i = i + 1 {
    if chars[i] == '-' && chars[i + 1] == '>' {
      arrow_pos = i
      break
    }
  }
  if arrow_pos < 0 {
    return None
  }
  // Extract pattern and target
  let pattern_chars : Array[Char] = []
  for i = 0; i < arrow_pos; i = i + 1 {
    pattern_chars.push(chars[i])
  }
  let target_start = if arrow_pos + 2 < chars.length() &&
    chars[arrow_pos + 2] == ' ' {
    arrow_pos + 3
  } else {
    arrow_pos + 2
  }
  let target_chars : Array[Char] = []
  for i = target_start; i < chars.length(); i = i + 1 {
    target_chars.push(chars[i])
  }
  let pattern = @common.trim_ascii_spaces(String::from_array(pattern_chars))
  let target = @common.trim_ascii_spaces(String::from_array(target_chars))
  if pattern.length() == 0 || target.length() == 0 {
    return None
  }
  Some({ pattern, target })
}

// split_lines: use @common (SoT)
// trim_string: use @common.trim_ascii_spaces (SoT)

///|
/// Find cross-directory matches above threshold.
fn find_cross_matches(config : SolidConfig) -> Array[FileMatch] {
  let matches : Array[FileMatch] = []
  // Collect files from all source directories
  let files = @common.collect_files(
    config.from_dirs,
    includes=config.includes,
    excludes=config.excludes,
  )
  if files.length() < 2 {
    return matches
  }
  let registry = @kgf_features.load_registry(
    specs_dir=config.specs_dir,
    target_dirs=config.from_dirs,
  )
  // Check if using tree-based strategy
  let is_tree_strategy = config.strategy == "apted" || config.strategy == "tsed"
  let pairs : Array[(Int, Int, Double)] = if is_tree_strategy {
    calculate_tree_pairs(files, config.strategy, config.threshold, registry)
  } else {
    let (tokenized, _) = @kgf_features.tokenize_files_with_kgf(files, registry)
    // Build TF-IDF batch
    let batch = @tfidf.TfidfBatch::from_tokens(tokenized)
    // Find pairs above threshold
    batch.all_pairs_above_threshold(config.threshold)
  }
  // Filter to cross-directory pairs
  for pair in pairs {
    let (i, j, sim) = pair
    let file1 = files[i].0
    let file2 = files[j].0
    let dir1 = @common.get_dirname_prefix(file1)
    let dir2 = @common.get_dirname_prefix(file2)
    // Only keep cross-directory pairs
    if dir1.length() > 0 && dir2.length() > 0 && dir1 != dir2 {
      let rel1 = @common.get_relative_part(file1)
      let rel2 = @common.get_relative_part(file2)
      // Only if relative paths match
      if rel1 == rel2 {
        matches.push({
          _source1: file1,
          _source2: file2,
          similarity: sim,
          relative_path: rel1,
          _matched_rule: None,
        })
      }
    }
  }
  // Sort by similarity descending
  matches.sort_by(fn(a, b) { b.similarity.compare(a.similarity) })
  matches
}

///|
/// Calculate tree-based similarity pairs (APTED/TSED).
fn calculate_tree_pairs(
  files : Array[(String, String)],
  strategy : String,
  threshold : Double,
  registry : @registry.KGFRegistry?,
) -> Array[(Int, Int, Double)] {
  let pairs : Array[(Int, Int, Double)] = []
  let resolved_registry = match registry {
    Some(r) => r
    None => return pairs
  }
  // Build function trees for each file
  let file_trees : Array[
    Array[(@kgf_features.ExtractedFunction, @apted.TreeNode)],
  ] = []
  for file in files {
    let (path, content) = file
    // Get relative path for language detection
    let rel_path = @common.get_relative_part(path)
    let trees : Array[(@kgf_features.ExtractedFunction, @apted.TreeNode)] = []
    match resolved_registry.detect_from_path(rel_path) {
      Some(lang) =>
        match resolved_registry.get_spec(lang) {
          Some(spec) => {
            let lexer = @kgf_lexer.Lexer::new(spec.get_tokens())
            let tokens = lexer.tokenize(content)
            let func_trees = @kgf_features.extract_function_trees(tokens, path, spec=spec)
            for ft in func_trees {
              trees.push(ft)
            }
          }
          None => ()
        }
      None => ()
    }
    file_trees.push(trees)
  }
  // Compare file pairs
  let cost_config = @apted.CostConfig::default()
  let tsed_config = @apted.TSEDConfig::default()
  for i = 0; i < files.length(); i = i + 1 {
    for j = i + 1; j < files.length(); j = j + 1 {
      let trees1 = file_trees[i]
      let trees2 = file_trees[j]
      if trees1.length() == 0 || trees2.length() == 0 {
        continue
      }
      // Calculate average similarity across function pairs
      let mut total_sim = 0.0
      let mut count = 0
      for t1 in trees1 {
        let (_, tree1) = t1
        for t2 in trees2 {
          let (_, tree2) = t2
          let sim = if strategy == "tsed" {
            @apted.calculate_tsed(tree1, tree2, tsed_config)
          } else {
            @apted.tree_similarity(tree1, tree2, cost_config)
          }
          total_sim = total_sim + sim
          count = count + 1
        }
      }
      if count > 0 {
        let avg_sim = total_sim / count.to_double()
        if avg_sim >= threshold {
          pairs.push((i, j, avg_sim))
        }
      }
    }
  }
  pairs
}

// collect_files: use @common (SoT)

///|
/// Categorized matches by target.
priv struct CategorizedMatches {
  by_target : Map[String, Array[FileMatch]] // target -> matches
  unmatched : Array[FileMatch] // no rule matched
}

///|
/// Categorize matches by rules.
fn categorize_matches(
  matches : Array[FileMatch],
  rules : Array[SolidRule],
  to_dir : String,
) -> CategorizedMatches {
  let by_target : Map[String, Array[FileMatch]] = {}
  let unmatched : Array[FileMatch] = []
  for m in matches {
    let mut matched = false
    for rule in rules {
      if @scope.path_matches_pattern(m.relative_path, rule.pattern) {
        // Resolve target path
        let target = resolve_target(rule.target, to_dir)
        let updated_match = { ..m, _matched_rule: Some(rule) }
        match by_target.get(target) {
          Some(arr) => arr.push(updated_match)
          None => by_target.set(target, [updated_match])
        }
        matched = true
        break
      }
    }
    if !matched {
      unmatched.push(m)
    }
  }
  { by_target, unmatched }
}

///|
/// Resolve target path (handle @ prefix for absolute).
fn resolve_target(target : String, to_dir : String) -> String {
  if target.has_prefix("@") {
    // Absolute path, remove @
    let chars = target.to_array()
    let result : Array[Char] = []
    for i = 1; i < chars.length(); i = i + 1 {
      result.push(chars[i])
    }
    String::from_array(result)
    // Relative to to_dir
  } else if to_dir.length() > 0 {
    @pipeline.trim_trailing_slash(to_dir) + "/" + target
  } else {
    target
  }
}

// render_plan removed - using PlanDocument IR and @plan_render (SoT)
