///|
/// # indexion plan refactor
///
/// Generate refactoring plan based on file similarity analysis.
///
/// ## Overview
///
/// Analyzes files in a directory, identifies similar code patterns using
/// TF-IDF or NCD algorithms, and generates a Markdown checklist for
/// refactoring candidates.
///
/// ## Usage
///
/// ```bash
/// indexion plan refactor [options] <directory>
/// ```
///
/// ## Options
///
/// | Option | Description | Default |
/// |--------|-------------|---------|
/// | `--threshold=FLOAT` | Similarity threshold (0.0-1.0) | 0.7 |
/// | `--strategy=NAME` | Algorithm: `tfidf`, `ncd`, `hybrid` | tfidf |
/// | `--include=PATTERN` | Include files matching glob pattern | * |
/// | `--exclude=PATTERN` | Exclude files matching glob pattern | - |
/// | `--output=FILE`, `-o=` | Output file path | stdout |
///
/// ## Examples
///
/// ```bash
/// # Basic usage - analyze src/ with 70% threshold
/// indexion plan refactor src/
///
/// # Higher threshold, exclude tests
/// indexion plan refactor --threshold=0.85 --exclude='*_wbtest.mbt' src/
///
/// # Output to file
/// indexion plan refactor --include='*.mbt' -o=refactor-plan.md src/
/// ```
///
/// ## Output Format
///
/// Generates Markdown with:
/// - Configuration summary
/// - Grouped similar files (clustered by similarity)
/// - Similarity matrix per group
/// - Action item checklist

///|
/// CLI configuration.
pub struct RefactorPlanConfig {
  target_dir : String
  threshold : Double // similarity threshold (default: 0.7 = 70%)
  strategy : String // "hybrid", "ncd", "tfidf"
  includes : Array[String] // glob patterns to include
  excludes : Array[String] // glob patterns to exclude
  output : String // output file path (empty = stdout)
  format : String // output format: "md", "json", "text"
  style : String // output style: "raw" (similarity), "structured" (plan)
  project_name : String // project name for structured output
  show_help : Bool
}

///|
/// Create default configuration.
pub fn RefactorPlanConfig::default() -> RefactorPlanConfig {
  {
    target_dir: "",
    threshold: 0.7,
    strategy: "tfidf",
    includes: [],
    excludes: [],
    output: "",
    format: "md",
    style: "raw",
    project_name: "",
    show_help: false,
  }
}

///|
/// File pair with similarity.
priv struct SimilarPair {
  file1 : String
  file2 : String
  similarity : Double
}

///|
/// Cluster of related files.
struct FileCluster {
  files : Array[String]
  pairs : Array[SimilarPair] // pairs within this cluster
}

///|
fn get_arg_value(arg : String, prefix_len : Int) -> String {
  let chars = arg.to_array()
  if prefix_len >= chars.length() {
    return ""
  }
  let result : Array[Char] = []
  for i = prefix_len; i < chars.length(); i = i + 1 {
    result.push(chars[i])
  }
  String::from_array(result)
}

///|
fn parse_double(s : String) -> Double {
  let chars = s.to_array()
  if chars.length() == 0 {
    return 0.0
  }
  let mut result = 0.0
  let mut decimal_place = 0
  let mut i = 0
  while i < chars.length() {
    let c = chars[i]
    if c == '.' {
      decimal_place = 1
    } else if c >= '0' && c <= '9' {
      let digit = (c.to_int() - '0'.to_int()).to_double()
      if decimal_place > 0 {
        let mut divisor = 1.0
        for j = 0; j < decimal_place; j = j + 1 {
          divisor = divisor * 10.0
        }
        result = result + digit / divisor
        decimal_place = decimal_place + 1
      } else {
        result = result * 10.0 + digit
      }
    }
    i = i + 1
  }
  result
}

///|
pub fn parse_args(args : Array[String], start_idx : Int) -> RefactorPlanConfig {
  let mut config = RefactorPlanConfig::default()
  for i = start_idx; i < args.length(); i = i + 1 {
    let arg = args[i]
    if arg == "--help" || arg == "-h" {
      config = { ..config, show_help: true }
    } else if arg.has_prefix("--threshold=") {
      let value = get_arg_value(arg, 12)
      config = { ..config, threshold: parse_double(value) }
    } else if arg.has_prefix("--strategy=") {
      let value = get_arg_value(arg, 11)
      config = { ..config, strategy: value }
    } else if arg.has_prefix("--include=") {
      let value = get_arg_value(arg, 10)
      config.includes.push(value)
    } else if arg.has_prefix("--exclude=") {
      let value = get_arg_value(arg, 10)
      config.excludes.push(value)
    } else if arg.has_prefix("--output=") || arg.has_prefix("-o=") {
      let prefix_len = if arg.has_prefix("--output=") { 9 } else { 3 }
      let value = get_arg_value(arg, prefix_len)
      config = { ..config, output: value }
    } else if arg.has_prefix("--format=") {
      let value = get_arg_value(arg, 9)
      config = { ..config, format: value }
    } else if arg.has_prefix("--style=") {
      let value = get_arg_value(arg, 8)
      config = { ..config, style: value }
    } else if arg.has_prefix("--name=") {
      let value = get_arg_value(arg, 7)
      config = { ..config, project_name: value }
    } else if not(arg.has_prefix("-")) && config.target_dir.length() == 0 {
      config = { ..config, target_dir: arg }
    }
  }
  config
}

///|
pub fn show_help() -> Unit {
  println(
    "indexion plan refactor - Generate refactoring plan from similarity analysis",
  )
  println("")
  println("Usage:")
  println("  indexion plan refactor [options] <directory>")
  println("")
  println("Options:")
  println("  --threshold=FLOAT    Similarity threshold (default: 0.7 = 70%)")
  println(
    "  --strategy=NAME      Similarity strategy: hybrid, ncd, tfidf (default: tfidf)",
  )
  println(
    "  --include=PATTERN    Include files matching pattern (can be repeated)",
  )
  println(
    "  --exclude=PATTERN    Exclude files matching pattern (can be repeated)",
  )
  println("  --output=FILE, -o=   Output file path (default: stdout)")
  println("  --format=FORMAT      Output format: md, json, text (default: md)")
  println("  --style=STYLE        Output style: raw, structured (default: raw)")
  println("  --name=NAME          Project name for structured output")
  println("  --help               Show this help message")
  println("")
  println("Styles:")
  println("  raw          Raw similarity analysis with duplicate detection")
  println(
    "  structured   Comprehensive refactoring plan with phases/checklists",
  )
  println("")
  println("Examples:")
  println("  indexion plan refactor src/")
  println("  indexion plan refactor --threshold=0.8 --exclude=*_test.mbt src/")
  println("  indexion plan refactor --style=structured --name=myproject src/")
  println(
    "  indexion plan refactor --include=*.mbt --exclude=*_wbtest.mbt -o=refactor.md src/",
  )
  println("")
  println("Patterns:")
  println("  *           Match any characters")
  println("  *_test.mbt  Match files ending with _test.mbt")
  println("  test/*      Match files in test directory")
}

///|
/// Check if filename matches a glob pattern (simple implementation).
fn matches_pattern(filename : String, pattern : String) -> Bool {
  let fname_chars = filename.to_array()
  let pat_chars = pattern.to_array()
  matches_pattern_impl(fname_chars, 0, pat_chars, 0)
}

///|
fn matches_pattern_impl(
  fname : Array[Char],
  fi : Int,
  pat : Array[Char],
  pi : Int,
) -> Bool {
  // Both exhausted
  if fi >= fname.length() && pi >= pat.length() {
    return true
  }
  // Pattern exhausted but filename remains
  if pi >= pat.length() {
    return false
  }
  // Handle wildcard
  if pat[pi] == '*' {
    // Try matching zero or more characters
    // First, try skipping the wildcard (match zero chars)
    if matches_pattern_impl(fname, fi, pat, pi + 1) {
      return true
    }
    // Then try consuming one char from filename
    if fi < fname.length() {
      return matches_pattern_impl(fname, fi + 1, pat, pi)
    }
    return false
  }
  // Filename exhausted but pattern remains (non-wildcard)
  if fi >= fname.length() {
    return false
  }
  // Match single character
  if pat[pi] == fname[fi] {
    return matches_pattern_impl(fname, fi + 1, pat, pi + 1)
  }
  false
}

///|
/// Check if file should be included based on filter config.
fn should_include_file(
  filter : @filter.FilterConfig,
  filename : String,
) -> Bool {
  filter.should_include(filename, false).is_included()
}

///|
/// Collect files recursively with filtering.
fn collect_files(
  dir : String,
  includes : Array[String],
  excludes : Array[String],
) -> Array[(String, String)] {
  let filter = @filter.FilterConfig::new()
    .with_includes(includes)
    .with_excludes(excludes)
  let files : Array[(String, String)] = []
  collect_files_recursive(dir, filter, files, "")
  files
}

///|
fn collect_files_recursive(
  dir : String,
  filter : @filter.FilterConfig,
  files : Array[(String, String)],
  prefix : String,
) -> Unit {
  let clean_dir = if dir.has_suffix("/") {
    let chars = dir.to_array()
    let result : Array[Char] = []
    for i = 0; i < chars.length() - 1; i = i + 1 {
      result.push(chars[i])
    }
    String::from_array(result)
  } else {
    dir
  }
  try {
    if not(@fs.is_dir(clean_dir)) {
      return
    }
    let entries = @fs.read_dir(clean_dir)
    for entry in entries {
      // Skip excluded directories early
      if filter.should_skip_dir(entry) {
        continue
      }
      let path = clean_dir + "/" + entry
      let display_name = if prefix.length() > 0 {
        prefix + "/" + entry
      } else {
        entry
      }
      if @fs.is_dir(path) {
        collect_files_recursive(path, filter, files, display_name)
      } else if @fs.is_file(path) {
        if should_include_file(filter, display_name) {
          let content = @fs.read_file_to_string(path)
          files.push((display_name, content))
        }
      }
    }
  } catch {
    _ => ()
  }
}

///|
/// Calculate similarity between two texts.
fn calc_similarity(text1 : String, text2 : String, strategy : String) -> Double {
  match strategy {
    "ncd" => {
      let s = @sim.NCDStrategy::new()
      s.similarity(text1, text2)
    }
    "tfidf" => {
      let s = @sim.TfidfStrategy::new()
      s.similarity(text1, text2)
    }
    _ => {
      let s = @sim.HybridStrategy::new()
      s.similarity(text1, text2)
    }
  }
}

///|
/// Find connected components (clusters) using Union-Find.
fn find_clusters(
  files : Array[(String, String)],
  pairs : Array[SimilarPair],
  threshold : Double,
) -> Array[FileCluster] {
  let n = files.length()
  if n == 0 {
    return []
  }
  // Create file index map
  let file_index : Map[String, Int] = {}
  for i, f in files {
    file_index.set(f.0, i)
  }
  // Union-Find parent array
  let parent : Array[Int] = []
  for i = 0; i < n; i = i + 1 {
    parent.push(i)
  }
  // Find with path compression
  fn find(x : Int) -> Int {
    if parent[x] != x {
      parent[x] = find(parent[x])
    }
    parent[x]
  }
  // Union
  fn union(x : Int, y : Int) -> Unit {
    let px = find(x)
    let py = find(y)
    if px != py {
      parent[px] = py
    }
  }
  // Union files that are similar
  for pair in pairs {
    if pair.similarity >= threshold {
      match (file_index.get(pair.file1), file_index.get(pair.file2)) {
        (Some(i), Some(j)) => union(i, j)
        _ => ()
      }
    }
  }
  // Group files by their root
  let groups : Map[Int, Array[String]] = {}
  for i, f in files {
    let root = find(i)
    match groups.get(root) {
      Some(arr) => arr.push(f.0)
      None => groups.set(root, [f.0])
    }
  }
  // Build clusters with their pairs
  let clusters : Array[FileCluster] = []
  for _, group in groups {
    if group.length() > 1 {
      // Find all pairs within this cluster
      let cluster_pairs : Array[SimilarPair] = []
      for pair in pairs {
        if pair.similarity >= threshold {
          let mut in_cluster = false
          for file in group {
            if pair.file1 == file || pair.file2 == file {
              in_cluster = true
              break
            }
          }
          if in_cluster {
            // Check both files are in cluster
            let mut both = false
            let mut found1 = false
            let mut found2 = false
            for file in group {
              if pair.file1 == file {
                found1 = true
              }
              if pair.file2 == file {
                found2 = true
              }
            }
            both = found1 && found2
            if both {
              cluster_pairs.push(pair)
            }
          }
        }
      }
      // Sort pairs by similarity (descending)
      for i = 0; i < cluster_pairs.length(); i = i + 1 {
        for j = i + 1; j < cluster_pairs.length(); j = j + 1 {
          if cluster_pairs[j].similarity > cluster_pairs[i].similarity {
            let tmp = cluster_pairs[i]
            cluster_pairs[i] = cluster_pairs[j]
            cluster_pairs[j] = tmp
          }
        }
      }
      clusters.push({ files: group, pairs: cluster_pairs })
    }
  }
  // Sort clusters by max similarity (descending)
  for i = 0; i < clusters.length(); i = i + 1 {
    for j = i + 1; j < clusters.length(); j = j + 1 {
      let max_i = if clusters[i].pairs.length() > 0 {
        clusters[i].pairs[0].similarity
      } else {
        0.0
      }
      let max_j = if clusters[j].pairs.length() > 0 {
        clusters[j].pairs[0].similarity
      } else {
        0.0
      }
      if max_j > max_i {
        let tmp = clusters[i]
        clusters[i] = clusters[j]
        clusters[j] = tmp
      }
    }
  }
  clusters
}

///|
/// Trim leading/trailing whitespace.
fn trim_line(line : String) -> String {
  let chars = line.to_array()
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
/// Check if line is a function definition (MoonBit style).
fn is_function_def(line : String) -> Bool {
  let trimmed = trim_line(line)
  trimmed.has_prefix("pub fn ") ||
  trimmed.has_prefix("fn ") ||
  trimmed.has_prefix("pub impl ") ||
  trimmed.has_prefix("impl ")
}

///|
/// Extract function name from definition line.
fn extract_func_name(line : String) -> String {
  let trimmed = trim_line(line)
  let chars = trimmed.to_array()
  // Find start of function name (after "fn " or after "pub fn ")
  let mut start = 0
  if trimmed.has_prefix("pub fn ") {
    start = 7
  } else if trimmed.has_prefix("fn ") {
    start = 3
  } else if trimmed.has_prefix("pub impl ") {
    start = 9
  } else if trimmed.has_prefix("impl ") {
    start = 5
  }
  // Find end (space, ( or {)
  let mut end = start
  while end < chars.length() &&
        chars[end] != ' ' &&
        chars[end] != '(' &&
        chars[end] != '{' {
    end = end + 1
  }
  let result : Array[Char] = []
  for i = start; i < end; i = i + 1 {
    result.push(chars[i])
  }
  String::from_array(result)
}

///|
/// Duplicate code block found between two files.
priv struct DuplicateBlock {
  start_line1 : Int
  start_line2 : Int
  line_count : Int
  func_name : String? // function name if it's a function
  preview : String // first few lines as preview
}

///|
/// Find duplicate code blocks between two files.
fn find_duplicate_blocks(
  content1 : String,
  content2 : String,
  min_lines : Int,
) -> Array[DuplicateBlock] {
  let lines1 = split_lines(content1)
  let lines2 = split_lines(content2)
  let duplicates : Array[DuplicateBlock] = []
  // Skip empty or very short files
  if lines1.length() < min_lines || lines2.length() < min_lines {
    return duplicates
  }
  // Build line hash map for file2
  let line_map : Map[String, Array[Int]] = {}
  for i, line in lines2 {
    let trimmed = trim_line(line)
    if trimmed.length() > 5 {
      // Skip very short lines
      match line_map.get(trimmed) {
        Some(arr) => arr.push(i)
        None => line_map.set(trimmed, [i])
      }
    }
  }
  // Find matching blocks
  let mut i = 0
  while i < lines1.length() {
    let trimmed = trim_line(lines1[i])
    if trimmed.length() > 5 {
      match line_map.get(trimmed) {
        Some(positions) =>
          for j in positions {
            // Count matching lines
            let mut count = 0
            while i + count < lines1.length() &&
                  j + count < lines2.length() &&
                  trim_line(lines1[i + count]) == trim_line(lines2[j + count]) {
              count = count + 1
            }
            if count >= min_lines {
              // Check if this block starts with a function def
              let func_name = if is_function_def(lines1[i]) {
                Some(extract_func_name(lines1[i]))
              } else {
                None
              }
              // Build preview (first 3 lines)
              let preview_lines : Array[String] = []
              let preview_count = if count < 3 { count } else { 3 }
              for k = 0; k < preview_count; k = k + 1 {
                preview_lines.push(lines1[i + k])
              }
              let preview = preview_lines
                .iter()
                .fold(init="", fn(acc, line) {
                  if acc.length() == 0 {
                    line
                  } else {
                    acc + "\n" + line
                  }
                })
              duplicates.push({
                start_line1: i + 1,
                start_line2: j + 1,
                line_count: count,
                func_name,
                preview,
              })
              // Skip past this block
              i = i + count - 1
              break
            }
          }
        None => ()
      }
    }
    i = i + 1
  }
  // Sort by line count (descending)
  for a = 0; a < duplicates.length(); a = a + 1 {
    for b = a + 1; b < duplicates.length(); b = b + 1 {
      if duplicates[b].line_count > duplicates[a].line_count {
        let tmp = duplicates[a]
        duplicates[a] = duplicates[b]
        duplicates[b] = tmp
      }
    }
  }
  duplicates
}

///|
/// Suggest target module for shared code.
fn suggest_shared_module(file1 : String, file2 : String) -> String {
  // Find common path prefix
  let parts1 = split_by_slash(file1)
  let parts2 = split_by_slash(file2)
  let common : Array[String] = []
  let min_len = if parts1.length() < parts2.length() {
    parts1.length()
  } else {
    parts2.length()
  }
  for i = 0; i < min_len - 1; i = i + 1 {
    if parts1[i] == parts2[i] {
      common.push(parts1[i])
    } else {
      break
    }
  }
  if common.length() > 0 {
    common
    .iter()
    .fold(init="", fn(acc, part) {
      if acc.length() == 0 {
        part
      } else {
        acc + "/" + part
      }
    }) +
    "/utils/"
  } else {
    "shared/utils/"
  }
}

///|
fn split_by_slash(path : String) -> Array[String] {
  let parts : Array[String] = []
  let chars = path.to_array()
  let current : Array[Char] = []
  for c in chars {
    if c == '/' || c == '\\' {
      if current.length() > 0 {
        parts.push(String::from_array(current))
        current.clear()
      }
    } else {
      current.push(c)
    }
  }
  if current.length() > 0 {
    parts.push(String::from_array(current))
  }
  parts
}

///|
/// Extract project name from directory path.
fn extract_project_name(path : String) -> String {
  let parts = split_by_slash(path)
  // Find first meaningful part (skip "src", ".", etc.)
  for i = parts.length() - 1; i >= 0; i = i - 1 {
    let part = parts[i]
    if part != "src" && part != "." && part != ".." && part.length() > 0 {
      return part
    }
  }
  "project"
}

///|
pub fn run(args : Array[String], start_idx : Int) -> Unit {
  let config = parse_args(args, start_idx)
  if config.show_help {
    show_help()
    return
  }
  if config.target_dir.length() == 0 {
    println("Error: Directory path required.")
    println("")
    show_help()
    return
  }
  // Collect files
  let files = collect_files(config.target_dir, config.includes, config.excludes)
  if files.length() < 2 {
    println("Error: Need at least 2 files to analyze.")
    return
  }
  // Calculate all pairs using optimized batch processing for TF-IDF
  let pairs : Array[SimilarPair] = []
  if config.strategy == "tfidf" {
    // Optimized path: batch TF-IDF with precomputed vectors
    let contents : Array[String] = []
    for f in files {
      contents.push(f.1)
    }
    let batch = @sim.TfidfBatch::from_texts(contents)
    let results = batch.all_pairs_above_threshold(config.threshold)
    for result in results {
      let (i, j, sim) = result
      pairs.push({ file1: files[i].0, file2: files[j].0, similarity: sim })
    }
  } else {
    // Fallback for NCD/Hybrid strategies
    for i = 0; i < files.length(); i = i + 1 {
      for j = i + 1; j < files.length(); j = j + 1 {
        let sim = calc_similarity(files[i].1, files[j].1, config.strategy)
        if sim >= config.threshold {
          pairs.push({ file1: files[i].0, file2: files[j].0, similarity: sim })
        }
      }
    }
  }
  // Find clusters
  let clusters = find_clusters(files, pairs, config.threshold)
  // Build file contents map for concrete suggestions
  let file_contents : Map[String, String] = {}
  for f in files {
    file_contents.set(f.0, f.1)
  }
  // Build intermediate plan
  let plan = build_refactor_plan(clusters, config, file_contents)
  // Render to selected format/style
  let output_content = match config.style {
    "structured" => {
      let name = if config.project_name.length() > 0 {
        config.project_name
      } else {
        extract_project_name(config.target_dir)
      }
      render_structured(plan, name)
    }
    _ =>
      match config.format {
        "json" => render_json(plan)
        "text" => render_text(plan)
        _ => render_markdown(plan)
      }
  }
  // Output
  if config.output.length() > 0 {
    try {
      @fs.write_string_to_file(config.output, output_content)
      println("Refactoring plan written to: " + config.output)
    } catch {
      e => println("Error writing file: " + e.to_string())
    }
  } else {
    println(output_content)
  }
}
