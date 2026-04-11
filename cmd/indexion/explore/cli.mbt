///|
/// # indexion explore
///
/// Analyze similarity across files in a directory.
///
/// ## Overview
///
/// Explores a directory and calculates pairwise similarity between all files.
/// Useful for understanding code patterns and finding potential duplications.
///
/// ## Usage
///
/// ```bash
/// indexion explore [options] <directory>
/// ```
///
/// ## Options
///
/// | Option | Description | Default |
/// |--------|-------------|---------|
/// | `--format=FORMAT` | Output: `matrix`, `list`, `cluster`, `json` | matrix |
/// | `--strategy=NAME` | Algorithm: `tfidf`, `ncd`, `hybrid` | tfidf |
/// | `--threshold=FLOAT` | Min similarity for list/json/cluster output | 0.5 |
/// | `--ext=EXT` | File extension filter (repeatable) | all |
/// | `--include=PATTERN` | Include files matching glob pattern | * |
/// | `--exclude=PATTERN` | Exclude files matching glob pattern | - |
/// | `--specs-dir=DIR` | KGF specs directory | kgfs |
///
/// ## Examples
///
/// ```bash
/// # Matrix view of all files
/// indexion explore src/
///
/// # List sorted by similarity
/// indexion explore --format=list src/
///
/// # Cluster similar files (70%+)
/// indexion explore --format=cluster --threshold=0.7 src/
///
/// # Filter by extension
/// indexion explore --ext=.mbt --ext=.kgf src/
///
/// # TypeScript only with glob filters
/// indexion explore --format=list --include=*.ts --include=*.tsx src/
/// ```
///
/// ## Output Formats
///
/// - **matrix**: Grid showing pairwise similarity percentages
/// - **list**: Pairs sorted by similarity (highest first)
/// - **cluster**: Groups of files exceeding threshold
/// - **json**: Machine-readable JSON output

///|
/// CLI configuration.
pub(all) struct ExploreConfig {
  target_dirs : Array[String] // multiple directories supported
  format : String // "matrix", "list", "cluster", "json"
  strategy : String // "hybrid", "ncd", "tfidf", "apted", "tsed", "bm25", "jsd"
  threshold : Double // similarity threshold for clustering
  fdr : Double // FDR correction level (0 = disabled, 0.05 = 5% FDR)
  extensions : Array[String] // file extensions to include
  includes : Array[String] // glob patterns to include
  excludes : Array[String] // glob patterns to exclude
  specs_dir : String
}

///|
/// Create default CLI configuration.
pub fn ExploreConfig::default() -> ExploreConfig {
  {
    target_dirs: [],
    format: "matrix",
    strategy: "tfidf",
    threshold: 0.5,
    fdr: 0.0,
    extensions: [],
    includes: [],
    excludes: [],
    specs_dir: "kgfs",
  }
}

///|
/// Create ExploreConfig from argparse matches.
pub fn ExploreConfig::from_matches(
  matches : @argparse.Matches,
) -> ExploreConfig {
  let format = match matches.values.get("format") {
    Some(arr) => if arr.length() > 0 { arr[0] } else { "matrix" }
    _ => "matrix"
  }
  let strategy = match matches.values.get("strategy") {
    Some(arr) => if arr.length() > 0 { arr[0] } else { "tfidf" }
    _ => "tfidf"
  }
  let threshold = match matches.values.get("threshold") {
    Some(arr) =>
      if arr.length() > 0 {
        @common.parse_double(arr[0])
      } else {
        0.5
      }
    _ => 0.5
  }
  let extensions = match matches.values.get("ext") {
    Some(arr) => arr
    _ => []
  }
  let includes = match matches.values.get("include") {
    Some(arr) => arr
    _ => []
  }
  let excludes = match matches.values.get("exclude") {
    Some(arr) => arr
    _ => []
  }
  let target_dirs = match matches.values.get("directory") {
    Some(arr) => arr
    _ => []
  }
  let specs_dir = match matches.values.get("specs-dir") {
    Some(arr) => if arr.length() > 0 { arr[0] } else { "kgfs" }
    _ => "kgfs"
  }
  let fdr = match matches.values.get("fdr") {
    Some(arr) =>
      if arr.length() > 0 {
        @common.parse_double(arr[0])
      } else {
        0.0
      }
    _ => 0.0
  }
  {
    target_dirs,
    format,
    strategy,
    threshold,
    fdr,
    extensions,
    includes,
    excludes,
    specs_dir,
  }
}

///|
/// Define the explore command for argparse.
pub fn command() -> @argparse.Command {
  @argparse.Command(
    "explore",
    about="Analyze similarity across files in a directory",
    options=[
      @argparse.OptionArg(
        "format",
        about="Output format: matrix, list, cluster, json",
        default_values=["matrix"],
      ),
      @argparse.OptionArg(
        "strategy",
        about="Similarity strategy: tfidf, bm25, jsd, ncd, hybrid, apted, tsed",
        default_values=["tfidf"],
      ),
      @argparse.OptionArg(
        "threshold",
        about="Min similarity for list/json/cluster output",
        default_values=["0.5"],
      ),
      @argparse.OptionArg(
        "ext",
        action=Append,
        about="File extension to include (repeatable)",
      ),
      @argparse.OptionArg("include", action=Append, about=@help.include_pattern),
      @argparse.OptionArg("exclude", action=Append, about=@help.exclude_pattern),
      @argparse.OptionArg(
        "fdr",
        about="FDR correction level (0=disabled, 0.05=5% false discovery rate)",
        default_values=["0"],
      ),
      @argparse.OptionArg("specs-dir", about=@help.specs_dir, default_values=[
        "kgfs",
      ]),
    ],
    positionals=[
      @argparse.PositionArg(
        "directory",
        num_args=@argparse.ValueRange(lower=0),
        about="Target directories to analyze",
      ),
    ],
  )
}

///|
/// File pair with similarity score.
priv struct FilePair {
  file1 : String
  file2 : String
  similarity : Double
  _distance : Double
}

// collect_files: use @common (SoT)

///|
/// Filter pairs to keep only cross-directory pairs.
fn filter_cross_dir_pairs(pairs : Array[FilePair]) -> Array[FilePair] {
  let result : Array[FilePair] = []
  for pair in pairs {
    let dir1 = @common.get_dirname_prefix(pair.file1)
    let dir2 = @common.get_dirname_prefix(pair.file2)
    // Keep only if both have prefixes and they differ
    if dir1.length() > 0 && dir2.length() > 0 && dir1 != dir2 {
      result.push(pair)
    }
  }
  result
}

///|
fn pair_threshold_for_format(format : String, threshold : Double) -> Double {
  match format {
    "matrix" => 0.0
    _ => threshold
  }
}

// elapsed_ms: use @common (SoT)

///|
fn calculate_tfidf_pairs(
  batch : @tfidf.TfidfBatch,
  files : Array[(String, String)],
  min_similarity : Double,
) -> (Array[FilePair], @tfidf.TfidfPairSearchStats) {
  let pairs : Array[FilePair] = []
  let (results, search_stats) = batch.all_pairs_above_threshold_with_stats(
    min_similarity,
  )
  for result in results {
    let (i, j, sim) = result
    pairs.push({
      file1: files[i].0,
      file2: files[j].0,
      similarity: sim,
      _distance: 1.0 - sim,
    })
  }
  (pairs, search_stats)
}

///|
fn calculate_pairs(
  files : Array[(String, String)],
  strategy : String,
  min_similarity : Double,
) -> Array[FilePair] {
  let entries : Array[@batch.FileEntry] = []
  for f in files {
    entries.push(@batch.FileEntry::new(f.0, f.1))
  }
  let score_fn : (String, String) -> Double = match strategy {
    "ncd" => fn(t1, t2) { @ncd.NCDStrategy::new().similarity(t1, t2) }
    _ => fn(t1, t2) { @hybrid.HybridStrategy::new().similarity(t1, t2) }
  }
  let result = @batch.compare_with_prefilter(entries, min_similarity, score_fn)
  let pairs : Array[FilePair] = []
  for m in result.matches {
    pairs.push({
      file1: m.file1,
      file2: m.file2,
      similarity: m.similarity,
      _distance: 1.0 - m.similarity,
    })
  }
  pairs
}

// format_percent: use @common (SoT)

///|
/// Output as matrix format.
fn output_matrix(
  files : Array[(String, String)],
  pairs : Array[FilePair],
) -> Unit {
  if files.length() == 0 {
    println("No files found.")
    return
  }
  // Build lookup map
  let pair_map : Map[String, Double] = {}
  for pair in pairs {
    let key = pair.file1 + "|" + pair.file2
    pair_map.set(key, pair.similarity)
    let key2 = pair.file2 + "|" + pair.file1
    pair_map.set(key2, pair.similarity)
  }
  // Header
  let mut header = "| |"
  for f in files {
    header = header + " " + @common.truncate(f.0, 10) + " |"
  }
  println(header)
  // Separator
  let mut sep = "|--|"
  for _ in files {
    sep = sep + "--------|"
  }
  println(sep)
  // Rows
  for f1 in files {
    let mut row = "| " + @common.truncate(f1.0, 10) + " |"
    for f2 in files {
      if f1.0 == f2.0 {
        row = row + " - |"
      } else {
        let key = f1.0 + "|" + f2.0
        match pair_map.get(key) {
          Some(sim) => row = row + " " + @common.format_percent(sim) + " |"
          None => row = row + " ? |"
        }
      }
    }
    println(row)
  }
}

///|
/// Output as list format (sorted by similarity).
fn output_list(pairs : Array[FilePair]) -> Unit {
  if pairs.length() == 0 {
    println("No file pairs found.")
    return
  }
  pairs.sort_by(fn(a, b) { b.similarity.compare(a.similarity) })
  println("=== File Similarity (sorted) ===")
  println("")
  for pair in pairs {
    println(
      @common.format_percent(pair.similarity) +
      "  " +
      pair.file1 +
      " <-> " +
      pair.file2,
    )
  }
}

///|
/// Output as cluster format.
fn output_cluster(
  files : Array[(String, String)],
  pairs : Array[FilePair],
  threshold : Double,
) -> Unit {
  if files.length() == 0 {
    println("No files found.")
    return
  }
  // Simple clustering: group files with similarity >= threshold
  let clusters : Array[Array[String]] = []
  let assigned : Map[String, Bool] = {}
  for f in files {
    assigned.set(f.0, false)
  }
  for f in files {
    match assigned.get(f.0) {
      Some(true) => continue
      _ => ()
    }
    let cluster : Array[String] = [f.0]
    assigned.set(f.0, true)
    for pair in pairs {
      if pair.similarity >= threshold {
        if pair.file1 == f.0 {
          match assigned.get(pair.file2) {
            Some(false) => {
              cluster.push(pair.file2)
              assigned.set(pair.file2, true)
            }
            _ => ()
          }
        } else if pair.file2 == f.0 {
          match assigned.get(pair.file1) {
            Some(false) => {
              cluster.push(pair.file1)
              assigned.set(pair.file1, true)
            }
            _ => ()
          }
        }
      }
    }
    clusters.push(cluster)
  }
  println(
    "=== Clusters (threshold: " + @common.format_percent(threshold) + ") ===",
  )
  println("")
  for i, cluster in clusters {
    if cluster.length() > 0 {
      let mut line = "Cluster " + (i + 1).to_string() + ": "
      for j, f in cluster {
        if j > 0 {
          line = line + ", "
        }
        line = line + f
      }
      println(line)
    }
  }
}

///|
/// Build JSON result from files and pairs using Json type.
fn build_json(files : Array[(String, String)], pairs : Array[FilePair]) -> Json {
  let files_json : Array[Json] = files
    .iter()
    .map(fn(f) { f.0.to_json() })
    .collect()
  let pairs_json : Array[Json] = pairs
    .iter()
    .map(fn(pair) {
      let obj : Map[String, Json] = {}
      obj.set("file1", pair.file1.to_json())
      obj.set("file2", pair.file2.to_json())
      obj.set("similarity", pair.similarity.to_json())
      Json::object(obj)
    })
    .collect()
  let root : Map[String, Json] = {}
  root.set("files", Json::array(files_json))
  root.set("pairs", Json::array(pairs_json))
  Json::object(root)
}

///|
/// Output as JSON format.
fn output_json(
  files : Array[(String, String)],
  pairs : Array[FilePair],
) -> Unit {
  println(build_json(files, pairs).stringify(indent=2))
}

// truncate: use @common (SoT)

///|
/// Core explore logic. Returns (files, filtered_pairs) or None on failure.
fn run_core(
  config : ExploreConfig,
) -> (Array[(String, String)], Array[FilePair])? {
  if config.target_dirs.length() == 0 {
    return None
  }
  let registry = @kgf_features.load_registry(
    specs_dir=config.specs_dir,
    target_dirs=config.target_dirs,
  )
  let files = @common.collect_files(
    config.target_dirs,
    includes=config.includes,
    excludes=config.excludes,
    extensions=config.extensions,
    registry~,
  )
  if files.length() < 2 {
    return None
  }
  let min_similarity = pair_threshold_for_format(
    config.format,
    config.threshold,
  )
  let is_tree_strategy = config.strategy == "apted" || config.strategy == "tsed"
  let pairs = if is_tree_strategy {
    calculate_function_pairs(files, config.strategy, min_similarity, registry)
  } else if config.strategy == "tfidf" {
    let (tokenized, _) = @kgf_features.tokenize_files_with_kgf(files, registry)
    let batch = @tfidf.TfidfBatch::from_tokens(tokenized)
    let (pairs, _) = calculate_tfidf_pairs(batch, files, min_similarity)
    pairs
  } else if config.strategy == "bm25" || config.strategy == "jsd" {
    calculate_batch_pairs(files, config.strategy, min_similarity)
  } else {
    calculate_pairs(files, config.strategy, min_similarity)
  }
  let is_cross_dir = config.target_dirs.length() > 1
  let dir_filtered = if is_cross_dir {
    filter_cross_dir_pairs(pairs)
  } else {
    pairs
  }
  // Apply FDR correction if enabled
  let filtered_pairs = if config.fdr > 0.0 {
    // The BH denominator must match the hypothesis family being tested.
    // After cross-directory filtering, only cross-directory pairs remain,
    // so the denominator is the number of cross-directory combinations,
    // not all-file nC2.
    let total_pairs = if is_cross_dir {
      count_cross_dir_pairs(files)
    } else {
      files.length() * (files.length() - 1) / 2
    }
    apply_fdr_to_file_pairs(
      dir_filtered,
      total_pairs,
      config.fdr,
      min_similarity,
    )
  } else {
    dir_filtered
  }
  Some((files, filtered_pairs))
}

///|
/// Run explore and return result as JSON string.
pub fn run_to_json(config : ExploreConfig) -> String? {
  match run_core(config) {
    Some((files, pairs)) => Some(build_json(files, pairs).stringify())
    None => None
  }
}

///|
/// Run the explore command from argparse matches (with CLI progress output).
pub fn run_matches(matches : @argparse.Matches) -> Unit {
  let config = ExploreConfig::from_matches(matches)
  if config.target_dirs.length() == 0 {
    println(@help.dir_required)
    return
  }
  println("=== indexion explore ===")
  let dirs_str = config.target_dirs
    .iter()
    .fold(init="", fn(acc, d) {
      if acc.length() == 0 {
        d
      } else {
        acc + ", " + d
      }
    })
  println("Directories: " + dirs_str)
  println("Strategy: " + config.strategy)
  println("")
  println("[1/2] Scanning files...")
  // Delegate to run_core (SoT for explore logic)
  let (files, filtered_pairs) = match run_core(config) {
    Some(r) => r
    None => {
      println("Need at least 2 files to compare.")
      return
    }
  }
  println(
    "      Done (" +
    filtered_pairs.length().to_string() +
    " pairs from " +
    files.length().to_string() +
    " files)",
  )
  println("")
  match config.format {
    "list" => output_list(filtered_pairs)
    "cluster" => output_cluster(files, filtered_pairs, config.threshold)
    "json" => output_json(files, filtered_pairs)
    _ => output_matrix(files, filtered_pairs)
  }
}

///|
/// Count the number of cross-directory file pairs.
/// Groups files by their directory prefix (the part before ':'),
/// then sums |dir_i| × |dir_j| for all i < j.
fn count_cross_dir_pairs(files : Array[(String, String)]) -> Int {
  // Count files per directory prefix
  let dir_counts : Map[String, Int] = {}
  for f in files {
    let prefix = @common.get_dirname_prefix(f.0)
    let current = dir_counts.get(prefix).unwrap_or(0)
    dir_counts.set(prefix, current + 1)
  }
  // Collect counts into array
  let counts : Array[Int] = []
  for entry in dir_counts {
    counts.push(entry.1)
  }
  // Sum cross-bucket combinations: Σ_{i<j} counts[i] × counts[j]
  let mut total = 0
  for i = 0; i < counts.length(); i = i + 1 {
    for j = i + 1; j < counts.length(); j = j + 1 {
      total += counts[i] * counts[j]
    }
  }
  // Ensure at least 1 to avoid division by zero in BH
  if total < 1 {
    1
  } else {
    total
  }
}

///|
/// Calculate pairs using @batch.compare for strategies that have
/// dedicated batch implementations (bm25, jsd, etc.).
fn calculate_batch_pairs(
  files : Array[(String, String)],
  strategy : String,
  min_similarity : Double,
) -> Array[FilePair] {
  let entries : Array[@batch.FileEntry] = []
  for f in files {
    entries.push(@batch.FileEntry::new(f.0, f.1))
  }
  let result = @batch.compare(
    entries,
    @batch.BatchConfig::create(min_similarity, strategy),
  )
  let pairs : Array[FilePair] = []
  for m in result.matches {
    pairs.push({
      file1: m.file1,
      file2: m.file2,
      similarity: m.similarity,
      _distance: 1.0 - m.similarity,
    })
  }
  pairs
}

///|
/// Apply BH FDR correction to FilePair results.
/// Converts FilePairs to SimilarityMatches, applies FDR, converts back.
/// `total_pairs` is the number of hypotheses tested (the family size for BH).
fn apply_fdr_to_file_pairs(
  pairs : Array[FilePair],
  total_pairs : Int,
  alpha : Double,
  threshold : Double,
) -> Array[FilePair] {
  let matches : Array[@batch.SimilarityMatch] = []
  for i, pair in pairs {
    matches.push(
      @batch.SimilarityMatch::new(i, 0, pair.file1, pair.file2, pair.similarity),
    )
  }
  let filtered = @batch.apply_fdr_correction(
    matches,
    alpha,
    total_pairs,
    threshold~,
  )
  let result : Array[FilePair] = []
  for m in filtered {
    result.push({
      file1: m.file1,
      file2: m.file2,
      similarity: m.similarity,
      _distance: 1.0 - m.similarity,
    })
  }
  result
}

///|
/// Calculate function-level similarity pairs using APTED or TSED.
fn calculate_function_pairs(
  files : Array[(String, String)],
  strategy : String,
  min_similarity : Double,
  registry : @registry.KGFRegistry?,
) -> Array[FilePair] {
  let pairs : Array[FilePair] = []
  let resolved_registry = match registry {
    Some(r) => r
    None => {
      println("      Warning: KGF registry not found, cannot extract functions")
      return pairs
    }
  }
  // Extract functions from all files
  println("      Extracting functions...")
  let all_functions : Array[(@kgf_features.ExtractedFunction, @apted.TreeNode)] = []
  let mut total_functions = 0
  for file in files {
    let (path, content) = file
    // Detect language and get spec
    match resolved_registry.detect_from_path(path) {
      Some(lang) =>
        match resolved_registry.get_spec(lang) {
          Some(spec) => {
            // Tokenize
            let lexer = @kgf_lexer.Lexer::new(spec.get_tokens())
            let tokens = lexer.tokenize(content)
            // Extract functions and convert to TreeNodes
            let func_trees = @kgf_features.extract_function_trees(
              tokens,
              path,
              spec~,
            )
            for ft in func_trees {
              all_functions.push(ft)
              total_functions += 1
            }
          }
          None => ()
        }
      None => ()
    }
  }
  println("      Found " + total_functions.to_string() + " functions")
  if all_functions.length() < 2 {
    println("      Need at least 2 functions to compare")
    return pairs
  }
  // Calculate function pairs
  let total_fn_pairs = all_functions.length() * (all_functions.length() - 1) / 2
  println(
    "      Comparing " + total_fn_pairs.to_string() + " function pairs...",
  )
  let cost_config = @apted.CostConfig::default()
  let tsed_config = @apted.TSEDConfig::default()
  for i = 0; i < all_functions.length(); i = i + 1 {
    let (func1, tree1) = all_functions[i]
    for j = i + 1; j < all_functions.length(); j = j + 1 {
      let (func2, tree2) = all_functions[j]
      // Skip comparing functions from the same file with the same name
      if func1.get_file() == func2.get_file() &&
        func1.get_name() == func2.get_name() {
        continue
      }
      // Calculate similarity based on strategy
      let sim = if strategy == "tsed" {
        @apted.calculate_tsed(tree1, tree2, tsed_config)
      } else {
        @apted.tree_similarity(tree1, tree2, cost_config)
      }
      if sim >= min_similarity {
        pairs.push({
          file1: func1.qualified_name(),
          file2: func2.qualified_name(),
          similarity: sim,
          _distance: 1.0 - sim,
        })
      }
    }
  }
  pairs
}
