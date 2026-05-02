/// # indexion story reconcile
///
/// Reconcile plot acts against prose chapters: detect drift, recommend
/// concrete actions (expand, consolidate, prune, restructure), and surface
/// the term-level evidence behind each recommendation.

///|
pub struct ReconcileCliConfig {
  root : String
  format : String
  output : String
  similarity_floor : Double
  runner_up_margin : Double
  max_terms : Int
}

///|
pub fn ReconcileCliConfig::from_matches(
  matches : @argparse.Matches,
) -> ReconcileCliConfig {
  let get_str = fn(key : String, default_ : String) -> String {
    match matches.values.get(key) {
      Some(arr) => if arr.length() > 0 { arr[0] } else { default_ }
      None => default_
    }
  }
  let get_int = fn(key : String, default_ : Int) -> Int {
    match matches.values.get(key) {
      Some(arr) =>
        if arr.length() > 0 { @common.parse_int(arr[0]) } else { default_ }
      None => default_
    }
  }
  let get_double = fn(key : String, default_ : Double) -> Double {
    match matches.values.get(key) {
      Some(arr) =>
        if arr.length() > 0 { @common.parse_double(arr[0]) } else { default_ }
      None => default_
    }
  }
  {
    root: get_str("root", ""),
    format: get_str("format", "text"),
    output: get_str("output", ""),
    similarity_floor: get_double("similarity-floor", 0.15),
    runner_up_margin: get_double("runner-up-margin", 0.05),
    max_terms: get_int("max-terms", 8),
  }
}

///|
pub fn command() -> @argparse.Command {
  @argparse.Command::new(
    "reconcile",
    about="Reconcile plot acts against prose chapters; recommend writer actions",
    options=[
      @argparse.OptionArg::new(
        "format",
        about="Output format: text | json",
        default_values=["text"],
      ),
      @argparse.OptionArg::new(
        "output",
        about="Output file path (- or empty = stdout)",
        default_values=[""],
      ),
      @argparse.OptionArg::new(
        "similarity-floor",
        about="Minimum BM25 similarity for a chapter to count as a match",
        default_values=["0.15"],
      ),
      @argparse.OptionArg::new(
        "runner-up-margin",
        about="Margin under best similarity within which runner-ups are reported",
        default_values=["0.05"],
      ),
      @argparse.OptionArg::new(
        "max-terms",
        about="Maximum missing/extra terms reported per candidate",
        default_values=["8"],
      ),
    ],
    positionals=[
      @argparse.PositionArg::new(
        "root",
        about="Story root directory containing sources/ and prose/",
        num_args=@argparse.ValueRange::single(),
      ),
    ],
  )
}

///|
pub fn run_matches(matches : @argparse.Matches) -> Unit {
  let config = ReconcileCliConfig::from_matches(matches)
  if config.root.length() == 0 {
    println("Error: story root directory is required.")
    println("")
    println(command().render_help())
    return
  }
  let dataset = match @story.load_story_dataset(config.root) {
    Some(ds) => ds
    None => {
      println(
        "Error: no sources/ or prose/ found under " + config.root + ".",
      )
      return
    }
  }
  let reconcile_config = @story_reconcile.ReconcileConfig::new(
    config.root,
    similarity_floor=config.similarity_floor,
    runner_up_margin=config.runner_up_margin,
    max_terms_per_candidate=config.max_terms,
  )
  let report = @story_reconcile.reconcile(dataset, reconcile_config)
  let format = @story_reconcile.ReconcileFormat::parse(config.format)
  let rendered = @story_reconcile.render_report(report, format)
  @common.write_output(config.output, rendered, label="Reconcile report")
}
