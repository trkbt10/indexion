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
  format : String
  text1 : String
  text2 : String
}

///|
/// Create default CLI configuration.
pub fn SimilarityConfig::default() -> SimilarityConfig {
  {
    strategy: "hybrid",
    ncd_weight: 0.5,
    tfidf_weight: 0.5,
    format: "both",
    text1: "",
    text2: "",
  }
}

///|
/// Create SimilarityConfig from argparse Matches.
pub fn SimilarityConfig::from_matches(
  matches : @argparse.Matches,
) -> SimilarityConfig {
  let mut config = SimilarityConfig::default()
  match matches.values.get("strategy") {
    Some(vals) =>
      if vals.length() > 0 {
        config = { ..config, strategy: vals[0] }
      }
    None => ()
  }
  match matches.values.get("ncd-weight") {
    Some(vals) =>
      if vals.length() > 0 {
        config = { ..config, ncd_weight: @common.parse_double(vals[0]) }
      }
    None => ()
  }
  match matches.values.get("tfidf-weight") {
    Some(vals) =>
      if vals.length() > 0 {
        config = { ..config, tfidf_weight: @common.parse_double(vals[0]) }
      }
    None => ()
  }
  match matches.values.get("output") {
    Some(vals) =>
      if vals.length() > 0 {
        config = { ..config, format: vals[0] }
      }
    None => ()
  }
  match matches.values.get("text1") {
    Some(vals) => if vals.length() > 0 { config = { ..config, text1: vals[0] } }
    None => ()
  }
  match matches.values.get("text2") {
    Some(vals) => if vals.length() > 0 { config = { ..config, text2: vals[0] } }
    None => ()
  }
  config
}

///|
/// Define the similarity command for argparse.
pub fn command() -> @argparse.Command {
  @argparse.Command(
    "sim",
    about="Calculate text similarity/distance between two texts",
    options=[
      @argparse.OptionArg(
        "strategy",
        about="Strategy to use: tfidf, ncd, hybrid, apted, tsed",
        default_values=["hybrid"],
      ),
      @argparse.OptionArg(
        "ncd-weight",
        about="NCD weight for hybrid strategy (0.0-1.0)",
        default_values=["0.5"],
      ),
      @argparse.OptionArg(
        "tfidf-weight",
        about="TF-IDF weight for hybrid strategy (0.0-1.0)",
        default_values=["0.5"],
      ),
      @argparse.OptionArg(
        "output",
        about="Output format: distance|similarity|both",
        default_values=["both"],
      ),
    ],
    positionals=[
      @argparse.PositionArg("text1", about="First text to compare"),
      @argparse.PositionArg("text2", about="Second text to compare"),
    ],
  )
}

///|
/// Entry point for the similarity subcommand using argparse Matches.
pub fn run_matches(matches : @argparse.Matches) -> Unit {
  let config = SimilarityConfig::from_matches(matches)
  // Validate input
  if config.text1.length() == 0 || config.text2.length() == 0 {
    println("Error: Two text arguments required.")
    println("")
    println("Usage: indexion sim [options] <text1> <text2>")
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
      match config.format {
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

///|
/// Calculate similarity using the specified strategy.
/// Uses StrategyKind from src/similarity as SoT.
fn calculate_similarity(config : SimilarityConfig) -> (Double, Double)? {
  // Parse strategy using SoT
  let strategy_kind = @sim.StrategyKind::parse_with_weights(
    config.strategy,
    config.ncd_weight,
    config.tfidf_weight,
  )
  match strategy_kind {
    Some(kind) =>
      match kind.calculate(config.text1, config.text2) {
        Some(result) => Some((result.get_distance(), result.get_similarity()))
        None => {
          if kind.is_tree_strategy() {
            println("Error: Invalid tree syntax for " + kind.name() + ".")
            println(
              "Use bracket notation: \"Label\" or \"Label(Child1,Child2)\"",
            )
          }
          None
        }
      }
    None => {
      println("Error: Unknown strategy '" + config.strategy + "'")
      println(
        "Available strategies: " +
        @sim.available_strategies()
        .iter()
        .fold(init="", fn(acc, s) {
          if acc.length() == 0 {
            s
          } else {
            acc + ", " + s
          }
        }),
      )
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
