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
    show_help: false,
  }
}

///|
/// File pair with similarity.
struct SimilarPair {
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
    } else if not(arg.has_prefix("-")) && config.target_dir.length() == 0 {
      config = { ..config, target_dir: arg }
    }
  }
  config
}

///|
pub fn show_help() -> Unit {
  println("indexion plan refactor - Generate refactoring plan from similarity analysis")
  println("")
  println("Usage:")
  println("  indexion plan refactor [options] <directory>")
  println("")
  println("Options:")
  println("  --threshold=FLOAT    Similarity threshold (default: 0.7 = 70%)")
  println("  --strategy=NAME      Similarity strategy: hybrid, ncd, tfidf (default: tfidf)")
  println("  --include=PATTERN    Include files matching pattern (can be repeated)")
  println("  --exclude=PATTERN    Exclude files matching pattern (can be repeated)")
  println("  --output=FILE, -o=   Output file path (default: stdout)")
  println("  --help               Show this help message")
  println("")
  println("Examples:")
  println("  indexion plan refactor src/")
  println("  indexion plan refactor --threshold=0.8 --exclude=*_test.mbt src/")
  println("  indexion plan refactor --include=*.mbt --exclude=*_wbtest.mbt -o=refactor.md src/")
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
  pi : Int
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
/// Check if file should be included based on include/exclude patterns.
fn should_include_file(
  filename : String,
  includes : Array[String],
  excludes : Array[String]
) -> Bool {
  // Check excludes first
  for pattern in excludes {
    if matches_pattern(filename, pattern) {
      return false
    }
  }
  // If no includes specified, include all (that weren't excluded)
  if includes.length() == 0 {
    return true
  }
  // Check includes
  for pattern in includes {
    if matches_pattern(filename, pattern) {
      return true
    }
  }
  false
}

///|
/// Collect files recursively with filtering.
fn collect_files(
  dir : String,
  includes : Array[String],
  excludes : Array[String]
) -> Array[(String, String)] {
  let files : Array[(String, String)] = []
  collect_files_recursive(dir, includes, excludes, files, "")
  files
}

///|
fn collect_files_recursive(
  dir : String,
  includes : Array[String],
  excludes : Array[String],
  files : Array[(String, String)],
  prefix : String
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
      let path = clean_dir + "/" + entry
      let display_name = if prefix.length() > 0 {
        prefix + "/" + entry
      } else {
        entry
      }
      if @fs.is_dir(path) {
        collect_files_recursive(path, includes, excludes, files, display_name)
      } else if @fs.is_file(path) {
        if should_include_file(display_name, includes, excludes) {
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
  threshold : Double
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
/// Format percentage.
fn format_percent(d : Double) -> String {
  let percent = (d * 100.0).to_int()
  percent.to_string() + "%"
}

///|
/// Generate markdown output.
fn generate_markdown(
  clusters : Array[FileCluster],
  config : RefactorPlanConfig
) -> String {
  let buf = StringBuilder::new()
  buf.write_string("# Refactoring Plan\n\n")
  buf.write_string("Generated by `indexion plan refactor`\n\n")
  buf.write_string("## Configuration\n\n")
  buf.write_string("- **Directory**: `" + config.target_dir + "`\n")
  buf.write_string("- **Threshold**: " + format_percent(config.threshold) + "\n")
  buf.write_string("- **Strategy**: " + config.strategy + "\n")
  if config.includes.length() > 0 {
    buf.write_string("- **Includes**: ")
    for i, inc in config.includes {
      if i > 0 {
        buf.write_string(", ")
      }
      buf.write_string("`" + inc + "`")
    }
    buf.write_string("\n")
  }
  if config.excludes.length() > 0 {
    buf.write_string("- **Excludes**: ")
    for i, exc in config.excludes {
      if i > 0 {
        buf.write_string(", ")
      }
      buf.write_string("`" + exc + "`")
    }
    buf.write_string("\n")
  }
  buf.write_string("\n")
  if clusters.length() == 0 {
    buf.write_string("## Result\n\n")
    buf.write_string("No similar file groups found above threshold.\n")
    return buf.to_string()
  }
  buf.write_string("## Summary\n\n")
  buf.write_string("Found **" + clusters.length().to_string() + "** groups of similar files.\n\n")
  buf.write_string("---\n\n")
  buf.write_string("## Refactoring Checklist\n\n")
  for i, cluster in clusters {
    let group_num = i + 1
    let max_sim = if cluster.pairs.length() > 0 {
      format_percent(cluster.pairs[0].similarity)
    } else {
      "N/A"
    }
    buf.write_string("### Group " + group_num.to_string() + " (max: " + max_sim + ")\n\n")
    buf.write_string("**Files:**\n")
    for file in cluster.files {
      buf.write_string("- `" + file + "`\n")
    }
    buf.write_string("\n")
    buf.write_string("**Similarity Matrix:**\n")
    buf.write_string("| File 1 | File 2 | Similarity |\n")
    buf.write_string("|--------|--------|------------|\n")
    for pair in cluster.pairs {
      buf.write_string("| `" + pair.file1 + "` | `" + pair.file2 + "` | " + format_percent(
          pair.similarity,
        ) + " |\n")
    }
    buf.write_string("\n")
    buf.write_string("**Action Items:**\n")
    buf.write_string("- [ ] Review files for duplicated code\n")
    buf.write_string("- [ ] Identify common patterns to extract\n")
    buf.write_string("- [ ] Create shared utility module if needed\n")
    buf.write_string("- [ ] Update references to use shared code\n")
    buf.write_string("- [ ] Verify tests pass after refactoring\n")
    buf.write_string("\n")
    if i < clusters.length() - 1 {
      buf.write_string("---\n\n")
    }
  }
  buf.to_string()
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
  // Calculate all pairs
  let pairs : Array[SimilarPair] = []
  for i = 0; i < files.length(); i = i + 1 {
    for j = i + 1; j < files.length(); j = j + 1 {
      let sim = calc_similarity(files[i].1, files[j].1, config.strategy)
      if sim >= config.threshold {
        pairs.push({ file1: files[i].0, file2: files[j].0, similarity: sim })
      }
    }
  }
  // Find clusters
  let clusters = find_clusters(files, pairs, config.threshold)
  // Generate markdown
  let markdown = generate_markdown(clusters, config)
  // Output
  if config.output.length() > 0 {
    try {
      @fs.write_string_to_file(config.output, markdown)
      println("Refactoring plan written to: " + config.output)
    } catch {
      e => println("Error writing file: " + e.to_string())
    }
  } else {
    println(markdown)
  }
}
