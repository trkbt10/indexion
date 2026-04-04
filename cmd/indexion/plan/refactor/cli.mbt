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
pub(all) struct RefactorPlanConfig {
  target_dir : String
  threshold : Double // similarity threshold (default: 0.7 = 70%)
  strategy : String // "hybrid", "ncd", "tfidf"
  includes : Array[String] // glob patterns to include
  excludes : Array[String] // glob patterns to exclude
  output : String // output file path (empty = stdout)
  format : String // output format: "md", "json", "text"
  style : String // output style: "raw" (similarity), "structured" (plan)
  project_name : String // project name for structured output
  specs_dir : String // KGF specs directory
}

///|
/// Create default configuration.
pub fn RefactorPlanConfig::default() -> RefactorPlanConfig {
  {
    target_dir: "",
    threshold: 0.7,
    strategy: "hybrid",
    includes: [],
    excludes: [],
    output: "",
    format: "md",
    style: "raw",
    project_name: "",
    specs_dir: "kgfs",
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
/// Create RefactorPlanConfig from argparse matches.
pub fn RefactorPlanConfig::from_matches(
  matches : @argparse.Matches,
) -> RefactorPlanConfig {
  let threshold = match matches.values.get("threshold") {
    Some(arr) =>
      if arr.length() > 0 {
        @common.parse_double(arr[0])
      } else {
        0.7
      }
    _ => 0.7
  }
  let strategy = match matches.values.get("strategy") {
    Some(arr) => if arr.length() > 0 { arr[0] } else { "hybrid" }
    _ => "hybrid"
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
  let style = match matches.values.get("style") {
    Some(arr) => if arr.length() > 0 { arr[0] } else { "raw" }
    _ => "raw"
  }
  let project_name = match matches.values.get("name") {
    Some(arr) => if arr.length() > 0 { arr[0] } else { "" }
    _ => ""
  }
  let specs_dir = match matches.values.get("specs-dir") {
    Some(arr) => if arr.length() > 0 { arr[0] } else { "kgfs" }
    _ => "kgfs"
  }
  let target_dir = match matches.values.get("directory") {
    Some(arr) => if arr.length() > 0 { arr[0] } else { "" }
    _ => ""
  }
  {
    target_dir,
    threshold,
    strategy,
    includes,
    excludes,
    output,
    format,
    style,
    project_name,
    specs_dir,
  }
}

///|
/// Define the refactor command for argparse.
pub fn command() -> @argparse.Command {
  @argparse.Command(
    "refactor",
    about="Generate refactoring plan from similarity analysis",
    options=[
      @argparse.OptionArg("threshold", about="Similarity threshold (0.0-1.0)", default_values=[
        "0.7",
      ]),
      @argparse.OptionArg("strategy", about="Algorithm: hybrid, tfidf, ncd", default_values=[
        "hybrid",
      ]),
      @argparse.OptionArg("include", action=Append, about=@help.include_pattern),
      @argparse.OptionArg("exclude", action=Append, about=@help.exclude_pattern),
      @argparse.OptionArg("output", short='o', about=@help.output),
      @argparse.OptionArg(
        "format",
        about="Output format: md, json, text, github-issue",
        default_values=["md"],
      ),
      @argparse.OptionArg("style", about="Output style: raw, structured", default_values=[
        "raw",
      ]),
      @argparse.OptionArg("name", about="Project name for structured output"),
      @argparse.OptionArg("specs-dir", about=@help.specs_dir, default_values=[
        "kgfs",
      ]),
    ],
    positionals=[
      @argparse.PositionArg(
        "directory",
        num_args=@argparse.ValueRange(lower=1),
        about="Target directory to analyze",
      ),
    ],
  )
}

///|
/// Entry point using argparse matches.
pub fn run_matches(matches : @argparse.Matches) -> Unit {
  let config = RefactorPlanConfig::from_matches(matches)
  run_with_config(config)
}

// collect_files: use @common (SoT)

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
  line_funcs1? : Map[Int, String] = {},
  line_funcs2? : Map[Int, String] = {},
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
/// Render a refactor plan to the configured output format.
fn render_plan(config : RefactorPlanConfig, plan : RefactorPlanJSON) -> String {
  let name = if config.project_name.length() > 0 {
    config.project_name
  } else {
    extract_project_name(config.target_dir)
  }
  match config.format {
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
}

///|
/// Collect similar pairs from files using the configured strategy.
fn collect_similar_pairs(
  files : Array[(String, String)],
  config : RefactorPlanConfig,
) -> Array[SimilarPair] {
  let pairs : Array[SimilarPair] = []
  if config.strategy == "tfidf" || config.strategy == "hybrid" {
    let entries : Array[@batch.FileEntry] = []
    for f in files {
      entries.push(@batch.FileEntry::new(f.0, f.1))
    }
    let result = if config.strategy == "hybrid" {
      @batch.compare_hybrid(entries, config.threshold)
    } else {
      @batch.compare_tfidf(entries, config.threshold)
    }
    for m in result.matches {
      pairs.push({ file1: m.file1, file2: m.file2, similarity: m.similarity })
    }
  } else {
    let entries : Array[@batch.FileEntry] = []
    for f in files {
      entries.push(@batch.FileEntry::new(f.0, f.1))
    }
    let score_fn : (String, String) -> Double = match config.strategy {
      "ncd" => fn(t1, t2) { @ncd.NCDStrategy::new().similarity(t1, t2) }
      _ => fn(t1, t2) { @hybrid.HybridStrategy::new().similarity(t1, t2) }
    }
    let result = @batch.compare_with_prefilter(
      entries,
      config.threshold,
      score_fn,
    )
    for m in result.matches {
      pairs.push({ file1: m.file1, file2: m.file2, similarity: m.similarity })
    }
  }
  pairs
}

///|
/// Core refactor analysis. Returns rendered output string or None.
pub fn run_to_string(config : RefactorPlanConfig) -> String? {
  if config.target_dir.length() == 0 {
    return None
  }
  let registry = @kgf_features.load_registry(
    specs_dir=config.specs_dir,
    target_dir=config.target_dir,
  )
  let files = @common.collect_files(
    [config.target_dir],
    includes=config.includes,
    excludes=config.excludes,
  )
  if files.length() < 2 {
    return None
  }
  let pairs = collect_similar_pairs(files, config)
  let clusters = find_clusters(files, pairs, config.threshold)
  let file_contents : Map[String, String] = {}
  for f in files {
    file_contents.set(f.0, f.1)
  }
  let plan = build_refactor_plan(
    clusters,
    config,
    file_contents,
    effective_threshold=config.threshold,
    registry~,
  )
  let func_dups = find_function_duplicates(files, config.threshold, registry)
  let magic_strs = find_magic_strings(files, registry)
  let plan = {
    ..plan,
    function_duplicates: func_dups,
    magic_strings: magic_strs,
  }
  Some(render_plan(config, plan))
}

///|
/// Entry point with a pre-built configuration (with CLI progress output).
fn run_with_config(config : RefactorPlanConfig) -> Unit {
  if config.target_dir.length() == 0 {
    println(@help.dir_required)
    return
  }
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
  let registry = @kgf_features.load_registry(
    specs_dir=config.specs_dir,
    target_dir=config.target_dir,
  )
  // Detect project type from marker files
  let detected_markers : Array[String] = []
  match registry {
    Some(reg) => {
      let markers = reg.get_project_markers()
      let search_dirs = @common.ancestor_dirs(config.target_dir)
      for dir in search_dirs {
        let entries : Array[String] = @fs.read_dir(dir) catch { _ => continue }
        for marker in markers {
          for entry in entries {
            if @glob.glob_match(entry, marker) {
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
      let markers_str = detected_markers
        .iter()
        .fold(init="", fn(acc, m) {
          if acc.length() == 0 {
            m
          } else {
            acc + ", " + m
          }
        })
      println("Project type: " + markers_str)
    } else {
      println("Project type: unknown")
    }
    println("")
    println("[1/4] Collecting files...")
  }
  let files = @common.collect_files(
    [config.target_dir],
    includes=config.includes,
    excludes=config.excludes,
  )
  if show_progress {
    println("      Found " + files.length().to_string() + " files")
  }
  if files.length() < 2 {
    println("Error: Need at least 2 files to analyze.")
    return
  }
  if show_progress {
    println("[2/4] Calculating similarity pairs...")
  }
  let sim_started = @env.now()
  let pairs = collect_similar_pairs(files, config)
  if show_progress {
    println(
      "      Found " +
      pairs.length().to_string() +
      " pairs above threshold (" +
      @common.elapsed_ms(sim_started).to_string() +
      "ms)",
    )
    println("[3/4] Clustering and analyzing duplicates...")
  }
  let cluster_started = @env.now()
  let clusters = find_clusters(files, pairs, config.threshold)
  if show_progress {
    println(
      "      Clustering: " +
      clusters.length().to_string() +
      " clusters (" +
      @common.elapsed_ms(cluster_started).to_string() +
      "ms)",
    )
  }
  let file_contents : Map[String, String] = {}
  for f in files {
    file_contents.set(f.0, f.1)
  }
  let plan_started = @env.now()
  let plan = build_refactor_plan(
    clusters,
    config,
    file_contents,
    effective_threshold=config.threshold,
    registry~,
  )
  let func_dups = find_function_duplicates(files, config.threshold, registry)
  let magic_strs = find_magic_strings(files, registry)
  let plan = {
    ..plan,
    function_duplicates: func_dups,
    magic_strings: magic_strs,
  }
  if show_progress {
    println(
      "      Plan build: " +
      @common.elapsed_ms(plan_started).to_string() +
      "ms" +
      " (function duplicates: " +
      func_dups.length().to_string() +
      ", magic strings: " +
      magic_strs.length().to_string() +
      ")",
    )
    println("[4/4] Rendering " + config.format + " output...")
    println("")
  }
  let output_content = render_plan(config, plan)
  @common.write_output(config.output, output_content, label="Refactoring plan")
}

// format_github_issue: use @plan_render.GitHubIssue::format (SoT)

// marker_matches: use @glob.glob_match (SoT)
// ancestor_dirs, parent_dir: use @common (SoT)

///|
/// Detect structurally similar functions across and within files using TF-IDF.
/// This catches same-file duplicates (e.g., compare_apted ≈ compare_tsed)
/// and cross-file small-function duplicates that file-level TF-IDF misses.
fn find_function_duplicates(
  files : Array[(String, String)],
  threshold : Double,
  registry : @kgf_registry.KGFRegistry?,
) -> Array[FunctionDuplicate] {
  let reg = match registry {
    Some(r) => r
    None => return []
  }
  // Extract functions from all files
  let func_names : Array[String] = []
  let func_bodies : Array[String] = []
  let func_files : Array[String] = []
  for file in files {
    let (path, content) = file
    let lang = match reg.detect_from_path(path) {
      Some(l) => l
      None => continue
    }
    let spec = match reg.get_spec(lang) {
      Some(s) => s
      None => continue
    }
    let lexer = @kgf_lexer.Lexer::new(spec.get_tokens())
    let tokens = lexer.tokenize(content)
    let functions = @kgf_features.extract_functions(tokens, path, spec~)
    let lines = @common.split_lines(content)
    // Build token index → line number
    let token_lines : Array[Int] = Array::make(tokens.length(), 1)
    let mut line = 1
    for i, tok in tokens {
      token_lines[i] = line
      if tok.get_kind() == "NL" {
        line += 1
      }
    }
    for func in functions {
      let start_line = if func.get_start() < token_lines.length() {
        token_lines[func.get_start()]
      } else {
        1
      }
      let end_line = if func.get_end() < token_lines.length() {
        token_lines[func.get_end() - 1]
      } else {
        lines.length()
      }
      // Extract function body text
      let body_lines : Array[String] = []
      for li = start_line - 1; li < end_line && li < lines.length(); li = li + 1 {
        body_lines.push(lines[li])
      }
      if body_lines.length() < 5 {
        continue
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
      func_names.push(func.get_name())
      func_bodies.push(body)
      func_files.push(path)
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
  let pairs = batch.all_pairs_above_threshold(threshold)
  let duplicates : Array[FunctionDuplicate] = []
  for pair in pairs {
    let (i, j, sim) = pair
    let same_file = func_files[i] == func_files[j]
    // Skip if same function name in same file (self-match from overloads)
    if same_file && func_names[i] == func_names[j] {
      continue
    }
    duplicates.push({
      func1: func_names[i],
      func2: func_names[j],
      file1: func_files[i],
      file2: func_files[j],
      similarity: sim,
      same_file,
    })
  }
  duplicates.sort_by(fn(a, b) {
    if a.similarity > b.similarity {
      -1
    } else if a.similarity < b.similarity {
      1
    } else {
      0
    }
  })
  duplicates
}

// elapsed_ms: use @common (SoT)

///|
/// Detect string literals that appear in 2+ files.
fn find_magic_strings(
  files : Array[(String, String)],
  registry : @kgf_registry.KGFRegistry?,
) -> Array[MagicStringGroup] {
  let min_length = 4
  let min_files = 2
  // value → Array[(file, line)]
  let occurrences : Map[String, Array[(String, Int)]] = {}
  for item in files {
    let (path, content) = item
    let reg = match registry {
      Some(r) => r
      None => continue
    }
    let lang = match reg.detect_from_path(path) {
      Some(l) => l
      None => continue
    }
    let spec = match reg.get_spec(lang) {
      Some(s) => s
      None => continue
    }
    let lexer = @kgf_lexer.Lexer::new(spec.get_tokens())
    let tokens = lexer.tokenize(content)
    // Build line number tracking
    let mut line = 1
    for tok in tokens {
      let kind = tok.get_kind()
      if kind == "NL" {
        line += 1
        continue
      }
      if is_string_token_kind(kind) {
        let value = tok.get_value()
        if value.length() >= min_length {
          match occurrences.get(value) {
            Some(arr) => arr.push((path, line))
            None => occurrences.set(value, [(path, line)])
          }
        }
      }
    }
  }
  // Filter to strings appearing in 2+ distinct files
  let result : Array[MagicStringGroup] = []
  for entry in occurrences {
    let value = entry.0
    let locs = entry.1
    let files_seen : Map[String, Bool] = {}
    for loc in locs {
      files_seen.set(loc.0, true)
    }
    if files_seen.length() >= min_files {
      let occ : Array[MagicStringOccurrence] = []
      for loc in locs {
        occ.push({ file: loc.0, line: loc.1 })
      }
      result.push({ value, occurrences: occ, file_count: files_seen.length() })
    }
  }
  // Sort by file_count desc, then occurrence count desc
  result.sort_by(fn(a, b) {
    if a.file_count != b.file_count {
      b.file_count - a.file_count
    } else {
      b.occurrences.length() - a.occurrences.length()
    }
  })
  result
}

///|
/// Check if a token kind represents a string literal.
/// Uses naming convention from KGF specs rather than hardcoding language names.
fn is_string_token_kind(kind : String) -> Bool {
  kind.to_lower().contains("string") || kind == "Docstring"
}
