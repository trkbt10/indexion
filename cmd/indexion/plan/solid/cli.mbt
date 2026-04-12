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
  source1 : String // file from first source (dirname:path)
  source2 : String // file from second source (dirname:path)
  similarity : Double
  relative_path : String // common relative path (or best-fit path for content matches)
  matched_rule : SolidRule? // rule that matched, if any
  match_kind : MatchKind // how the match was found
}

///|
/// How a file match was discovered.
priv enum MatchKind {
  /// Identical relative paths across directories (original behavior)
  PathMatch
  /// Content similarity above threshold (new: different file names)
  ContentMatch
}

///|
/// A cross-directory function duplicate found by content analysis.
pub struct CrossFunctionMatch {
  func_name1 : String
  func_name2 : String
  file1 : String // display_name (dirname:path)
  file2 : String
  dir1 : String // dirname prefix
  dir2 : String
  similarity : Double
  body_preview : String // first few lines of the function body
  line_count : Int // approximate line count of the function
}

///|
/// Extraction task for an agent to execute.
/// Contains enough context for automated extraction.
pub struct ExtractionTask {
  task_id : Int
  target_path : String // where to put the extracted code
  functions : Array[ExtractableFunction] // functions to extract
  source_files : Array[String] // files affected
  merge_strategy : String // "copy" (identical) or "reconcile" (similar)
  confidence : Double // overall confidence (min similarity)
}

///|
/// A function that should be extracted to a shared location.
pub struct ExtractableFunction {
  name : String // function name
  source_locations : Array[FunctionLocation] // where it currently lives
  similarity : Double // similarity across locations
  preview : String // code preview
  line_count : Int
}

///|
/// Location of a function in a source file.
pub struct FunctionLocation {
  file : String // display_name
  dir : String // directory prefix
  start_line : Int
  end_line : Int
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
  let sources = collect_sources(config)
  // Phase 1: File-level cross-directory matches (path + content)
  let matches = find_cross_matches(config, sources)
  let categorized = categorize_matches(matches, rules, config.to_dir)
  // Phase 2: Function-level cross-directory duplicates
  let func_matches = find_cross_function_matches(config, sources)
  let extraction_tasks = build_extraction_tasks(func_matches, rules, config.to_dir)
  let plan_json = build_plan_json(
    categorized, config, rules, func_matches, extraction_tasks,
  )
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
  func_matches : Array[CrossFunctionMatch],
  extraction_tasks : Array[ExtractionTask],
) -> SolidPlanJSON {
  // Extract unique source names (use parent dir if all are "src")
  let source_names = @common.extract_unique_dir_names(config.from_dirs)
  // Build extraction groups from file-level matches
  let extractions : Array[ExtractionGroup] = []
  for target, matches in categorized.by_target {
    let files : Array[ExtractionFile] = []
    for m in matches {
      let action = match m.match_kind {
        PathMatch =>
          if m.similarity >= 0.99 {
            "Extract"
          } else {
            "Extract (review diff)"
          }
        ContentMatch =>
          if m.similarity >= 0.99 {
            "Extract (content match)"
          } else {
            "Extract (content match, review diff)"
          }
      }
      // For content matches, show both source paths
      let display_path = match m.match_kind {
        PathMatch => m.relative_path
        ContentMatch => {
          let rel1 = @common.get_relative_part(m.source1)
          let rel2 = @common.get_relative_part(m.source2)
          if rel1 == rel2 {
            rel1
          } else {
            rel1 + " ≈ " + rel2
          }
        }
      }
      files.push({
        relative_path: display_path,
        similarity: m.similarity,
        action,
        source1: m.source1,
        source2: m.source2,
      })
    }
    extractions.push({ target_path: target, files })
  }
  // Build unmatched list
  let unmatched : Array[UnmatchedFile] = []
  for m in categorized.unmatched {
    let display_path = match m.match_kind {
      PathMatch => m.relative_path
      ContentMatch => {
        let rel1 = @common.get_relative_part(m.source1)
        let rel2 = @common.get_relative_part(m.source2)
        if rel1 == rel2 {
          rel1
        } else {
          rel1 + " ≈ " + rel2
        }
      }
    }
    unmatched.push({
      relative_path: display_path,
      similarity: m.similarity,
      source1: m.source1,
      source2: m.source2,
    })
  }
  // Count matched
  let mut matched_count = 0
  for _, matches in categorized.by_target {
    matched_count = matched_count + matches.length()
  }
  // Count content matches
  let mut content_match_count = 0
  let mut path_match_count = 0
  for _, matches in categorized.by_target {
    for m in matches {
      match m.match_kind {
        PathMatch => path_match_count += 1
        ContentMatch => content_match_count += 1
      }
    }
  }
  for m in categorized.unmatched {
    match m.match_kind {
      PathMatch => path_match_count += 1
      ContentMatch => content_match_count += 1
    }
  }
  {
    config: {
      sources: source_names,
      target: config.to_dir,
      threshold: config.threshold,
      rules_count: rules.length(),
      from_dirs: config.from_dirs,
    },
    summary: {
      total_matches: matched_count + unmatched.length(),
      matched_by_rules: matched_count,
      unmatched_count: unmatched.length(),
      path_match_count,
      content_match_count,
      function_match_count: func_matches.length(),
      extraction_task_count: extraction_tasks.length(),
    },
    extractions,
    unmatched,
    function_matches: func_matches,
    extraction_tasks,
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
/// Collected files with registry for reuse across analysis phases.
priv struct CollectedSources {
  files : Array[(String, String)] // (display_name, content)
  registry : @registry.KGFRegistry?
}

///|
/// Collect source files from all directories.
fn collect_sources(config : SolidConfig) -> CollectedSources {
  let registry = @kgf_features.load_registry(
    specs_dir=config.specs_dir,
    target_dirs=config.from_dirs,
  )
  let files = @common.collect_files(
    config.from_dirs,
    includes=config.includes,
    excludes=config.excludes,
    registry~,
  )
  { files, registry }
}

///|
/// Find cross-directory matches above threshold using content-based comparison.
/// Phase 1: path-based matches (identical relative paths — high confidence).
/// Phase 2: content-based matches (different names but similar content).
fn find_cross_matches(
  config : SolidConfig,
  sources : CollectedSources,
) -> Array[FileMatch] {
  let matches : Array[FileMatch] = []
  let files = sources.files
  if files.length() < 2 {
    return matches
  }
  // Use @batch for content-based comparison (SoT for all similarity)
  let entries : Array[@batch.FileEntry] = []
  for f in files {
    entries.push(@batch.FileEntry::new(f.0, f.1))
  }
  let result = @batch.compare(
    entries,
    @batch.BatchConfig::create(config.threshold, config.strategy),
  )
  // Track which pairs are path-matches vs content-matches
  let seen_paths : Map[String, Bool] = {}
  // Phase 1: path-based cross-directory matches (highest confidence)
  for m in result.matches {
    let file1 = m.file1
    let file2 = m.file2
    let dir1 = @common.get_dirname_prefix(file1)
    let dir2 = @common.get_dirname_prefix(file2)
    if dir1.length() > 0 && dir2.length() > 0 && dir1 != dir2 {
      let rel1 = @common.get_relative_part(file1)
      let rel2 = @common.get_relative_part(file2)
      if rel1 == rel2 {
        matches.push({
          source1: file1,
          source2: file2,
          similarity: m.similarity,
          relative_path: rel1,
          matched_rule: None,
          match_kind: PathMatch,
        })
        // Mark this pair so we don't duplicate it in phase 2
        let key = file1 + "\t" + file2
        seen_paths.set(key, true)
      }
    }
  }
  // Phase 2: content-based cross-directory matches (different file names)
  for m in result.matches {
    let file1 = m.file1
    let file2 = m.file2
    let key = file1 + "\t" + file2
    if seen_paths.contains(key) {
      continue
    }
    let dir1 = @common.get_dirname_prefix(file1)
    let dir2 = @common.get_dirname_prefix(file2)
    if dir1.length() > 0 && dir2.length() > 0 && dir1 != dir2 {
      let rel1 = @common.get_relative_part(file1)
      let rel2 = @common.get_relative_part(file2)
      // Use the shorter relative path as representative, or combine
      let representative = if rel1.length() <= rel2.length() {
        rel1
      } else {
        rel2
      }
      matches.push({
        source1: file1,
        source2: file2,
        similarity: m.similarity,
        relative_path: representative,
        matched_rule: None,
        match_kind: ContentMatch,
      })
    }
  }
  // Sort by similarity descending
  matches.sort_by(fn(a, b) { b.similarity.compare(a.similarity) })
  matches
}

///|
/// Find cross-directory function-level duplicates.
/// Extracts functions from all files via KGF grammar pipeline
/// (tokenize→parse→eval_semantics→declares edges), compares function bodies
/// via TF-IDF, and returns only cross-directory pairs.
fn find_cross_function_matches(
  config : SolidConfig,
  sources : CollectedSources,
) -> Array[CrossFunctionMatch] {
  let files = sources.files
  let registry = sources.registry
  match registry {
    Some(_) => ()
    None => return []
  }
  // Extract functions from all files with source info
  let func_names : Array[String] = []
  let func_bodies : Array[String] = []
  let func_files : Array[String] = []
  let func_lines : Array[(Int, Int)] = [] // (start_line, end_line)
  for file in files {
    let (path, content) = file
    let rel_path = @common.get_relative_part(path)
    let lines = @common.split_lines(content)
    // Grammar-based function extraction via KGF full pipeline.
    // PubDeclaration with Shortest span preference gives accurate
    // function boundaries for all languages.
    let (declarations, _) = @kgf_declarations.extract_pub_declarations_and_doc_map(
      content, rel_path, registry,
    )
    for decl in declarations {
      if decl.category != "function" {
        continue
      }
      add_function_body(
        lines, decl.line, decl.end_line, decl.name, path,
        func_names, func_bodies, func_files, func_lines,
      )
    }
  }
  if func_bodies.length() < 2 {
    return []
  }
  // Tokenize function bodies with KGF and compare via TF-IDF
  let func_pairs : Array[(String, String)] = []
  for i in 0..<func_bodies.length() {
    func_pairs.push((func_files[i], func_bodies[i]))
  }
  let (tokenized, _) = @kgf_features.tokenize_files_with_kgf(
    func_pairs, registry,
  )
  let batch = @tfidf.TfidfBatch::from_tokens(tokenized)
  let pairs = batch.all_pairs_above_threshold(config.threshold)
  // Filter to cross-directory function pairs
  let results : Array[CrossFunctionMatch] = []
  for pair in pairs {
    let (i, j, sim) = pair
    let file_i = func_files[i]
    let file_j = func_files[j]
    let dir_i = @common.get_dirname_prefix(file_i)
    let dir_j = @common.get_dirname_prefix(file_j)
    // Only cross-directory pairs
    if dir_i.length() == 0 || dir_j.length() == 0 || dir_i == dir_j {
      continue
    }
    // Build preview from first function body (first 5 lines)
    let body_lines = @common.split_lines(func_bodies[i])
    let preview_count = if body_lines.length() < 5 {
      body_lines.length()
    } else {
      5
    }
    let preview = body_lines
      .iter()
      .take(preview_count)
      .fold(init="", fn(acc, l) {
        if acc.length() == 0 {
          l
        } else {
          acc + "\n" + l
        }
      })
    results.push({
      func_name1: func_names[i],
      func_name2: func_names[j],
      file1: file_i,
      file2: file_j,
      dir1: dir_i,
      dir2: dir_j,
      similarity: sim,
      body_preview: preview,
      line_count: body_lines.length(),
    })
  }
  results.sort_by(fn(a, b) { b.similarity.compare(a.similarity) })
  results
}

// find_name_in_tokens, find_brace_end_from_line: removed.
// Grammar-based extraction via @kgf_declarations provides accurate line/end_line
// directly from PubDeclaration with Shortest span preference.

///|
/// Add a function body to the extraction arrays.
/// Shared by both token-based and grammar-based extraction paths.
fn add_function_body(
  lines : Array[String],
  start_line : Int,
  end_line : Int,
  name : String,
  path : String,
  func_names : Array[String],
  func_bodies : Array[String],
  func_files : Array[String],
  func_lines : Array[(Int, Int)],
) -> Unit {
  let body_lines : Array[String] = []
  for li = start_line - 1; li < end_line && li < lines.length(); li = li + 1 {
    body_lines.push(lines[li])
  }
  // Skip trivially small functions
  if body_lines.length() < 3 {
    return
  }
  let body = body_lines
    .iter()
    .fold(init="", fn(acc, l) {
      if acc.length() == 0 {
        l
      } else {
        acc + "\n" + l
      }
    })
  func_names.push(name)
  func_bodies.push(body)
  func_files.push(path)
  func_lines.push((start_line, end_line))
}

// calculate_tree_pairs: replaced by @batch.compare (SoT) which handles all strategies
// including apted and tsed via BatchConfig

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
        let updated_match = { ..m, matched_rule: Some(rule) }
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
/// Group cross-function matches by shared function name/signature.
/// Returns extraction tasks grouped by target, with functions to extract.
fn build_extraction_tasks(
  func_matches : Array[CrossFunctionMatch],
  rules : Array[SolidRule],
  to_dir : String,
) -> Array[ExtractionTask] {
  // Group by function name clusters: functions that are similar across dirs
  // Key: canonical function name → all matches involving that function
  let func_groups : Map[String, Array[CrossFunctionMatch]] = {}
  for m in func_matches {
    // Use the common name if names match, otherwise create a composite key
    let key = if m.func_name1 == m.func_name2 {
      m.func_name1
    } else {
      // For different names, group by the pair
      let k1 = if m.func_name1.compare(m.func_name2) <= 0 {
        m.func_name1
      } else {
        m.func_name2
      }
      let k2 = if m.func_name1.compare(m.func_name2) <= 0 {
        m.func_name2
      } else {
        m.func_name1
      }
      k1 + "~" + k2
    }
    match func_groups.get(key) {
      Some(arr) => arr.push(m)
      None => func_groups.set(key, [m])
    }
  }
  // Build extraction tasks from grouped functions
  let tasks : Array[ExtractionTask] = []
  let mut task_id = 1
  for entry in func_groups {
    let group_matches = entry.1
    if group_matches.length() == 0 {
      continue
    }
    // Determine target path from rules or default
    let representative = group_matches[0]
    let rel1 = @common.get_relative_part(representative.file1)
    let target_path = resolve_extraction_target(rel1, rules, to_dir)
    // Collect all unique source files
    let source_files_set : Map[String, Bool] = {}
    for m in group_matches {
      source_files_set.set(m.file1, true)
      source_files_set.set(m.file2, true)
    }
    let source_files : Array[String] = []
    for entry2 in source_files_set {
      source_files.push(entry2.0)
    }
    // Build extractable functions
    let functions : Array[ExtractableFunction] = []
    let seen_funcs : Map[String, Bool] = {}
    let mut min_similarity = 1.0
    for m in group_matches {
      // Avoid duplicating the same function
      let func_key = m.func_name1 + "@" + m.file1
      if seen_funcs.contains(func_key) {
        continue
      }
      seen_funcs.set(func_key, true)
      if m.similarity < min_similarity {
        min_similarity = m.similarity
      }
      let locations : Array[FunctionLocation] = [
        {
          file: m.file1,
          dir: m.dir1,
          start_line: 0, // populated later if needed
          end_line: 0,
        },
        {
          file: m.file2,
          dir: m.dir2,
          start_line: 0,
          end_line: 0,
        },
      ]
      functions.push({
        name: m.func_name1,
        source_locations: locations,
        similarity: m.similarity,
        preview: m.body_preview,
        line_count: m.line_count,
      })
    }
    let merge_strategy = if min_similarity >= 0.99 { "copy" } else { "reconcile" }
    tasks.push({
      task_id,
      target_path,
      functions,
      source_files,
      merge_strategy,
      confidence: min_similarity,
    })
    task_id += 1
  }
  // Sort by confidence descending (highest first = easiest to extract)
  tasks.sort_by(fn(a, b) { b.confidence.compare(a.confidence) })
  tasks
}

///|
/// Resolve extraction target for a function using rules or default.
fn resolve_extraction_target(
  relative_path : String,
  rules : Array[SolidRule],
  to_dir : String,
) -> String {
  // Try rules first
  for rule in rules {
    if @scope.path_matches_pattern(relative_path, rule.pattern) {
      return resolve_target(rule.target, to_dir)
    }
  }
  // Default: use to_dir if specified, otherwise infer from path
  if to_dir.length() > 0 {
    @pipeline.trim_trailing_slash(to_dir) + "/"
  } else {
    "shared/"
  }
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
