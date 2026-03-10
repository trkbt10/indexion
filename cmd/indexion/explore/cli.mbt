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
pub struct ExploreConfig {
  target_dirs : Array[String] // multiple directories supported
  format : String // "matrix", "list", "cluster", "json"
  strategy : String // "hybrid", "ncd", "tfidf", "apted", "tsed"
  threshold : Double // similarity threshold for clustering
  extensions : Array[String] // file extensions to include
  includes : Array[String] // glob patterns to include
  excludes : Array[String] // glob patterns to exclude
  show_help : Bool
}

///|
/// Create default CLI configuration.
pub fn ExploreConfig::default() -> ExploreConfig {
  {
    target_dirs: [],
    format: "matrix",
    strategy: "tfidf",
    threshold: 0.5,
    extensions: [],
    includes: [],
    excludes: [],
    show_help: false,
  }
}

///|
/// File pair with similarity score.
priv struct FilePair {
  file1 : String
  file2 : String
  similarity : Double
  _distance : Double
}

// get_arg_value and parse_double are now in @common (SoT)

///|
/// Parse command line arguments into ExploreConfig.
pub fn parse_explore_args(
  args : Array[String],
  start_idx : Int,
) -> ExploreConfig {
  let mut config = ExploreConfig::default()
  for i = start_idx; i < args.length(); i = i + 1 {
    let arg = args[i]
    if arg == "--help" || arg == "-h" {
      config = { ..config, show_help: true }
    } else if arg.has_prefix("--format=") {
      let value = @common.get_arg_value(arg, 9)
      config = { ..config, format: value }
    } else if arg.has_prefix("--strategy=") {
      let value = @common.get_arg_value(arg, 11)
      config = { ..config, strategy: value }
    } else if arg.has_prefix("--threshold=") {
      let value = @common.get_arg_value(arg, 12)
      config = { ..config, threshold: @common.parse_double(value) }
    } else if arg.has_prefix("--ext=") {
      let value = @common.get_arg_value(arg, 6)
      config.extensions.push(value)
    } else if arg.has_prefix("--include=") {
      let value = @common.get_arg_value(arg, 10)
      config.includes.push(value)
    } else if arg.has_prefix("--exclude=") {
      let value = @common.get_arg_value(arg, 10)
      config.excludes.push(value)
    } else if not(arg.has_prefix("-")) {
      config.target_dirs.push(arg)
    }
  }
  config
}

///|
/// Display help message for explore command.
pub fn show_explore_help() -> Unit {
  println("indexion explore - Analyze similarity across files")
  println("")
  println("Usage:")
  println("  indexion explore [options] <directory>")
  println("")
  println("Options:")
  println(
    "  --format=FORMAT      Output format: matrix, list, cluster, json (default: matrix)",
  )
  println(
    "  --strategy=NAME      Similarity strategy: tfidf, ncd, hybrid, apted, tsed (default: tfidf)",
  )
  println(
    "                       apted/tsed: function-level tree edit distance",
  )
  println(
    "  --threshold=FLOAT    Min similarity for list/json/cluster output (default: 0.5)",
  )
  println("  --ext=EXT            File extension to include (can be repeated)")
  println(
    "  --include=PATTERN    Include files matching pattern (can be repeated)",
  )
  println(
    "  --exclude=PATTERN    Exclude files matching pattern (can be repeated)",
  )
  println("  --help               Show this help message")
  println("")
  println("Examples:")
  println("  indexion explore kgfs/")
  println("  indexion explore --format=list --strategy=tfidf src/")
  println("  indexion explore --format=cluster --threshold=0.7 kgfs/")
  println("  indexion explore --ext=.mbt --ext=.kgf .")
  println("  indexion explore --include=*.ts --include=*.tsx src/")
  println("")
  println("Function-level similarity (apted/tsed):")
  println("  indexion explore --strategy=apted --format=list src/")
  println("  indexion explore --strategy=tsed --threshold=0.8 src/")
}

///|
/// Collect files from multiple directories using pipeline.discover_files (SoT).
/// When multiple directories are given, display_name is "dirname:relative_path".
fn collect_files_multi(
  dirs : Array[String],
  extensions : Array[String],
  includes : Array[String],
  excludes : Array[String],
) -> Array[(String, String)] {
  let files : Array[(String, String)] = []
  let multi_dir = dirs.length() > 1
  // Get unique names for each directory (handles "src" vs "src" case)
  let dir_names = @common.extract_unique_dir_names(dirs)
  for i, dir in dirs {
    // Use pipeline.discover_files as SoT for filtering
    let opts = @pipeline.DiscoverOptions::new(
      includes~,
      excludes~,
      root_dir=dir,
    )
    let paths = @pipeline.discover_files([dir], opts)
    // Use unique dirname for prefix
    let dirname = dir_names[i]
    // Filter by extensions and read contents
    for path in paths {
      let basename = @pipeline.extract_basename(path)
      // Check extension filter
      let ext_ok = if extensions.length() == 0 {
        true
      } else {
        let mut matched = false
        for ext in extensions {
          if basename.has_suffix(ext) {
            matched = true
            break
          }
        }
        matched
      }
      if ext_ok {
        try {
          let content = @fs.read_file_to_string(path)
          let relative = @common.make_relative_path(path, dir)
          // Prefix with dirname when multiple directories
          let display_name = if multi_dir {
            dirname + ":" + relative
          } else {
            relative
          }
          files.push((display_name, content))
        } catch {
          _ => ()
        }
      }
    }
  }
  files
}

// Path utilities: use @common (SoT)

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
/// Calculate similarity between two texts.
fn calc_similarity(
  text1 : String,
  text2 : String,
  strategy : String,
) -> (Double, Double) {
  match strategy {
    "ncd" => {
      let s = @ncd.NCDStrategy::new()
      (s.distance(text1, text2), s.similarity(text1, text2))
    }
    "tfidf" => {
      let s = @tfidf_strategy.TfidfStrategy::new()
      (s.distance(text1, text2), s.similarity(text1, text2))
    }
    _ => {
      let s = @hybrid.HybridStrategy::new()
      (s.distance(text1, text2), s.similarity(text1, text2))
    }
  }
}

///|
fn pair_threshold_for_format(format : String, threshold : Double) -> Double {
  match format {
    "matrix" => 0.0
    _ => threshold
  }
}

///|
fn elapsed_ms(start_ms : UInt64) -> UInt64 {
  let now = @env.now()
  if now >= start_ms {
    now - start_ms
  } else {
    0UL
  }
}

///|
fn average_count(total : Int, count : Int) -> Int {
  if count <= 0 {
    0
  } else {
    total / count
  }
}

///|
fn report_tfidf_build_stats(
  stats : @tfidf.TfidfBatchBuildStats,
  elapsed : UInt64,
) -> Unit {
  println(
    "      TF-IDF build: " +
    stats.total_tokens.to_string() +
    " tokens (" +
    average_count(stats.total_tokens, stats.document_count).to_string() +
    "/file), " +
    stats.total_vector_terms.to_string() +
    " vector terms, " +
    stats.vocabulary_size.to_string() +
    " unique terms in " +
    elapsed.to_string() +
    "ms",
  )
}

///|
fn report_tfidf_search_stats(
  stats : @tfidf.TfidfPairSearchStats,
  elapsed : UInt64,
) -> Unit {
  println(
    "      Candidate search: " +
    stats.posting_hits.to_string() +
    " posting hits, " +
    stats.candidate_pairs.to_string() +
    " candidate pairs, " +
    stats.cosine_evaluations.to_string() +
    " cosine evals in " +
    elapsed.to_string() +
    "ms",
  )
}

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
  let pairs : Array[FilePair] = []
  for i = 0; i < files.length(); i = i + 1 {
    if files.length() > 10 {
      println(
        "      [" +
        (i + 1).to_string() +
        "/" +
        files.length().to_string() +
        "] " +
        truncate(files[i].0, 40),
      )
    }
    for j = i + 1; j < files.length(); j = j + 1 {
      let (dist, sim) = calc_similarity(files[i].1, files[j].1, strategy)
      if sim >= min_similarity {
        pairs.push({
          file1: files[i].0,
          file2: files[j].0,
          similarity: sim,
          _distance: dist,
        })
      }
    }
  }
  pairs
}

///|
/// Format double with 2 decimal places.
fn format_percent(d : Double) -> String {
  let percent = (d * 100.0).to_int()
  percent.to_string() + "%"
}

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
    header = header + " " + truncate(f.0, 10) + " |"
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
    let mut row = "| " + truncate(f1.0, 10) + " |"
    for f2 in files {
      if f1.0 == f2.0 {
        row = row + " - |"
      } else {
        let key = f1.0 + "|" + f2.0
        match pair_map.get(key) {
          Some(sim) => row = row + " " + format_percent(sim) + " |"
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
      format_percent(pair.similarity) + "  " + pair.file1 + " <-> " + pair.file2,
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
  println("=== Clusters (threshold: " + format_percent(threshold) + ") ===")
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
/// Output as JSON format.
fn output_json(
  files : Array[(String, String)],
  pairs : Array[FilePair],
) -> Unit {
  println("{")
  println("  \"files\": [")
  for i, f in files {
    let comma = if i < files.length() - 1 { "," } else { "" }
    println("    \"" + f.0 + "\"" + comma)
  }
  println("  ],")
  println("  \"pairs\": [")
  for i, pair in pairs {
    let comma = if i < pairs.length() - 1 { "," } else { "" }
    println(
      "    {\"file1\": \"" +
      pair.file1 +
      "\", \"file2\": \"" +
      pair.file2 +
      "\", \"similarity\": " +
      pair.similarity.to_string() +
      "}" +
      comma,
    )
  }
  println("  ]")
  println("}")
}

///|
/// Truncate string to max length.
fn truncate(s : String, max_len : Int) -> String {
  let chars = s.to_array()
  if chars.length() <= max_len {
    return s
  }
  let result : Array[Char] = []
  for i = 0; i < max_len - 2; i = i + 1 {
    result.push(chars[i])
  }
  result.push('.')
  result.push('.')
  String::from_array(result)
}

///|
/// Run the explore command with given arguments.
pub fn run(args : Array[String], start_idx : Int) -> Unit {
  let config = parse_explore_args(args, start_idx)
  if config.show_help {
    show_explore_help()
    return
  }
  if config.target_dirs.length() == 0 {
    println("Error: Directory path required.")
    println("")
    show_explore_help()
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
  // Collect files with progress (respects .gitignore, .indexionignore)
  println("[1/2] Scanning files...")
  let files = collect_files_multi(
    config.target_dirs,
    config.extensions,
    config.includes,
    config.excludes,
  )
  println("      Scan complete: " + files.length().to_string() + " files")
  if files.length() < 2 {
    println("Need at least 2 files to compare.")
    return
  }
  // Calculate total pairs for progress
  let total_pairs = files.length() * (files.length() - 1) / 2
  println(
    "[2/2] Calculating " + total_pairs.to_string() + " similarity pairs...",
  )
  let min_similarity = pair_threshold_for_format(
    config.format,
    config.threshold,
  )
  // Check if using tree-based strategy (function-level comparison)
  let is_tree_strategy = config.strategy == "apted" || config.strategy == "tsed"
  let pairs = if is_tree_strategy {
    calculate_function_pairs(files, config.strategy, min_similarity)
  } else if config.strategy == "tfidf" {
    // Load KGF registry for language-aware tokenization
    let registry = @kgf_features.load_registry()
    println("      Tokenizing with KGF lexer...")
    let tokenize_started = @env.now()
    let (tokenized, kgf_hits) = @kgf_features.tokenize_files_with_kgf(
      files, registry,
    )
    let fallback_count = files.length() - kgf_hits
    println(
      "      Tokenized: " +
      kgf_hits.to_string() +
      " with KGF, " +
      fallback_count.to_string() +
      " fallback in " +
      elapsed_ms(tokenize_started).to_string() +
      "ms",
    )
    println("      Building TF-IDF vectors...")
    let build_started = @env.now()
    let batch = @tfidf.TfidfBatch::from_tokens(tokenized)
    report_tfidf_build_stats(batch.build_stats(), elapsed_ms(build_started))
    let search_started = @env.now()
    let (pairs, search_stats) = calculate_tfidf_pairs(
      batch, files, min_similarity,
    )
    report_tfidf_search_stats(search_stats, elapsed_ms(search_started))
    pairs
  } else {
    calculate_pairs(files, config.strategy, min_similarity)
  }
  // Filter to cross-directory pairs when multiple directories
  let filtered_pairs = if config.target_dirs.length() > 1 {
    let cross = filter_cross_dir_pairs(pairs)
    println(
      "      Cross-directory filter: " +
      cross.length().to_string() +
      " pairs (from " +
      pairs.length().to_string() +
      " total)",
    )
    cross
  } else {
    pairs
  }
  if min_similarity > 0.0 {
    println(
      "      Done (" +
      filtered_pairs.length().to_string() +
      " pairs kept at >= " +
      format_percent(min_similarity) +
      ")",
    )
  } else {
    println(
      "      Done (" +
      filtered_pairs.length().to_string() +
      " pairs calculated)",
    )
  }
  println("")
  // Output based on format
  match config.format {
    "list" => output_list(filtered_pairs)
    "cluster" => output_cluster(files, filtered_pairs, config.threshold)
    "json" => output_json(files, filtered_pairs)
    _ => output_matrix(files, filtered_pairs)
  }
}

///|
/// Calculate function-level similarity pairs using APTED or TSED.
fn calculate_function_pairs(
  files : Array[(String, String)],
  strategy : String,
  min_similarity : Double,
) -> Array[FilePair] {
  let pairs : Array[FilePair] = []
  // Load KGF registry for tokenization
  let registry = match @kgf_features.load_registry() {
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
    match registry.detect_from_path(path) {
      Some(lang) =>
        match registry.get_spec(lang) {
          Some(spec) => {
            // Tokenize
            let lexer = @kgf_lexer.Lexer::new(spec.get_tokens())
            let tokens = lexer.tokenize(content)
            // Extract functions and convert to TreeNodes
            let func_trees = @kgf_features.extract_function_trees(tokens, path)
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
