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

// get_arg_value, parse_double: use @common (SoT)

///|
pub fn parse_args(args : Array[String], start_idx : Int) -> RefactorPlanConfig {
  let mut config = RefactorPlanConfig::default()
  for i = start_idx; i < args.length(); i = i + 1 {
    let arg = args[i]
    if arg == "--help" || arg == "-h" {
      config = { ..config, show_help: true }
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
    } else if arg.has_prefix("--style=") {
      let value = @common.get_arg_value(arg, 8)
      config = { ..config, style: value }
    } else if arg.has_prefix("--name=") {
      let value = @common.get_arg_value(arg, 7)
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
  println(
    "  --format=FORMAT      Output format: md, json, text, github-issue (default: md)",
  )
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
  println("Formats:")
  println("  md           Standard Markdown output")
  println("  json         JSON intermediate representation")
  println("  text         Plain text output")
  println("  github-issue GitHub Issue format with labels and checklist")
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

// collect_files: use @common (SoT)

///|
/// Calculate similarity between two texts.
fn calc_similarity(text1 : String, text2 : String, strategy : String) -> Double {
  match strategy {
    "ncd" => {
      let s = @ncd.NCDStrategy::new()
      s.similarity(text1, text2)
    }
    "tfidf" => {
      let s = @tfidf_strategy.TfidfStrategy::new()
      s.similarity(text1, text2)
    }
    _ => {
      let s = @hybrid.HybridStrategy::new()
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
  // Build file-to-root lookup for O(1) cluster membership check
  let file_to_root : Map[String, Int] = {}
  for i, f in files {
    file_to_root.set(f.0, find(i))
  }
  // Group pairs by cluster root in one pass over pairs
  let cluster_pairs_map : Map[Int, Array[SimilarPair]] = {}
  for pair in pairs {
    if pair.similarity >= threshold {
      let root1 = file_to_root.get(pair.file1)
      let root2 = file_to_root.get(pair.file2)
      match (root1, root2) {
        (Some(r1), Some(r2)) =>
          if r1 == r2 {
            match cluster_pairs_map.get(r1) {
              Some(arr) => arr.push(pair)
              None => cluster_pairs_map.set(r1, [pair])
            }
          }
        _ => ()
      }
    }
  }
  // Build clusters
  let clusters : Array[FileCluster] = []
  for _, group in groups {
    if group.length() > 1 {
      // Look up pre-grouped pairs by root of first file
      let root = file_to_root.get(group[0]).unwrap()
      let cluster_pairs = cluster_pairs_map.get(root).unwrap_or([])
      // Sort pairs by similarity (descending)
      cluster_pairs.sort_by(fn(a, b) {
        if b.similarity > a.similarity {
          -1
        } else if b.similarity < a.similarity {
          1
        } else {
          0
        }
      })
      clusters.push({ files: group, pairs: cluster_pairs })
    }
  }
  // Sort clusters by max similarity (descending)
  clusters.sort_by(fn(a, b) {
    let max_a = if a.pairs.length() > 0 { a.pairs[0].similarity } else { 0.0 }
    let max_b = if b.pairs.length() > 0 { b.pairs[0].similarity } else { 0.0 }
    if max_b > max_a {
      -1
    } else if max_b < max_a {
      1
    } else {
      0
    }
  })
  clusters
}

// trim_line: use @common.trim_ascii_spaces (SoT)
// is_function_def, extract_func_name: replaced by @kgf_features.build_line_func_map (SoT)

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
/// Function name annotation is done by the caller via line_funcs maps
/// built from @kgf_features.build_line_func_map (language-agnostic).
fn find_duplicate_blocks(
  content1 : String,
  content2 : String,
  min_lines : Int,
  line_funcs1~ : Map[Int, String] = {},
  line_funcs2~ : Map[Int, String] = {},
) -> Array[DuplicateBlock] {
  let lines1 = @common.split_lines(content1)
  let lines2 = @common.split_lines(content2)
  let duplicates : Array[DuplicateBlock] = []
  // Skip empty or very short files
  if lines1.length() < min_lines || lines2.length() < min_lines {
    return duplicates
  }
  // Pre-compute trimmed lines to avoid repeated allocations
  let trimmed1 : Array[String] = Array::make(lines1.length(), "")
  let trimmed2 : Array[String] = Array::make(lines2.length(), "")
  for i, line in lines1 {
    trimmed1[i] = @common.trim_ascii_spaces(line)
  }
  for i, line in lines2 {
    trimmed2[i] = @common.trim_ascii_spaces(line)
  }
  // Build line hash map for file2
  let line_map : Map[String, Array[Int]] = {}
  for i, trimmed in trimmed2 {
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
    let trimmed = trimmed1[i]
    if trimmed.length() > 5 {
      match line_map.get(trimmed) {
        Some(positions) =>
          for j in positions {
            // Count matching lines using pre-computed trimmed arrays
            let mut count = 0
            while i + count < lines1.length() &&
                  j + count < lines2.length() &&
                  trimmed1[i + count] == trimmed2[j + count] {
              count = count + 1
            }
            if count >= min_lines {
              // Look up function name from KGF-built map (1-indexed)
              let func_name : String? = match line_funcs1.get(i + 1) {
                Some(name) => Some(name)
                None => line_funcs2.get(j + 1)
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
  duplicates.sort_by(fn(a, b) { b.line_count - a.line_count })
  duplicates
}

///|
/// Suggest target module for shared code.
fn suggest_shared_module(file1 : String, file2 : String) -> String {
  // Find common path prefix
  let parts1 = @common.split_by_slash(file1)
  let parts2 = @common.split_by_slash(file2)
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

// split_by_slash: use @common (SoT)

///|
/// Extract project name from directory path.
/// Uses the last non-trivial path component (skipping "." and "..").
fn extract_project_name(path : String) -> String {
  let parts = @common.split_by_slash(path)
  for i = parts.length() - 1; i >= 0; i = i - 1 {
    let part = parts[i]
    if part != "." && part != ".." && part.length() > 0 {
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
  // Progress output goes to stderr-equivalent: only print when stdout is not
  // carrying a machine-readable payload (json to stdout).
  let show_progress = config.output.length() > 0 || config.format != "json"
  if show_progress {
    println("=== indexion plan refactor ===")
    println(
      "Directory: " +
      config.target_dir +
      ", Strategy: " +
      config.strategy +
      ", Threshold: " +
      config.threshold.to_string(),
    )
    println("")
  }
  // Load KGF registry for language detection
  let registry = @kgf_features.load_registry(target_dir=config.target_dir)
  // Detect project type from marker files (search target dir and ancestors)
  let detected_markers : Array[String] = []
  match registry {
    Some(reg) => {
      let markers = reg.get_project_markers()
      let search_dirs = @common.ancestor_dirs(config.target_dir)
      for dir in search_dirs {
        let entries : Array[String] = try {
          @fs.read_dir(dir)
        } catch {
          _ => continue
        }
        for marker in markers {
          for entry in entries {
            if @glob.glob_match(entry, marker) {
              // Avoid duplicates
              let mut exists = false
              for existing in detected_markers {
                if existing == marker {
                  exists = true
                  break
                }
              }
              if !exists {
                detected_markers.push(marker)
              }
              break
            }
          }
        }
      }
    }
    None => ()
  }
  if show_progress {
    if detected_markers.length() > 0 {
      let markers_str = detected_markers.iter().fold(
        init="",
        fn(acc, m) {
          if acc.length() == 0 { m } else { acc + ", " + m }
        },
      )
      println("Project type: " + markers_str)
    } else {
      println("Project type: unknown")
    }
    println("")
  }
  // [1/4] Collect files
  if show_progress {
    println("[1/4] Collecting files...")
  }
  let files = @common.collect_files(
    [config.target_dir], includes=config.includes, excludes=config.excludes,
  )
  if show_progress {
    println("      Found " + files.length().to_string() + " files")
  }
  if files.length() < 2 {
    println("Error: Need at least 2 files to analyze.")
    return
  }
  // [2/4] Calculate all pairs using optimized batch processing for TF-IDF
  if show_progress {
    println("[2/4] Calculating similarity pairs...")
  }
  let sim_started = @env.now()
  let pairs : Array[SimilarPair] = []
  let mut effective_threshold = config.threshold
  if config.strategy == "tfidf" {
    // Tokenize files with KGF where available
    if show_progress {
      println("      Tokenizing with KGF lexer...")
    }
    let tok_started = @env.now()
    let (tokenized, _) = @kgf_features.tokenize_files_with_kgf(files, registry)
    if show_progress {
      println(
        "      Tokenized " +
        tokenized.length().to_string() +
        " files (" +
        @common.elapsed_ms(tok_started).to_string() +
        "ms)",
      )
      println("      Building TF-IDF vectors...")
    }
    let build_started = @env.now()
    let batch = @tfidf.TfidfBatch::from_tokens(tokenized)
    if show_progress {
      println(
        "      Vectors built (" +
        @common.elapsed_ms(build_started).to_string() +
        "ms)",
      )
      // Adaptive threshold: for large file sets, start with a higher threshold
      // and step down if too few results, to avoid O(n²) explosion
      println("      Searching pairs...")
    }
    let (results, adapted) = adaptive_tfidf_search(
      batch, files.length(), config.threshold,
    )
    effective_threshold = adapted
    if show_progress && effective_threshold > config.threshold {
      println(
        "      Adaptive threshold: " +
        config.threshold.to_string() +
        " -> " +
        effective_threshold.to_string(),
      )
    }
    for result in results {
      let (i, j, sim) = result
      pairs.push({ file1: files[i].0, file2: files[j].0, similarity: sim })
    }
  } else {
    // Fallback for NCD/Hybrid strategies
    let total_pairs = files.length() * (files.length() - 1) / 2
    if show_progress {
      println(
        "      Comparing " +
        total_pairs.to_string() +
        " pairs (" +
        config.strategy +
        ")...",
      )
    }
    for i = 0; i < files.length(); i = i + 1 {
      for j = i + 1; j < files.length(); j = j + 1 {
        let sim = calc_similarity(files[i].1, files[j].1, config.strategy)
        if sim >= config.threshold {
          pairs.push({ file1: files[i].0, file2: files[j].0, similarity: sim })
        }
      }
    }
  }
  if show_progress {
    println(
      "      Found " +
      pairs.length().to_string() +
      " pairs above threshold (" +
      @common.elapsed_ms(sim_started).to_string() +
      "ms)",
    )
  }
  // [3/4] Find clusters and build plan
  if show_progress {
    println("[3/4] Clustering and analyzing duplicates...")
  }
  let cluster_started = @env.now()
  let clusters = find_clusters(files, pairs, effective_threshold)
  if show_progress {
    println(
      "      Clustering: " +
      clusters.length().to_string() +
      " clusters (" +
      @common.elapsed_ms(cluster_started).to_string() +
      "ms)",
    )
  }
  // Build file contents map for concrete suggestions
  let file_contents : Map[String, String] = {}
  for f in files {
    file_contents.set(f.0, f.1)
  }
  // Build intermediate plan
  let plan_started = @env.now()
  let plan = build_refactor_plan(
    clusters, config, file_contents, effective_threshold~, registry~,
  )
  if show_progress {
    println(
      "      Plan build: " +
      @common.elapsed_ms(plan_started).to_string() +
      "ms",
    )
  }
  // [4/4] Render to selected format/style
  let name = if config.project_name.length() > 0 {
    config.project_name
  } else {
    extract_project_name(config.target_dir)
  }
  if show_progress {
    println("[4/4] Rendering " + config.format + " output...")
    println("")
  }
  let output_content = match config.format {
    "github-issue" => {
      let doc = refactor_to_plan_document(plan, name)
      let issue = @plan_render.render_github_issue(doc)
      issue.format()
    }
    _ =>
      match config.style {
        "structured" => render_structured(plan, name)
        _ =>
          match config.format {
            "json" => render_json(plan)
            "text" => render_text(plan)
            _ => render_markdown(plan)
          }
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

// format_github_issue: use @plan_render.GitHubIssue::format (SoT)

// marker_matches: use @glob.glob_match (SoT)
// ancestor_dirs, parent_dir: use @common (SoT)

///|
/// Adaptive TF-IDF search: for large file sets, start with a higher threshold
/// and step down until we get enough results or reach the base threshold.
///
/// This avoids the pathological case where a low threshold produces hundreds of
/// thousands of candidate pairs in the inverted index, making cosine evaluation
/// extremely slow.
fn adaptive_tfidf_search(
  batch : @tfidf.TfidfBatch,
  file_count : Int,
  base_threshold : Double,
) -> (Array[(Int, Int, Double)], Double) {
  // For small file sets, just use the base threshold directly
  let adaptive_file_threshold = 200
  if file_count <= adaptive_file_threshold {
    return (batch.all_pairs_above_threshold(base_threshold), base_threshold)
  }
  // Step down from 0.9 to base_threshold
  let steps : Array[Double] = [0.9, 0.85, 0.8, 0.75]
  let max_pairs = 10000
  for step in steps {
    if step <= base_threshold {
      break
    }
    let results = batch.all_pairs_above_threshold(step)
    if results.length() > 0 {
      // If we got a reasonable number, return with this threshold
      if results.length() <= max_pairs {
        return (results, step)
      }
      // Too many even at this threshold, use it anyway (it's the best we can do)
      return (results, step)
    }
  }
  // Fall back to base threshold
  (batch.all_pairs_above_threshold(base_threshold), base_threshold)
}

// elapsed_ms: use @common (SoT)
