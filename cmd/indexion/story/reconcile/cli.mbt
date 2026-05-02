/// # indexion story reconcile
///
/// Reconcile spec-extracted acts against impl documents: detect drift,
/// recommend writer actions (expand, consolidate, prune, restructure),
/// and surface the term-level evidence behind each recommendation.

///|
pub struct ReconcileCliConfig {
  spec : Array[String]
  impl_ : Array[String]
  format : String
  output : String
  similarity_floor : Double
  runner_up_margin : Double
  max_terms : Int
  registry_root : String
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
  let get_list = fn(key : String) -> Array[String] {
    match matches.values.get(key) {
      Some(arr) => arr
      None => []
    }
  }
  {
    spec: get_list("spec"),
    impl_: get_list("impl"),
    format: get_str("format", "text"),
    output: get_str("output", ""),
    similarity_floor: get_double("similarity-floor", 0.15),
    runner_up_margin: get_double("runner-up-margin", 0.05),
    max_terms: get_int("max-terms", 8),
    registry_root: get_str("registry-root", ""),
  }
}

///|
pub fn command() -> @argparse.Command {
  @argparse.Command::new(
    "reconcile",
    about="Reconcile acts extracted from --spec docs against --impl docs",
    options=[
      @argparse.OptionArg(
        "spec",
        action=Append,
        about="Glob pattern for spec-side documents (repeatable)",
      ),
      @argparse.OptionArg(
        "impl",
        action=Append,
        about="Glob pattern for impl-side documents (repeatable)",
      ),
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
        about="Minimum BM25 similarity for an impl doc to count as a match",
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
      @argparse.OptionArg::new(
        "registry-root",
        about="Root for kgfs/story spec discovery (default: CWD)",
        default_values=[""],
      ),
    ],
  )
}

///|
pub fn run_matches(matches : @argparse.Matches) -> Unit {
  let config = ReconcileCliConfig::from_matches(matches)
  if config.spec.is_empty() || config.impl_.is_empty() {
    println("Error: at least one --spec and one --impl pattern is required.")
    println("")
    println(command().render_help())
    return
  }
  let groups = @story.load_groups(config.spec, config.impl_)
  if groups.get_spec().is_empty() {
    println("Error: no spec documents matched the given --spec patterns.")
    return
  }
  if groups.get_impl().is_empty() {
    println("Error: no impl documents matched the given --impl patterns.")
    return
  }
  let reconcile_config = @story_reconcile.ReconcileConfig::new(
    similarity_floor=config.similarity_floor,
    runner_up_margin=config.runner_up_margin,
    max_terms_per_candidate=config.max_terms,
    registry_root=config.registry_root,
  )
  let report = @story_reconcile.reconcile(groups, reconcile_config)
  let format = @story_reconcile.ReconcileFormat::parse(config.format)
  let rendered = @story_reconcile.render_report(report, format)
  @common.write_output(config.output, rendered, label="Reconcile report")
}
