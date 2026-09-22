///|
/// Define the perf command with kgf subcommand for argparse.
pub fn command() -> @argparse.Command {
  @argparse.Command(
    "perf",
    about="Performance benchmark commands",
    subcommand_required=true,
    subcommands=[
      @argparse.Command("kgf", about="KGF parse benchmark", options=[
        @argparse.OptionArg("spec", about="KGF spec file", default_values=[
          "kgfs/moonbit.kgf",
        ]),
        @argparse.OptionArg("input", about="Input source file", default_values=[
          "src/docgen/build/pipeline.mbt",
        ]),
        @argparse.OptionArg("iterations", about="Iterations per benchmark", default_values=[
          "20",
        ]),
        @argparse.OptionArg("warmup", about="Warmup iterations", default_values=[
          "3",
        ]),
      ]),
    ],
  )
}

///|
/// Dispatch from argparse Matches.
pub fn dispatch(matches : @argparse.Matches) -> Unit {
  match matches.subcommand {
    Some(("kgf", sub_matches)) => run_kgf_matches(sub_matches)
    _ => println("Unknown perf subcommand. Use --help for usage.")
  }
}

///|
/// Run KGF parse benchmark from argparse Matches.
fn run_kgf_matches(matches : @argparse.Matches) -> Unit {
  let get_str = fn(key : String, default_ : String) -> String {
    match matches.values.get(key) {
      Some(arr) => if arr.length() > 0 { arr[0] } else { default_ }
      None => default_
    }
  }
  let spec_path = get_str("spec", "kgfs/moonbit.kgf")
  let input_path = get_str("input", "src/docgen/build/pipeline.mbt")
  let mut iterations = match matches.values.get("iterations") {
    Some(arr) => if arr.length() > 0 { @common.parse_int(arr[0]) } else { 20 }
    None => 20
  }
  let mut warmup = match matches.values.get("warmup") {
    Some(arr) => if arr.length() > 0 { @common.parse_int(arr[0]) } else { 3 }
    None => 3
  }
  if iterations <= 0 {
    iterations = 20
  }
  if warmup < 0 {
    warmup = 3
  }

  let spec_text = @fs.read_file_to_string(spec_path) catch {
    _ => {
      println("Error: failed to read spec file: " + spec_path)
      return
    }
  }
  let source_text = @fs.read_file_to_string(input_path) catch {
    _ => {
      println("Error: failed to read input file: " + input_path)
      return
    }
  }

  let spec = match @kgf_parser.parse_kgf(spec_text) {
    Some(s) => s
    None => {
      println("Error: failed to parse spec file: " + spec_path)
      return
    }
  }
  let peg = @kgf_peg.build_peg(spec) catch {
    _ => {
      println("Error: failed to build PEG from spec")
      return
    }
  }

  let lexer = @kgf_lexer.Lexer::for_spec(spec)
  let start_rule = spec.get_start_rule()
  let active_rules = @kgf_peg.collect_active_rules(spec)
  let tokens = lexer.tokenize(source_text)
  let file_exists = fn(path : String) -> Bool {
    @fs.is_file(path) catch {
      _ => false
    }
  }
  let language = spec.get_language()

  println("KGF benchmark")
  println("  spec      : " + spec_path)
  println("  input     : " + input_path)
  println("  language  : " + language)
  println("  tokens    : " + tokens.length().to_string())
  println("  iterations: " + iterations.to_string())
  println("  warmup    : " + warmup.to_string())
  println("")

  for _ in 0..<warmup {
    let _ = lexer.tokenize(source_text)
    let _ = tokenize_with_rebuild(spec, source_text)
    let _ = @kgf_peg.run_parse_filtered(
      peg, spec, start_rule, tokens, active_rules,
    )
    let _ = run_full_pipeline_reuse_lexer(
      spec, peg, lexer, source_text, input_path, file_exists, start_rule, active_rules,
    )
    let _ = run_full_pipeline_rebuild_lexer(
      spec, peg, source_text, input_path, file_exists, start_rule, active_rules,
    )
  }

  // Run benchmarks
  let benchmarks : Array[(String, () -> Unit)] = [
    ("tokenize_reuse_lexer", fn() { let _ = lexer.tokenize(source_text) }),
    (
      "tokenize_rebuild_lexer",
      fn() { let _ = tokenize_with_rebuild(spec, source_text) },
    ),
    (
      "parse_only",
      fn() {
        let _ = @kgf_peg.run_parse_filtered(
          peg, spec, start_rule, tokens, active_rules,
        )
      },
    ),
    (
      "full_pipeline_reuse_lexer",
      fn() {
        let _ = run_full_pipeline_reuse_lexer(
          spec, peg, lexer, source_text, input_path, file_exists, start_rule, active_rules,
        )
      },
    ),
    (
      "full_pipeline_rebuild_lexer",
      fn() {
        let _ = run_full_pipeline_rebuild_lexer(
          spec, peg, source_text, input_path, file_exists, start_rule, active_rules,
        )
      },
    ),
  ]
  for bench in benchmarks {
    let (name, task) = bench
    run_bench(name, task, iterations)
  }
}

///|
/// Run a single benchmark: execute task N times and report timing.
fn run_bench(name : String, task : () -> Unit, iterations : Int) -> Unit {
  let start = @env.now()
  for _ in 0..<iterations {
    task()
  }
  let elapsed = @common.elapsed_ms(start)
  let avg = elapsed.to_double() / iterations.to_double()
  println(
    name +
    ": " +
    elapsed.to_string() +
    "ms total, " +
    avg.to_string() +
    "ms/iter (" +
    iterations.to_string() +
    " iterations)",
  )
}

///|
/// Runs tokenize + parse + semantics once.
fn run_full_pipeline_rebuild_lexer(
  spec : @kgf_types.KGFSpec,
  peg : @kgf_peg.PEG,
  source_text : String,
  input_path : String,
  file_exists : (String) -> Bool,
  start_rule : String,
  active_rules : @hashset.HashSet[String],
) -> Int {
  let lexer = @kgf_lexer.Lexer::for_spec(spec)
  run_full_pipeline_reuse_lexer(
    spec, peg, lexer, source_text, input_path, file_exists, start_rule, active_rules,
  )
}

///|
/// Runs tokenize + parse + semantics once with a prebuilt lexer.
fn run_full_pipeline_reuse_lexer(
  spec : @kgf_types.KGFSpec,
  peg : @kgf_peg.PEG,
  lexer : @kgf_lexer.Lexer,
  source_text : String,
  input_path : String,
  file_exists : (String) -> Bool,
  start_rule : String,
  active_rules : @hashset.HashSet[String],
) -> Int {
  let graph = @graph.CodeGraph::new()
  let tokens = lexer.tokenize(source_text)
  match
    @kgf_peg.run_parse_filtered(peg, spec, start_rule, tokens, active_rules) {
    Some(eval_result) => {
      let ctx = @kgf_semantics.SemEvalCtx::new(
        spec,
        graph,
        input_path,
        "",
        spec.get_language(),
        file_exists,
      )
      for event in eval_result.get_events() {
        @kgf_semantics.eval_rule_semantics(event.0, event.1, ctx)
      }
      graph.get_edges().length()
    }
    None => 0
  }
}

///|
/// Tokenizes once while rebuilding lexer to measure construction overhead.
fn tokenize_with_rebuild(
  spec : @kgf_types.KGFSpec,
  source_text : String,
) -> Int {
  let lexer = @kgf_lexer.Lexer::for_spec(spec)
  lexer.tokenize(source_text).length()
}
