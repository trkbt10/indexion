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
/// | `--threshold=FLOAT` | Clustering threshold (for cluster format) | 0.5 |
/// | `--ext=EXT` | File extension filter (repeatable) | all |
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
    "  --threshold=FLOAT    Similarity threshold for clustering (default: 0.5)",
  )
  println("  --ext=EXT            File extension to include (can be repeated)")
  println("  --help               Show this help message")
  println("")
  println("Examples:")
  println("  indexion explore kgfs/")
  println("  indexion explore --format=list --strategy=tfidf src/")
  println("  indexion explore --format=cluster --threshold=0.7 kgfs/")
  println("  indexion explore --ext=.mbt --ext=.kgf .")
}

///|
/// Collect files from directory (recursive).
fn collect_files(
  dir : String,
  extensions : Array[String],
) -> Array[(String, String)] {
  let files : Array[(String, String)] = []
  collect_files_recursive(dir, extensions, files, "")
  files
}

///|
/// Recursive helper for collecting files.
fn collect_files_recursive(
  dir : String,
  extensions : Array[String],
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
      let path = clean_dir + "/" + entry
      let display_name = if prefix.length() > 0 {
        prefix + "/" + entry
      } else {
        entry
      }
      if @fs.is_dir(path) {
        // Recurse into subdirectory
        collect_files_recursive(path, extensions, files, display_name)
      } else if @fs.is_file(path) {
        let should_include = if extensions.length() == 0 {
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
        if should_include {
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
  // Sort by similarity (descending) - simple bubble sort
  for i = 0; i < pairs.length(); i = i + 1 {
    for j = i + 1; j < pairs.length(); j = j + 1 {
      if pairs[j].similarity > pairs[i].similarity {
        let tmp = pairs[i]
        pairs[i] = pairs[j]
        pairs[j] = tmp
      }
    }
  }
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
  // Collect files
  let files = collect_files(config.target_dir, config.extensions)
  println("Found " + files.length().to_string() + " files")
  println("")
  if files.length() < 2 {
    println("Need at least 2 files to compare.")
    return
  }
  // Calculate all pairs
  let pairs : Array[FilePair] = []
  for i = 0; i < files.length(); i = i + 1 {
    for j = i + 1; j < files.length(); j = j + 1 {
      let (dist, sim) = calc_similarity(files[i].1, files[j].1, config.strategy)
      pairs.push({
        file1: files[i].0,
        file2: files[j].0,
        similarity: sim,
        _distance: dist,
      })
    }
  }
  // Output based on format
  match config.format {
    "list" => output_list(pairs)
    "cluster" => output_cluster(files, pairs, config.threshold)
    "json" => output_json(files, pairs)
    _ => output_matrix(files, pairs)
  }
}
