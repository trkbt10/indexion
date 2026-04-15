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
}

///|
/// Create configuration from argparse Matches.
pub fn SegmentConfig::from_matches(
  matches : @argparse.Matches,
) -> SegmentConfig {
  let get_str = fn(key : String, default_ : String) -> String {
    match matches.values.get(key) {
      Some(arr) => if arr.length() > 0 { arr[0] } else { default_ }
      None => default_
    }
  }
  let get_int = fn(key : String, default_ : Int) -> Int {
    match matches.values.get(key) {
      Some(arr) =>
        if arr.length() > 0 {
          @common.parse_int(arr[0])
        } else {
          default_
        }
      None => default_
    }
  }
  let get_double = fn(key : String, default_ : Double) -> Double {
    match matches.values.get(key) {
      Some(arr) =>
        if arr.length() > 0 {
          @common.parse_double(arr[0])
        } else {
          default_
        }
      None => default_
    }
  }
  let get_flag = fn(key : String, default_ : Bool) -> Bool {
    match matches.flags.get(key) {
      Some(v) => v
      None => default_
    }
  }
  let hybrid = get_flag("hybrid", false)
  let adaptive = if hybrid { true } else { get_flag("adaptive", true) }
  {
    input_file: get_str("input-file", ""),
    output_dir: get_str("output-dir", ""),
    strategy: get_str("strategy", "window"),
    min_size: get_int("min-size", 100),
    max_size: get_int("max-size", 2000),
    target_size: get_int("target-size", 500),
    threshold: get_double("threshold", 0.42),
    window_size: get_int("window-size", 3),
    adaptive,
    hybrid,
    ncd_weight: get_double("ncd-weight", 0.5),
    tfidf_weight: get_double("tfidf-weight", 0.5),
    prefix: get_str("prefix", "segment"),
  }
}

///|
/// Define the segment command for argparse.
pub fn command() -> @argparse.Command {
  @argparse.Command::new(
    "segment",
    about="Split text into contextual segments",
    flags=[
      @argparse.FlagArg::new(
        "adaptive",
        about="Use adaptive threshold mode (default)",
      ),
      @argparse.FlagArg::new(
        "hybrid",
        about="Use NCD+TF-IDF hybrid mode (best quality)",
      ),
    ],
    options=[
      @argparse.OptionArg::new(
        "strategy",
        about="Strategy: window, tfidf, punctuation",
        default_values=["window"],
      ),
      @argparse.OptionArg::new(
        "min-size",
        about="Minimum segment size in chars",
        default_values=["100"],
      ),
      @argparse.OptionArg::new(
        "max-size",
        about="Maximum segment size in chars",
        default_values=["2000"],
      ),
      @argparse.OptionArg::new(
        "target-size",
        about="Target segment size in chars",
        default_values=["500"],
      ),
      @argparse.OptionArg::new("threshold", about="Divergence threshold", default_values=[
        "0.42",
      ]),
      @argparse.OptionArg::new(
        "window-size",
        about="Window size for divergence",
        default_values=["3"],
      ),
      @argparse.OptionArg::new(
        "ncd-weight",
        about="NCD weight in hybrid mode",
        default_values=["0.5"],
      ),
      @argparse.OptionArg::new(
        "tfidf-weight",
        about="TF-IDF weight in hybrid mode",
        default_values=["0.5"],
      ),
      @argparse.OptionArg::new("prefix", about="Output file prefix", default_values=[
        "segment",
      ]),
    ],
    positionals=[
      @argparse.PositionArg::new(
        "input-file",
        about="Input text file",
        num_args=@argparse.ValueRange::single(),
      ),
      @argparse.PositionArg::new(
        "output-dir",
        about="Output directory",
        num_args=@argparse.ValueRange::single(),
      ),
    ],
  )
}

///|
/// Run the segment command from argparse Matches.
pub fn run_matches(matches : @argparse.Matches) -> Unit {
  let config = SegmentConfig::from_matches(matches)

  if config.input_file.length() == 0 {
    println("Error: Input file required.")
    return
  }

  if config.output_dir.length() == 0 {
    println("Error: Output directory required.")
    return
  }

  run_with_config(config)
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

// use @common (SoT) — substring

///|
/// Run the segment command with a parsed config.
fn run_with_config(config : SegmentConfig) -> Unit {
  // Read input file
  let text = @fs.read_file_to_string(config.input_file) catch {
    e => {
      println("Error reading file: " + @debug.to_string(e))
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
    let segment_text = @common.substring(text, seg.get_start(), seg.get_end())
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
      e => println("Error writing " + filename + ": " + @debug.to_string(e))
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
