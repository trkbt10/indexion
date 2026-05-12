///|
pub(all) struct DriftConfig {
  file_a : String
  file_b : String
  /// Output target. Empty or "-" prints to stdout.
  output : String
  /// Output format: "text", "md", or "json".
  format : String
  /// Max gap terms reported per direction. 0 = unlimited.
  top : Int
  /// Cosine-distance threshold. When set, the command exits non-zero if
  /// the measured distance exceeds this value.
  vocab_threshold : Double?
  /// KGF specs directory (None = auto-detect).
  specs_dir : String?
}

///|
pub fn DriftConfig::default() -> DriftConfig {
  {
    file_a: "",
    file_b: "",
    output: "",
    format: "text",
    top: 10,
    vocab_threshold: None,
    specs_dir: None,
  }
}

///|
pub fn DriftConfig::from_matches(matches : @argparse.Matches) -> DriftConfig {
  let mut config = DriftConfig::default()
  config = { ..config, file_a: @common.get_option(matches, "file_a", "") }
  config = { ..config, file_b: @common.get_option(matches, "file_b", "") }
  config = { ..config, output: @common.get_option(matches, "output", "") }
  config = { ..config, format: @common.get_option(matches, "format", "text") }
  let top_str = @common.get_option(matches, "top", "10")
  config = { ..config, top: @common.parse_int(top_str) }
  match matches.values.get("vocab-threshold") {
    Some(vals) =>
      if vals.length() > 0 {
        config = {
          ..config,
          vocab_threshold: Some(@common.parse_double(vals[0])),
        }
      }
    None => ()
  }
  match matches.values.get("specs-dir") {
    Some(vals) =>
      if vals.length() > 0 {
        config = { ..config, specs_dir: Some(vals[0]) }
      }
    None => ()
  }
  config
}

///|
pub fn command() -> @argparse.Command {
  @argparse.Command(
    "drift",
    about="Detect translation / documentation drift between two files",
    options=[
      @argparse.OptionArg("output", short='o', about=@help.output),
      @argparse.OptionArg(
        "format",
        about="Output format: text, md, json",
        default_values=["text"],
      ),
      @argparse.OptionArg(
        "top",
        about="Max gap terms reported per direction (0 = unlimited)",
        default_values=["10"],
      ),
      @argparse.OptionArg(
        "vocab-threshold",
        about="Cosine-distance threshold; exit non-zero if exceeded",
      ),
      @argparse.OptionArg(
        "specs-dir",
        about="KGF specs directory (default: auto-detect)",
      ),
    ],
    positionals=[
      @argparse.PositionArg("file_a", about="First file path"),
      @argparse.PositionArg("file_b", about="Second file path"),
    ],
  )
}
