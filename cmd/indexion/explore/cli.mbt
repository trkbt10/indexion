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
  target_dir : String
  format : String // "matrix", "list", "cluster", "json"
  strategy : String // "hybrid", "ncd", "tfidf"
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
    target_dir: "",
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
      let value = get_arg_value(arg, 9)
      config = { ..config, format: value }
    } else if arg.has_prefix("--strategy=") {
      let value = get_arg_value(arg, 11)
      config = { ..config, strategy: value }
    } else if arg.has_prefix("--threshold=") {
      let value = get_arg_value(arg, 12)
      config = { ..config, threshold: parse_double(value) }
    } else if arg.has_prefix("--ext=") {
      let value = get_arg_value(arg, 6)
      config.extensions.push(value)
    } else if arg.has_prefix("--include=") {
      let value = get_arg_value(arg, 10)
      config.includes.push(value)
    } else if arg.has_prefix("--exclude=") {
      let value = get_arg_value(arg, 10)
      config.excludes.push(value)
    } else if not(arg.has_prefix("-")) && config.target_dir.length() == 0 {
      config = { ..config, target_dir: arg }
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
    "  --strategy=NAME      Similarity strategy: hybrid, ncd, tfidf (default: tfidf)",
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
}

///|
/// Progress counter for file collection.
priv struct CollectProgress {
  mut files_found : Int
  mut dirs_scanned : Int
}

///|
/// Collect files from directory (recursive).
fn collect_files(
  dir : String,
  extensions : Array[String],
  includes : Array[String],
  excludes : Array[String],
) -> Array[(String, String)] {
  let files : Array[(String, String)] = []
  let progress = CollectProgress::{ files_found: 0, dirs_scanned: 0 }
  // Load filter config from directory (respects .gitignore, .indexionignore)
  let filter_config = @filter.FilterConfig::new()
    .with_includes(includes)
    .with_excludes(excludes)
    .with_gitignore_from_dir(dir)
    .with_indexionignore_from_dir(dir)
  collect_files_recursive(dir, extensions, files, "", progress, filter_config)
  files
}

///|
fn should_include_file(
  filter : @filter.FilterConfig,
  filename : String,
) -> Bool {
  filter.should_include(filename, false).is_included()
}

///|
/// Recursive helper for collecting files.
fn collect_files_recursive(
  dir : String,
  extensions : Array[String],
  files : Array[(String, String)],
  prefix : String,
  progress : CollectProgress,
  filter_config : @filter.FilterConfig,
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
    progress.dirs_scanned = progress.dirs_scanned + 1
    // Show progress every 10 directories
    if progress.dirs_scanned % 10 == 0 {
      println(
        "      Scanning: " +
        progress.dirs_scanned.to_string() +
        " dirs, " +
        progress.files_found.to_string() +
        " files found",
      )
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
        // Use filter config to determine if directory should be skipped
        if filter_config.should_skip_dir(entry) {
          continue
        }
        // Recurse into subdirectory
        collect_files_recursive(
          path, extensions, files, display_name, progress, filter_config,
        )
      } else if @fs.is_file(path) {
        // Check extension filter
        let ext_ok = if extensions.length() == 0 {
          true
        } else {
          let mut matched = false
          for ext in extensions {
            if entry.has_suffix(ext) {
              matched = true
              break
            }
          }
          matched
        }
        // Check filter config
        if ext_ok && should_include_file(filter_config, display_name) {
          let content = @fs.read_file_to_string(path)
          files.push((display_name, content))
          progress.files_found = progress.files_found + 1
        }
      }
    }
  } catch {
    _ => ()
  }
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
      let s = @sim.NCDStrategy::new()
      (s.distance(text1, text2), s.similarity(text1, text2))
    }
    "tfidf" => {
      let s = @sim.TfidfStrategy::new()
      (s.distance(text1, text2), s.similarity(text1, text2))
    }
    _ => {
      let s = @sim.HybridStrategy::new()
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
  if config.target_dir.length() == 0 {
    println("Error: Directory path required.")
    println("")
    show_explore_help()
    return
  }
  println("=== indexion explore ===")
  println("Directory: " + config.target_dir)
  println("Strategy: " + config.strategy)
  println("")
  // Collect files with progress (respects .gitignore, .indexionignore)
  println("[1/2] Scanning files...")
  let files = collect_files(
    config.target_dir,
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
  let pairs = if config.strategy == "tfidf" {
    // Load KGF registry for language-aware tokenization
    let registry = @kgf_features.load_registry()
    println("      Tokenizing with KGF lexer...")
    let tokenize_started = @env.now()
    let (tokenized, kgf_hits) = @kgf_features.tokenize_files_with_kgf(
      files,
      registry,
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
  if min_similarity > 0.0 {
    println(
      "      Done (" +
      pairs.length().to_string() +
      " pairs kept at >= " +
      format_percent(min_similarity) +
      ")",
    )
  } else {
    println("      Done (" + pairs.length().to_string() + " pairs calculated)")
  }
  println("")
  // Output based on format
  match config.format {
    "list" => output_list(pairs)
    "cluster" => output_cluster(files, pairs, config.threshold)
    "json" => output_json(files, pairs)
    _ => output_matrix(files, pairs)
  }
}
