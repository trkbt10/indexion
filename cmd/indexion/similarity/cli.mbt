///|
/// # indexion sim
///
/// Calculate text similarity and distance between two texts.
///
/// ## Overview
///
/// Computes similarity/distance metrics between two text inputs using
/// various algorithms (TF-IDF cosine similarity, NCD compression distance,
/// or a weighted hybrid).
///
/// ## Usage
///
/// ```bash
/// indexion sim [options] <text1> <text2>
/// ```
///
/// ## Options
///
/// | Option | Description | Default |
/// |--------|-------------|---------|
/// | `--strategy=NAME` | Algorithm: `tfidf`, `ncd`, `hybrid` | hybrid |
/// | `--ncd-weight=FLOAT` | NCD weight in hybrid mode | 0.5 |
/// | `--tfidf-weight=FLOAT` | TF-IDF weight in hybrid mode | 0.5 |
/// | `--format=FORMAT` | Output: `both`, `similarity`, `distance` | both |
///
/// ## Examples
///
/// ```bash
/// # Basic comparison
/// indexion sim "hello world" "hello there"
///
/// # Using TF-IDF only
/// indexion sim --strategy=tfidf "hello world" "hello there"
///
/// # Custom hybrid weights
/// indexion sim --ncd-weight=0.3 --tfidf-weight=0.7 "text1" "text2"
/// ```
///
/// ## Algorithms
///
/// - **tfidf**: TF-IDF cosine similarity (fast, token-based)
/// - **ncd**: Normalized Compression Distance (compression-based)
/// - **hybrid**: Weighted combination of both

///|
/// CLI configuration.
pub struct SimilarityConfig {
  strategy : String
  ncd_weight : Double
  tfidf_weight : Double
  output_format : String
  text1 : String
  text2 : String
  show_help : Bool
}

///|
/// Create default CLI configuration.
pub fn SimilarityConfig::default() -> SimilarityConfig {
  {
    strategy: "hybrid",
    ncd_weight: 0.5,
    tfidf_weight: 0.5,
    output_format: "both",
    text1: "",
    text2: "",
    show_help: false,
  }
}

///|
/// Extract value after '=' in argument.
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
/// Parse a double from string.
fn parse_double(s : String) -> Double {
  let chars = s.to_array()
  if chars.length() == 0 {
    return 0.0
  }
  let mut result = 0.0
  let mut decimal_place = 0
  let mut is_negative = false
  let mut i = 0
  if chars[0] == '-' {
    is_negative = true
    i = 1
  }
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
  if is_negative {
    -result
  } else {
    result
  }
}

///|
/// Parse command line arguments for similarity.
pub fn parse_similarity_args(
  args : Array[String],
  start_idx : Int,
) -> SimilarityConfig {
  let mut config = SimilarityConfig::default()
  let positional : Array[String] = []
  for i = start_idx; i < args.length(); i = i + 1 {
    let arg = args[i]
    if arg == "--help" || arg == "-h" {
      config = { ..config, show_help: true }
    } else if arg.has_prefix("--strategy=") {
      let value = get_arg_value(arg, 11)
      config = { ..config, strategy: value }
    } else if arg.has_prefix("--ncd-weight=") {
      let value = get_arg_value(arg, 13)
      config = { ..config, ncd_weight: parse_double(value) }
    } else if arg.has_prefix("--tfidf-weight=") {
      let value = get_arg_value(arg, 15)
      config = { ..config, tfidf_weight: parse_double(value) }
    } else if arg.has_prefix("--output=") {
      let value = get_arg_value(arg, 9)
      config = { ..config, output_format: value }
    } else if not(arg.has_prefix("-")) {
      positional.push(arg)
    }
  }
  if positional.length() >= 1 {
    config = { ..config, text1: positional[0] }
  }
  if positional.length() >= 2 {
    config = { ..config, text2: positional[1] }
  }
  config
}

///|
/// Show help message for similarity.
pub fn show_similarity_help() -> Unit {
  println("indexion similarity - Calculate text similarity/distance")
  println("")
  println(
    "Calculates similarity/distance between texts using various strategies.",
  )
  println("")
  println("Usage:")
  println("  indexion similarity [options] <text1> <text2>")
  println("")
  println("Strategies:")
  println("  ncd      Normalized Compression Distance (semantic similarity)")
  println("  tfidf    TF-IDF cosine similarity (lexical similarity)")
  println("  hybrid   Weighted combination of NCD and TF-IDF (default)")
  println(
    "  apted    Tree edit distance for structured text (bracket notation)",
  )
  println("  tsed     Tree Structure Edit Distance (bracket notation)")
  println("")
  println("Options:")
  println("  --strategy=NAME        Strategy to use (default: hybrid)")
  println("  --ncd-weight=FLOAT     NCD weight for hybrid (default: 0.5)")
  println("  --tfidf-weight=FLOAT   TF-IDF weight for hybrid (default: 0.5)")
  println(
    "  --output=FORMAT        Output format: distance|similarity|both (default: both)",
  )
  println("  --help                 Show this help message")
  println("")
  println("Examples:")
  println("  indexion similarity \"hello world\" \"hello there\"")
  println("  indexion similarity --strategy=ncd \"foo bar\" \"foo baz\"")
  println(
    "  indexion similarity --strategy=hybrid --ncd-weight=0.7 \"a\" \"b\"",
  )
  println("")
  println("APTED Example (tree edit distance):")
  println("  For APTED, use bracket notation for trees:")
  println("  indexion similarity --strategy=apted \"A(B,C)\" \"A(B,D)\"")
  println("")
  println("TSED Example (tree structure edit distance):")
  println("  indexion similarity --strategy=tsed \"A(B,C)\" \"A(B,D)\"")
}

///|
/// Parse bracket notation into TreeNode.
fn parse_tree(s : String) -> @apted.TreeNode? {
  let chars = s.to_array()
  if chars.length() == 0 {
    return None
  }
  let result = parse_tree_recursive(chars, 0)
  Some(result.0)
}

///|
/// Recursive tree parser.
fn parse_tree_recursive(
  chars : Array[Char],
  start : Int,
) -> (@apted.TreeNode, Int) {
  let label_chars : Array[Char] = []
  let mut i = start
  while i < chars.length() {
    let c = chars[i]
    if c == '(' || c == ',' || c == ')' {
      break
    }
    label_chars.push(c)
    i = i + 1
  }
  let label = String::from_array(label_chars)
  if i < chars.length() && chars[i] == '(' {
    let children : Array[@apted.TreeNode] = []
    i = i + 1
    while i < chars.length() && chars[i] != ')' {
      if chars[i] == ',' {
        i = i + 1
        continue
      }
      let (child, new_i) = parse_tree_recursive(chars, i)
      children.push(child)
      i = new_i
    }
    if i < chars.length() && chars[i] == ')' {
      i = i + 1
    }
    (@apted.TreeNode::node(label, children), i)
  } else {
    (@apted.TreeNode::leaf(label), i)
  }
}

///|
/// Calculate similarity using the specified strategy.
fn calculate_similarity(config : SimilarityConfig) -> (Double, Double)? {
  match config.strategy {
    "ncd" => {
      let strategy = @sim.NCDStrategy::new()
      let dist = strategy.distance(config.text1, config.text2)
      let sim = strategy.similarity(config.text1, config.text2)
      Some((dist, sim))
    }
    "tfidf" => {
      let strategy = @sim.TfidfStrategy::new()
      let dist = strategy.distance(config.text1, config.text2)
      let sim = strategy.similarity(config.text1, config.text2)
      Some((dist, sim))
    }
    "hybrid" => {
      let hybrid_config = @sim.HybridConfig::create(
        config.ncd_weight,
        config.tfidf_weight,
      )
      let strategy = @sim.HybridStrategy::with_config(hybrid_config)
      let dist = strategy.distance(config.text1, config.text2)
      let sim = strategy.similarity(config.text1, config.text2)
      Some((dist, sim))
    }
    "apted" =>
      match (parse_tree(config.text1), parse_tree(config.text2)) {
        (Some(tree1), Some(tree2)) => {
          let cost_config = @apted.CostConfig::default()
          let dist = @apted.normalized_tree_edit_distance(
            tree1, tree2, cost_config,
          )
          let sim = @apted.tree_similarity(tree1, tree2, cost_config)
          Some((dist, sim))
        }
        _ => {
          println("Error: Invalid tree syntax for APTED.")
          println("Use bracket notation: \"Label\" or \"Label(Child1,Child2)\"")
          None
        }
      }
    "tsed" =>
      match (parse_tree(config.text1), parse_tree(config.text2)) {
        (Some(tree1), Some(tree2)) => {
          let tsed_config = @apted.TSEDConfig::default()
          let sim = @apted.calculate_tsed(tree1, tree2, tsed_config)
          let dist = @apted.calculate_tsed_distance(tree1, tree2, tsed_config)
          Some((dist, sim))
        }
        _ => {
          println("Error: Invalid tree syntax for TSED.")
          println("Use bracket notation: \"Label\" or \"Label(Child1,Child2)\"")
          None
        }
      }
    _ => {
      println("Error: Unknown strategy '" + config.strategy + "'")
      println("Available strategies: ncd, tfidf, hybrid, apted, tsed")
      None
    }
  }
}

///|
/// Format double with limited precision.
fn format_double(d : Double) -> String {
  let negative = d < 0.0
  let abs_val = if negative { -d } else { d }
  let int_part = abs_val.to_int()
  let frac_part = ((abs_val - int_part.to_double()) * 1000000.0).to_int()
  let prefix = if negative { "-" } else { "" }
  let frac_str = pad_left(frac_part.to_string(), 6, '0')
  prefix + int_part.to_string() + "." + frac_str
}

///|
/// Pad string to left with character.
fn pad_left(s : String, width : Int, pad_char : Char) -> String {
  let chars = s.to_array()
  if chars.length() >= width {
    return s
  }
  let result : Array[Char] = []
  let pad_count = width - chars.length()
  for i = 0; i < pad_count; i = i + 1 {
    result.push(pad_char)
  }
  for c in chars {
    result.push(c)
  }
  String::from_array(result)
}

///|
/// Run similarity with the given arguments.
/// Args should be the full CLI args including program name.
/// start_idx is the index to start parsing from (after "similarity" subcommand).
pub fn run(args : Array[String], start_idx : Int) -> Unit {
  let config = parse_similarity_args(args, start_idx)
  if config.show_help {
    show_similarity_help()
    return
  }
  // Validate input
  if config.text1.length() == 0 || config.text2.length() == 0 {
    println("Error: Two text arguments required.")
    println("")
    show_similarity_help()
    return
  }
  // Calculate similarity
  match calculate_similarity(config) {
    Some((distance, similarity)) => {
      println("Strategy: " + config.strategy)
      if config.strategy == "hybrid" {
        println(
          "  NCD weight: " +
          format_double(config.ncd_weight) +
          ", TF-IDF weight: " +
          format_double(config.tfidf_weight),
        )
      }
      println("")
      match config.output_format {
        "distance" => println("Distance: " + format_double(distance))
        "similarity" => println("Similarity: " + format_double(similarity))
        _ => {
          println("Distance:   " + format_double(distance))
          println("Similarity: " + format_double(similarity))
        }
      }
    }
    None => ()
  }
}
