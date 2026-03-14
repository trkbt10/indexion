///|
/// # indexion segment
///
/// Split text file into contextual segments.
///
/// ## Usage
///
/// ```bash
/// indexion segment [options] <input-file> <output-dir>
/// ```
///
/// ## Options
///
/// | Option | Description | Default |
/// |--------|-------------|---------|
/// | `--strategy=NAME` | Algorithm: `window`, `tfidf`, `punctuation` | window |
/// | `--min-size=INT` | Minimum segment size in chars | 100 |
/// | `--max-size=INT` | Maximum segment size in chars | 2000 |
/// | `--target-size=INT` | Target segment size in chars | 500 |
/// | `--threshold=FLOAT` | Divergence threshold | 0.42 |
/// | `--adaptive` | Use adaptive threshold mode | false |
/// | `--hybrid` | Use NCD+TF-IDF hybrid mode | false |
/// | `--ncd-weight=FLOAT` | NCD weight in hybrid mode | 0.5 |
/// | `--tfidf-weight=FLOAT` | TF-IDF weight in hybrid mode | 0.5 |
/// | `--prefix=NAME` | Output file prefix | segment |

///|
/// CLI configuration.
pub struct SegmentConfig {
  input_file : String
  output_dir : String
  strategy : String
  min_size : Int
  max_size : Int
  target_size : Int
  threshold : Double
  window_size : Int
  adaptive : Bool
  hybrid : Bool
  ncd_weight : Double
  tfidf_weight : Double
  prefix : String
  show_help : Bool
}

///|
/// Create default configuration.
pub fn SegmentConfig::default() -> SegmentConfig {
  {
    input_file: "",
    output_dir: "",
    strategy: "window",
    min_size: 100,
    max_size: 2000,
    target_size: 500,
    threshold: 0.42,
    window_size: 3,
    adaptive: true,
    hybrid: false,
    ncd_weight: 0.5,
    tfidf_weight: 0.5,
    prefix: "segment",
    show_help: false,
  }
}

// get_arg_value, parse_double: use @common (SoT)
// parse_int: use @common (SoT)

///|
/// Parse command line arguments into SegmentConfig.
pub fn parse_args(args : Array[String], start_idx : Int) -> SegmentConfig {
  let mut config = SegmentConfig::default()
  let positional : Array[String] = []
  for i = start_idx; i < args.length(); i = i + 1 {
    let arg = args[i]
    if arg == "--help" || arg == "-h" {
      config = { ..config, show_help: true }
    } else if arg == "--adaptive" {
      config = { ..config, adaptive: true }
    } else if arg == "--hybrid" {
      config = { ..config, hybrid: true, adaptive: true }
    } else if arg.has_prefix("--ncd-weight=") {
      let value = @common.get_arg_value(arg, 13)
      config = { ..config, ncd_weight: @common.parse_double(value) }
    } else if arg.has_prefix("--tfidf-weight=") {
      let value = @common.get_arg_value(arg, 15)
      config = { ..config, tfidf_weight: @common.parse_double(value) }
    } else if arg.has_prefix("--strategy=") {
      let value = @common.get_arg_value(arg, 11)
      config = { ..config, strategy: value }
    } else if arg.has_prefix("--min-size=") {
      let value = @common.get_arg_value(arg, 11)
      config = { ..config, min_size: @common.parse_int(value) }
    } else if arg.has_prefix("--max-size=") {
      let value = @common.get_arg_value(arg, 11)
      config = { ..config, max_size: @common.parse_int(value) }
    } else if arg.has_prefix("--target-size=") {
      let value = @common.get_arg_value(arg, 14)
      config = { ..config, target_size: @common.parse_int(value) }
    } else if arg.has_prefix("--threshold=") {
      let value = @common.get_arg_value(arg, 12)
      config = { ..config, threshold: @common.parse_double(value) }
    } else if arg.has_prefix("--window-size=") {
      let value = @common.get_arg_value(arg, 14)
      config = { ..config, window_size: @common.parse_int(value) }
    } else if arg.has_prefix("--prefix=") {
      let value = @common.get_arg_value(arg, 9)
      config = { ..config, prefix: value }
    } else if not(arg.has_prefix("-")) {
      positional.push(arg)
    }
  }
  if positional.length() >= 1 {
    config = { ..config, input_file: positional[0] }
  }
  if positional.length() >= 2 {
    config = { ..config, output_dir: positional[1] }
  }
  config
}

///|
/// Display help message for segment command.
pub fn show_help() -> Unit {
  println("indexion segment - Split text into contextual segments")
  println("")
  println("Usage:")
  println("  indexion segment [options] <input-file> <output-dir>")
  println("")
  println("Options:")
  println(
    "  --strategy=NAME      Strategy: window, tfidf, punctuation (default: window)",
  )
  println("  --min-size=INT       Minimum segment size in chars (default: 100)")
  println(
    "  --max-size=INT       Maximum segment size in chars (default: 2000)",
  )
  println("  --target-size=INT    Target segment size in chars (default: 500)")
  println("  --threshold=FLOAT    Divergence threshold (default: 0.42)")
  println("  --window-size=INT    Window size for divergence (default: 3)")
  println("  --adaptive           Use adaptive threshold mode (default)")
  println("  --hybrid             Use NCD+TF-IDF hybrid mode (best quality)")
  println("  --ncd-weight=FLOAT   NCD weight in hybrid mode (default: 0.5)")
  println("  --tfidf-weight=FLOAT TF-IDF weight in hybrid mode (default: 0.5)")
  println("  --prefix=NAME        Output file prefix (default: segment)")
  println("  --help               Show this help message")
  println("")
  println("Examples:")
  println("  indexion segment kokoro.txt ./output/")
  println("  indexion segment --adaptive --max-size=3000 novel.txt ./chapters/")
  println("  indexion segment --hybrid novel.txt ./chapters/")
  println("  indexion segment --prefix=chapter novel.txt ./output/")
}

///|
/// Pad number with leading zeros.
fn pad_number(n : Int, width : Int) -> String {
  let s = n.to_string()
  let chars = s.to_array()
  if chars.length() >= width {
    return s
  }
  let result : Array[Char] = []
  let pad_count = width - chars.length()
  for i = 0; i < pad_count; i = i + 1 {
    result.push('0')
  }
  for c in chars {
    result.push(c)
  }
  String::from_array(result)
}

///|
/// Extract substring from text.
fn substring(text : String, start : Int, end : Int) -> String {
  let chars = text.to_array()
  let result : Array[Char] = []
  let actual_end = if end > chars.length() { chars.length() } else { end }
  for i = start; i < actual_end; i = i + 1 {
    result.push(chars[i])
  }
  String::from_array(result)
}

///|
/// Run the segment command with given arguments.
pub fn run(args : Array[String], start_idx : Int) -> Unit {
  let config = parse_args(args, start_idx)

  if config.show_help {
    show_help()
    return
  }

  if config.input_file.length() == 0 {
    println("Error: Input file required.")
    println("")
    show_help()
    return
  }

  if config.output_dir.length() == 0 {
    println("Error: Output directory required.")
    println("")
    show_help()
    return
  }

  // Read input file
  let text = @fs.read_file_to_string(config.input_file) catch {
    e => {
      println("Error reading file: " + e.to_string())
      return
    }
  }

  println("=== indexion segment ===")
  println("Input: " + config.input_file)
  println("Output: " + config.output_dir)
  let mode_str = if config.hybrid {
    " (hybrid NCD+TF-IDF)"
  } else if config.adaptive {
    " (adaptive)"
  } else {
    ""
  }
  println("Strategy: " + config.strategy + mode_str)
  println("Text length: " + text.length().to_string() + " chars")
  println("")

  // Segment text
  let segments : Array[@types.SegmentPoint] = if config.hybrid {
    // Use NCD+TF-IDF hybrid adaptive mode
    let hybrid_config = @window.HybridAdaptiveConfig::new(
      0.2, // percentile
      0.13, // minimum_threshold
      config.target_size,
      config.min_size,
      config.max_size,
      config.window_size,
      config.ncd_weight,
      config.tfidf_weight,
    )
    @window.segment_hybrid_adaptive(text, hybrid_config)
  } else if config.adaptive {
    // Use TF-IDF adaptive mode
    let adaptive_config = @window.AdaptiveConfig::new(
      0.2, // percentile
      0.13, // minimum_threshold
      config.target_size,
      config.min_size,
      config.max_size,
      config.window_size,
    )
    @window.segment_adaptive(text, adaptive_config)
  } else {
    let window_config = @window.SegmentConfig::new(
      config.target_size,
      config.min_size,
      config.max_size,
      config.threshold,
      config.window_size,
    )
    @seg.segment_by_divergence(text, window_config)
  }

  println("Found " + segments.length().to_string() + " segments")
  println("")

  // Ensure output directory exists by writing test file
  let clean_output_dir = if config.output_dir.has_suffix("/") {
    let chars = config.output_dir.to_array()
    let result : Array[Char] = []
    for i = 0; i < chars.length() - 1; i = i + 1 {
      result.push(chars[i])
    }
    String::from_array(result)
  } else {
    config.output_dir
  }

  // Write segments to files
  let width = if segments.length() >= 1000 {
    4
  } else if segments.length() >= 100 {
    3
  } else {
    2
  }

  for i, seg in segments {
    let segment_text = substring(text, seg.get_start(), seg.get_end())
    let filename = clean_output_dir +
      "/" +
      config.prefix +
      "_" +
      pad_number(i + 1, width) +
      ".txt"

    try {
      @fs.write_string_to_file(filename, segment_text)
      println(
        "  [" +
        pad_number(i + 1, width) +
        "] " +
        filename +
        " (" +
        segment_text.length().to_string() +
        " chars)",
      )
    } catch {
      e => println("Error writing " + filename + ": " + e.to_string())
    }
  }

  println("")
  println(
    "Done. " +
    segments.length().to_string() +
    " segments written to " +
    clean_output_dir,
  )
}
