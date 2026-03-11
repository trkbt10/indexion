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
pub struct SolidConfig {
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
  show_help : Bool
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
    show_help: false,
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
/// Parse command line arguments.
pub fn parse_args(args : Array[String], start_idx : Int) -> SolidConfig {
  let mut config = SolidConfig::default()
  for i = start_idx; i < args.length(); i = i + 1 {
    let arg = args[i]
    if arg == "--help" || arg == "-h" {
      config = { ..config, show_help: true }
    } else if arg.has_prefix("--from=") {
      let value = @common.get_arg_value(arg, 7)
      let dirs = @common.parse_comma_list(value)
      for d in dirs {
        config.from_dirs.push(d)
      }
    } else if arg.has_prefix("--to=") {
      let value = @common.get_arg_value(arg, 5)
      config = { ..config, to_dir: value }
    } else if arg.has_prefix("--rules=") {
      let value = @common.get_arg_value(arg, 8)
      config = { ..config, rules_file: value }
    } else if arg.has_prefix("--rule=") {
      let value = @common.get_arg_value(arg, 7)
      config.inline_rules.push(value)
    } else if arg.has_prefix("--threshold=") {
      let value = @common.get_arg_value(arg, 12)
      config = { ..config, threshold: @common.parse_double(value) }
    } else if arg.has_prefix("--strategy=") {
      let value = @common.get_arg_value(arg, 11)
      config = { ..config, strategy: value }
    } else if arg.has_prefix("--include=") {
      let value = @common.get_arg_value(arg, 10)
      config.includes.push(value)
    } else if arg.has_prefix("--exclude=") {
      let value = @common.get_arg_value(arg, 10)
      config.excludes.push(value)
    } else if arg.has_prefix("--output=") || arg.has_prefix("-o=") {
      let prefix_len = if arg.has_prefix("--output=") { 9 } else { 3 }
      let value = @common.get_arg_value(arg, prefix_len)
      config = { ..config, output: value }
    } else if arg.has_prefix("--format=") {
      let value = @common.get_arg_value(arg, 9)
      config = { ..config, format: value }
    }
  }
  config
}

// get_arg_value and parse_double are in @common (SoT)

///|
pub fn show_help() -> Unit {
  println(
    "indexion plan solid - Generate solidification plan for common code extraction",
  )
  println("")
  println("Usage:")
  println("  indexion plan solid --from=pkg1/,pkg2/ --to=components/")
  println("  indexion plan solid --from=pkg1/,pkg2/ --rules=.solidrc")
  println("")
  println("Options:")
  println("  --from=DIRS          Source directories (comma-separated)")
  println("  --to=DIR             Target directory for extraction")
  println("  --rules=FILE         Rules file (.solidrc)")
  println("  --rule=RULE          Inline rule (can be repeated)")
  println("  --threshold=FLOAT    Similarity threshold (default: 0.9)")
  println(
    "  --strategy=NAME      Similarity strategy: tfidf, apted, tsed (default: tfidf)",
  )
  println("  --include=PATTERN    Include files matching pattern")
  println("  --exclude=PATTERN    Exclude files matching pattern")
  println("  --output=FILE, -o=   Output file path (default: stdout)")
  println(
    "  --format=FORMAT      Output format: md, json, github-issue (default: md)",
  )
  println("  --help               Show this help message")
  println("")
  println("Rule syntax:")
  println("  pattern -> target")
  println("  auth/** -> auth/        # relative (requires --to)")
  println("  auth/** -> @pkg/auth/   # absolute (@ prefix)")
  println("")
  println("Examples:")
  println(
    "  indexion plan solid --from=org-dashboard/src,store-dashboard/src --to=components/",
  )
  println(
    "  indexion plan solid --from=pkg1,pkg2 --rule=\"auth/** -> auth/\" --rule=\"layout/** -> layout/\"",
  )
}

///|
/// Run the solid command.
pub fn run(args : Array[String], start_idx : Int) -> Unit {
  let config = parse_args(args, start_idx)
  if config.show_help {
    show_help()
    return
  }
  if config.from_dirs.length() < 2 {
    println("Error: At least 2 source directories required (--from=dir1,dir2)")
    println("")
    show_help()
    return
  }
  // Parse rules
  let rules = load_rules(config)
  // Collect and compare files
  let matches = find_cross_matches(config)
  // Apply rules to matches
  let categorized = categorize_matches(matches, rules, config.to_dir)
  // Build intermediate representation
  let plan_json = build_plan_json(categorized, config, rules)
  // Convert to PlanDocument and render
  let output = match config.format {
    "github-issue" => {
      let doc = solid_to_plan_document(plan_json)
      let issue = @plan_render.render_github_issue(doc)
      format_github_issue(issue)
    }
    "json" => {
      let doc = solid_to_plan_document(plan_json)
      doc.to_json().stringify(indent=2)
    }
    _ => {
      let doc = solid_to_plan_document(plan_json)
      @plan_render.render_markdown(doc)
    }
  }
  // Output
  if config.output.length() > 0 {
    try {
      @fs.write_string_to_file(config.output, output)
      println("Plan written to: " + config.output)
    } catch {
      e => println("Error writing file: " + e.to_string())
    }
  } else {
    println(output)
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

///|
fn format_github_issue(issue : @plan_render.GitHubIssue) -> String {
  let buf = StringBuilder::new()
  buf.write_string("# ")
  buf.write_string(issue.title)
  buf.write_string("\n\n")
  if issue.labels.length() > 0 {
    buf.write_string("**Labels:** ")
    for i, label in issue.labels {
      if i > 0 {
        buf.write_string(", ")
      }
      buf.write_string("`")
      buf.write_string(label)
      buf.write_string("`")
    }
    buf.write_string("\n\n")
  }
  buf.write_string("---\n\n")
  buf.write_string(issue.body)
  buf.to_string()
}

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
  let lines = split_lines(content)
  for line in lines {
    let trimmed = trim_string(line)
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
  let pattern = trim_string(String::from_array(pattern_chars))
  let target = trim_string(String::from_array(target_chars))
  if pattern.length() == 0 || target.length() == 0 {
    return None
  }
  Some({ pattern, target })
}

///|
fn split_lines(s : String) -> Array[String] {
  let lines : Array[String] = []
  let chars = s.to_array()
  let current : Array[Char] = []
  for c in chars {
    if c == '\n' {
      lines.push(String::from_array(current))
      current.clear()
    } else if c != '\r' {
      current.push(c)
    }
  }
  if current.length() > 0 {
    lines.push(String::from_array(current))
  }
  lines
}

///|
fn trim_string(s : String) -> String {
  let chars = s.to_array()
  let mut start = 0
  let mut end = chars.length()
  while start < end && (chars[start] == ' ' || chars[start] == '\t') {
    start = start + 1
  }
  while end > start && (chars[end - 1] == ' ' || chars[end - 1] == '\t') {
    end = end - 1
  }
  let result : Array[Char] = []
  for i = start; i < end; i = i + 1 {
    result.push(chars[i])
  }
  String::from_array(result)
}

///|
/// Find cross-directory matches above threshold.
fn find_cross_matches(config : SolidConfig) -> Array[FileMatch] {
  let matches : Array[FileMatch] = []
  // Collect files from all source directories
  let files = collect_files(config.from_dirs, config.includes, config.excludes)
  if files.length() < 2 {
    return matches
  }
  // Check if using tree-based strategy
  let is_tree_strategy = config.strategy == "apted" || config.strategy == "tsed"
  let pairs : Array[(Int, Int, Double)] = if is_tree_strategy {
    calculate_tree_pairs(files, config.strategy, config.threshold)
  } else {
    // Tokenize with KGF
    let registry = @kgf_features.load_registry()
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
) -> Array[(Int, Int, Double)] {
  let pairs : Array[(Int, Int, Double)] = []
  let registry = match @kgf_features.load_registry() {
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
    match registry.detect_from_path(rel_path) {
      Some(lang) =>
        match registry.get_spec(lang) {
          Some(spec) => {
            let lexer = @kgf_lexer.Lexer::new(spec.get_tokens())
            let tokens = lexer.tokenize(content)
            let func_trees = @kgf_features.extract_function_trees(tokens, path)
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

///|
fn collect_files(
  dirs : Array[String],
  includes : Array[String],
  excludes : Array[String],
) -> Array[(String, String)] {
  let files : Array[(String, String)] = []
  // Get unique names for each directory (handles "src" vs "src" case)
  let dir_names = @common.extract_unique_dir_names(dirs)
  for i, dir in dirs {
    let opts = @pipeline.DiscoverOptions::new(
      includes~,
      excludes~,
      root_dir=dir,
    )
    let paths = @pipeline.discover_files([dir], opts)
    let dirname = dir_names[i]
    for path in paths {
      try {
        let content = @fs.read_file_to_string(path)
        let relative = @common.make_relative_path(path, dir)
        let display_name = dirname + ":" + relative
        files.push((display_name, content))
      } catch {
        _ => ()
      }
    }
  }
  files
}

// Path utilities: use @common (SoT)

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
    if not(matched) {
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
