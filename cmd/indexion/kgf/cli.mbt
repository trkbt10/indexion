///|
/// # indexion kgf
///
/// KGF (Knowledge Graph Framework) inspection tools.
///
/// ## Overview
///
/// Debug and inspect KGF spec parsing. Useful for developing and testing
/// new language specifications.
///
/// ## Usage
///
/// ```bash
/// indexion kgf <subcommand> [options]
/// ```
///
/// ## Subcommands
///
/// | Subcommand | Description |
/// |------------|-------------|
/// | `inspect` | Inspect parsing of a file with a KGF spec |
/// | `tokens` | Show tokenization result only |
/// | `events` | Show parse events only |
/// | `edges` | Show generated edges only |
/// | `check` | Validate spec structure; `--all` adds the cross-spec report |
///
/// ## Examples
///
/// ```bash
/// # Full inspection of a file
/// indexion kgf inspect fixtures/project/cargo/Cargo.toml
///
/// # Show only tokens
/// indexion kgf tokens fixtures/project/go/go.mod
///
/// # Specify spec explicitly
/// indexion kgf inspect --spec=cargo-toml Cargo.toml
///
/// # Validate every installed spec and report contested source patterns
/// indexion kgf check --all
/// ```

///|
/// CLI configuration.
priv struct KgfConfig {
  mut subcommand : String
  mut file_path : String
  mut spec_name : String // empty means auto-detect
  kgf_dirs : Array[String]
  mut format : String // "human" or "json"
  mut target_lang : String // for `transcribe`: target KGF spec name
  show_tokens : Bool
  show_events : Bool
  show_edges : Bool
}

///|
fn KgfConfig::default() -> KgfConfig {
  {
    subcommand: "inspect",
    file_path: "",
    spec_name: "",
    kgf_dirs: [],
    format: "human",
    target_lang: "",
    show_tokens: true,
    show_events: true,
    show_edges: true,
  }
}

///|
/// Create KgfConfig from argparse Matches.
fn KgfConfig::from_matches(matches : @argparse.Matches) -> KgfConfig {
  let mut config = {
    ..KgfConfig::default(),
    kgf_dirs: @common.arg_specs_dirs(matches, key="kgf-dir"),
  }
  // Global options
  match matches.values.get("spec") {
    Some(vals) =>
      if vals.length() > 0 && vals[0].length() > 0 {
        config.spec_name = vals[0]
      }
    None => ()
  }
  // Subcommand dispatch
  match matches.subcommand {
    Some((name, sub_matches)) => {
      config.subcommand = name
      match name {
        "add" =>
          match sub_matches.values.get("spec-name") {
            Some(vals) => if vals.length() > 0 { config.file_path = vals[0] }
            None => ()
          }
        "inspect" | "tokens" | "events" | "edges" => {
          match sub_matches.values.get("file") {
            Some(vals) => if vals.length() > 0 { config.file_path = vals[0] }
            None => ()
          }
          match sub_matches.values.get("format") {
            Some(vals) =>
              if vals.length() > 0 && vals[0].length() > 0 {
                config.format = vals[0]
              }
            None => ()
          }
          match name {
            "tokens" =>
              config = { ..config, show_events: false, show_edges: false, }
            "events" =>
              config = { ..config, show_tokens: false, show_edges: false, }
            "edges" =>
              config = { ..config, show_tokens: false, show_events: false, }
            _ => ()
          }
        }
        "transcribe" => {
          match sub_matches.values.get("file") {
            Some(vals) => if vals.length() > 0 { config.file_path = vals[0] }
            None => ()
          }
          match sub_matches.values.get("to") {
            Some(vals) =>
              if vals.length() > 0 && vals[0].length() > 0 {
                config.target_lang = vals[0]
              }
            None => ()
          }
        }
        _ => ()
      }
    }
    None => ()
  }
  config
}

///|
/// Define the kgf command for argparse.
pub fn command() -> @argparse.Command {
  let global_options : Array[@argparse.OptionArg] = [
    @argparse.OptionArg(
      "spec",
      about="Specify KGF spec name (auto-detect if omitted)",
      default_values=[""],
      global=true,
    ),
    @help.specs_dir_option(name="kgf-dir", global=true),
  ]
  let file_positional : Array[@argparse.PositionArg] = [
    @argparse.PositionArg(
      "file",
      about="File to inspect",
      num_args=@argparse.ValueRange::single(),
    ),
  ]
  let format_option : Array[@argparse.OptionArg] = [
    @argparse.OptionArg("format", about="Output format: human, json", default_values=[
      "human",
    ]),
  ]
  @argparse.Command(
    "kgf",
    about="KGF spec management and inspection",
    options=global_options[:],
    subcommand_required=true,
    arg_required_else_help=true,
    subcommands=[
      @argparse.Command("list", about="List installed KGF specs"),
      @argparse.Command("update", about="Update all specs from GitHub"),
      @argparse.Command("add", about="Download and install a single spec", positionals=[
        @argparse.PositionArg(
          "spec-name",
          about="Name of the spec to add",
          num_args=@argparse.ValueRange::single(),
        ),
      ]),
      @argparse.Command(
        "inspect",
        about="Full inspection (tokens, events, edges)",
        positionals=file_positional[:],
        options=format_option[:],
      ),
      @argparse.Command(
        "tokens",
        about="Show tokenization only",
        positionals=file_positional[:],
        options=format_option[:],
      ),
      @argparse.Command(
        "events",
        about="Show parse events only",
        positionals=file_positional[:],
        options=format_option[:],
      ),
      @argparse.Command(
        "edges",
        about="Show generated edges only",
        positionals=file_positional[:],
        options=format_option[:],
      ),
      @argparse.Command(
        "transcribe",
        about="Rewrite KGF events from one language spec into another (data-driven)",
        positionals=file_positional[:],
        options=[
          @argparse.OptionArg(
            "to",
            about="Target KGF spec name (e.g. moonbit). Used to look up kgfs/transpile/<source>-to-<to>.json",
            default_values=[""],
          ),
        ],
      ),
      @argparse.Command(
        "check",
        about="Validate KGF spec structure (regex, symbol references, semantics)",
        positionals=[
          @argparse.PositionArg(
            "spec-or-file",
            about="KGF spec name or .kgf file path (omit to check the whole resolved set)",
            num_args=@argparse.ValueRange(lower=0),
          ),
        ],
        flags=[
          @argparse.FlagArg(
            "all",
            about="Check every spec in the resolved set and report source-pattern conflicts (the default when no name is given)",
          ),
        ],
      ),
      @argparse.Command(
        "classify",
        about="Classification model tools",
        subcommand_required=true,
        subcommands=[
          @argparse.Command(
            "train",
            about="Train a Naive Bayes section classifier from labeled documents",
            positionals=[
              @argparse.PositionArg(
                "directory",
                about="Directory containing training documents",
                num_args=@argparse.ValueRange(lower=1),
              ),
            ],
            options=[
              @argparse.OptionArg(
                "default-class",
                about="Class label for unlabeled sections (default: normative)",
                default_values=["normative"],
              ),
              @argparse.OptionArg("include", about=@help.include_pattern, default_values=[
                "",
              ]),
              @argparse.OptionArg("exclude", about=@help.exclude_pattern, default_values=[
                "",
              ]),
              @argparse.OptionArg(
                "min-weight",
                about="Minimum term weight to include in model (reduces model size)",
                default_values=["0.5"],
              ),
            ],
          ),
        ],
      ),
    ],
  )
}

///|
/// Entry point for the kgf subcommand using argparse Matches.
pub async fn run_matches(matches : @argparse.Matches) -> Unit {
  let config = KgfConfig::from_matches(matches)
  match config.subcommand {
    "list" => run_list(config.kgf_dirs)
    "update" => run_kgf_update()
    "add" => {
      if config.file_path.length() == 0 {
        println("Error: Spec name required")
        println("")
        println("Usage: indexion kgf add <spec-name>")
        return
      }
      run_kgf_add(config.file_path)
    }
    "transcribe" => {
      if config.file_path.length() == 0 {
        println("Error: No file specified")
        println("")
        println(command().render_help())
        return
      }
      if config.target_lang.length() == 0 {
        println("Error: --to <target-lang> is required")
        return
      }
      match
        @kgf_transpile.transpile_file_json(
          config.file_path,
          config.target_lang,
          config.kgf_dirs,
        ) {
        Some(s) => println(s)
        None =>
          println(
            "Error: cannot transcribe '\{config.file_path}' to '\{config.target_lang}'",
          )
      }
    }
    "inspect" | "tokens" | "events" | "edges" => {
      if config.file_path.length() == 0 {
        println("Error: No file specified")
        println("")
        println(command().render_help())
        return
      }
      if config.format == "json" {
        let json_out = match config.subcommand {
          "inspect" =>
            inspect_json(config.file_path, config.spec_name, config.kgf_dirs)
          "tokens" =>
            tokenize_json(config.file_path, config.spec_name, config.kgf_dirs)
          "events" =>
            events_json(config.file_path, config.spec_name, config.kgf_dirs)
          "edges" =>
            edges_json(config.file_path, config.spec_name, config.kgf_dirs)
          _ => None
        }
        match json_out {
          Some(s) => println(s)
          None => println("Error: failed to inspect '\{config.file_path}'")
        }
        return
      }
      match config.subcommand {
        "inspect" => run_inspect(config)
        "tokens" => run_tokens(config)
        "events" => run_events(config)
        "edges" => run_edges(config)
        _ => ()
      }
    }
    "check" =>
      match matches.subcommand {
        Some((_, check_matches)) => run_check(config.kgf_dirs, check_matches)
        _ => println(command().render_help())
      }
    "classify" =>
      match matches.subcommand {
        Some((_, classify_matches)) =>
          match classify_matches.subcommand {
            Some(("train", train_matches)) =>
              run_classify_train(
                config.kgf_dirs,
                config.spec_name,
                train_matches,
              )
            _ => println(command().render_help())
          }
        _ => println(command().render_help())
      }
    _ => {
      println("Unknown subcommand: \{config.subcommand}")
      println(command().render_help())
    }
  }
}

///|
/// Label for the layer a spec's winning file came from: the base set, or the
/// 1-based position of the overlay that provided it.
fn layer_label(layer : Int) -> String {
  if layer == 0 {
    "base"
  } else {
    "overlay " + layer.to_string()
  }
}

///|
/// List the KGF specs of the resolved, layered spec set.
///
/// Each row names the file that won for that language, so a project that
/// overlays one spec can see at a glance which of its files is in effect and
/// which installed file it replaced.
fn run_list(kgf_dirs : Array[String]) -> Unit {
  let dirs = @kgf_features.resolve_specs_dirs(specs_dirs=kgf_dirs)
  let specs = @kgf_manage.list_specs_from_dirs(dirs)
  if specs.length() == 0 {
    println("No KGF specs installed.")
    if dirs.length() > 0 {
      println("Searched: " + dirs.join(", "))
    } else {
      println("No kgfs directory found.")
    }
    return
  }
  for layer, dir in dirs {
    println(layer_label(layer) + ": " + dir)
  }
  println("")
  // Print table header. The Extends column names the base a derived spec
  // inherits its undeclared sections from, so a reader can tell at a glance
  // which specs are not self-contained. The Origin column names the layer the
  // winning file came from, which is what a reader needs once overlays are in
  // play — the two are independent: an overlay spec may extend a base-layer
  // one, and a spec an overlay replaced may still be the base of others.
  println(
    pad_right("Category", 14) +
    pad_right("Name", 22) +
    pad_right("Extends", 18) +
    pad_right("Origin", 12) +
    "Sources",
  )
  println(
    pad_right("─".repeat(12), 14) +
    pad_right("─".repeat(20), 22) +
    pad_right("─".repeat(16), 18) +
    pad_right("─".repeat(10), 12) +
    "─".repeat(20),
  )
  // The listing shows each spec's declared sources, but declaring a pattern
  // is not the same as owning it: when several specs claim one, the registry
  // silently gives it to a single winner. Mark the contested patterns so the
  // table does not read as if every claim were honoured. The registry is built
  // over the same resolved chain, so the winner reflects the overlay too.
  let conflicts = load_registry(kgf_dirs).get_source_conflicts()
  let winner_of : Map[String, String] = Map([])
  for conflict in conflicts {
    winner_of.set(conflict.get_pattern(), conflict.get_winner())
  }
  let mut overridden = 0
  for spec in specs {
    let sources = if spec.info.sources.length() > 0 {
      annotate_contested_sources(spec.info.sources, spec.info.name, winner_of).join(
        ", ",
      )
    } else {
      "(none)"
    }
    let category = if spec.info.category.length() > 0 {
      spec.info.category
    } else {
      "(root)"
    }
    let extends = match spec.info.extends {
      Some(base) if base.length() > 0 => base
      _ => "-"
    }
    println(
      pad_right(category, 14) +
      pad_right(spec.info.name, 22) +
      pad_right(extends, 18) +
      pad_right(layer_label(spec.layer), 12) +
      sources,
    )
    if spec.shadowed.length() > 0 {
      overridden += 1
      println("  from:     " + spec.info.path)
      for path in spec.shadowed {
        println("  replaces: " + path)
      }
    }
  }
  println("")
  println("Total: \{specs.length()} specs")
  if overridden > 0 {
    println("Shadowed by a later file of the same language: \{overridden}")
  }
  if conflicts.length() > 0 {
    println("")
    println("Contested source patterns (only the winner analyses the files):")
    for conflict in conflicts {
      println(
        "  " +
        conflict.get_pattern() +
        " -> " +
        conflict.get_winner() +
        " (shadows " +
        conflict.get_losers().join(", ") +
        ")",
      )
    }
  }
}

///|
/// Tags each of a spec's source patterns that another spec also claims: the
/// winner keeps its pattern flagged with `(*)`, and every loser gets the
/// winner named beside the pattern it does not actually own.
fn annotate_contested_sources(
  sources : Array[String],
  lang : String,
  winner_of : Map[String, String],
) -> Array[String] {
  let out : Array[String] = []
  for source in sources {
    match winner_of.get(source) {
      Some(winner) =>
        if winner == lang {
          out.push(source + " (*)")
        } else {
          out.push(source + " (shadowed by " + winner + ")")
        }
      None => out.push(source)
    }
  }
  out
}

///|
/// Update KGF specs from GitHub.
async fn run_kgf_update() -> Unit {
  @kgf_manage.update_kgfs() catch {
    err => {
      println("Error: " + err.to_string())
      return
    }
  }
}

///|
/// Add a single KGF spec from GitHub.
async fn run_kgf_add(spec_name : String) -> Unit {
  @kgf_manage.add_kgf(spec_name) catch {
    err => {
      println("Error: " + err.to_string())
      return
    }
  }
}

///|
/// Pad string to the right with spaces.
fn pad_right(s : String, width : Int) -> String {
  if s.length() >= width {
    return s
  }
  let buf = StringBuilder()
  buf.write_string(s)
  for i = s.length(); i < width; i = i + 1 {
    buf.write_char(' ')
  }
  buf.to_string()
}

///|
/// Resolve the spec directories a `--kgf-dir` chain names.
///
/// An empty chain is not a path but a request to auto-detect, so the base set
/// is resolved as usual and the project-local `.indexion/kgfs/` overlay is
/// layered on top. A non-empty chain replaces that: the first entry is the
/// base and each later one is an overlay. Composition lives in
/// `@kgf_features.resolve_specs_dirs`, which wraps the `@config` SoT.
///
/// Shared by every kgf subcommand that needs the directories rather than a
/// loaded registry — `kgf check` resolves `extends:` against the raw sources
/// of the same chain.
fn resolve_kgfs_dirs(
  kgf_dirs : Array[String],
  targets? : Array[String] = [],
) -> Array[String] {
  let target_dirs : Array[String] = []
  for target in targets {
    if target.length() > 0 {
      target_dirs.push(target)
    }
  }
  if target_dirs.length() == 0 {
    target_dirs.push(".")
  }
  @kgf_features.resolve_specs_dirs(specs_dirs=kgf_dirs, target_dirs~)
}

///|
/// Load KGF registry over the resolved, layered spec directories.
///
/// Composition of the chain lives in `resolve_kgfs_dirs`; this only turns the
/// resolved chain into a registry. Because `load_from_dirs` flattens the
/// layers before resolving `extends:`, an overlay spec may extend one that
/// only the base layer provides.
fn load_registry(
  kgf_dirs : Array[String],
  targets? : Array[String] = [],
) -> @registry.KGFRegistry {
  @registry.KGFRegistry::load_from_dirs(resolve_kgfs_dirs(kgf_dirs, targets~))
}

///|
/// Run full inspection.
fn run_inspect(config : KgfConfig) -> Unit {
  println("=== indexion kgf inspect ===")
  println("File: \{config.file_path}")
  println("")
  let registry = load_registry(config.kgf_dirs, targets=[config.file_path])
  let resolved = match
    resolve_spec_name(config.file_path, config.spec_name, registry) {
    Some(n) => n
    None => {
      println("Error: Cannot detect language for file")
      println("Use --spec=<name> to specify explicitly")
      return
    }
  }
  println("Detected spec: \{resolved}")
  let spec = match registry.get_spec(resolved) {
    Some(s) => s
    None => {
      println("Error: Spec '\{resolved}' not found")
      return
    }
  }
  let source = match read_source(config.file_path) {
    Some(s) => s
    None => {
      println("Error reading file: \{config.file_path}")
      return
    }
  }
  // Prepare first: everything printed below (lengths, positions, tokens) must
  // describe the text the parser actually sees.
  let (source, tokens) = prepare_and_tokenize(spec, source)
  println("Source length: \{source.length()} chars")
  println("")
  println("=== Tokens ===")
  println("Token count: \{tokens.length()}")
  if config.show_tokens {
    for i, tok in tokens {
      if i < 50 {
        println("  [\{i}] \{tok.kind}: \"\{escape_string(tok.text)}\"")
      } else if i == 50 {
        println("  ... (\{tokens.length() - 50} more tokens)")
      }
    }
  }
  println("")
  // Parse
  println("=== Parse ===")
  let peg = @peg.build_peg(spec) catch {
    err => {
      println("Error building PEG: \{err}")
      return
    }
  }
  let start_rule = spec.get_start_rule()
  println("Start rule: \{start_rule}")
  let (parse_result, diagnostic) = @peg.run_parse_with_diagnostics(
    peg, spec, start_rule, tokens,
  )
  match parse_result {
    Some(eval_result) => {
      let events = eval_result.get_events()
      if diagnostic.is_fully_consumed() {
        println("Parse: SUCCESS")
      } else {
        // The start rule matched a prefix of the token stream and stopped.
        // Everything after the stop point is invisible to events, semantics
        // and edges, so say so instead of reporting a bare SUCCESS.
        println(
          "Parse: PARTIAL (consumed \{diagnostic.get_furthest_pos()} of \{tokens.length()} tokens)",
        )
        println("  " + describe_parse_stop(source, diagnostic))
        println(
          "  Events, semantics and edges below cover only the consumed prefix.",
        )
      }
      println("Event count: \{events.length()}")
      if config.show_events {
        println("")
        println("=== Events ===")
        for i, event in events {
          let rule_name = event.0
          let labels = event.1
          if i < 100 {
            let labels_str = format_labels(labels)
            println("  [\{i}] \{rule_name} \{labels_str}")
          } else if i == 100 {
            println("  ... (\{events.length() - 100} more events)")
          }
        }
      }
      // Evaluate semantics
      println("")
      println("=== Semantics ===")
      let graph = @graph.CodeGraph::new()
      let _ = graph.get_or_add_module(
        config.file_path,
        file=Some(config.file_path),
      )
      let ctx = @semantics.SemEvalCtx::new(
        spec,
        graph,
        config.file_path,
        "",
        spec.get_language(),
        fn(_path) { false },
      )
      for event in events {
        let rule_name = event.0
        let labels = event.1
        @semantics.eval_rule_semantics(rule_name, labels, ctx)
      }
      let edges = graph.get_edges()
      println("Edge count: \{edges.length()}")
      if config.show_edges {
        println("")
        println("=== Edges ===")
        for edge in edges {
          let attrs_str = format_attrs(edge.attrs)
          println(
            "  \{edge.kind.to_string()}: \{edge.from} -> \{edge.to}\{attrs_str}",
          )
        }
      }
    }
    None => {
      println("Parse: FAILED")
      println("  " + describe_parse_stop(source, diagnostic))
      println("")
      println("Possible issues:")
      println("  - Grammar doesn't match file structure")
      println("  - Missing tokens or rules")
      println("  - File format issues")
    }
  }
}

///|
/// Formats where the parser stopped as "line L, col C: <reason>" using the
/// diagnostic's actual token position (end of input when there is none).
fn describe_parse_stop(
  source : String,
  diagnostic : @peg.ParseDiagnostic,
) -> String {
  let pos = match diagnostic.get_actual_token() {
    Some(tok) => tok.get_pos()
    None => source.length()
  }
  let (line, col) = @kgf_check.SourceMap::new(source).resolve(pos)
  "stopped at line \{line}, col \{col}: " + diagnostic.describe()
}

///|
/// Run tokens-only inspection (no parse step).
fn run_tokens(config : KgfConfig) -> Unit {
  println("=== indexion kgf inspect ===")
  println("File: \{config.file_path}")
  println("")
  let registry = load_registry(config.kgf_dirs, targets=[config.file_path])
  let resolved = match
    resolve_spec_name(config.file_path, config.spec_name, registry) {
    Some(n) => n
    None => {
      println("Error: Cannot detect language for file")
      println("Use --spec=<name> to specify explicitly")
      return
    }
  }
  println("Detected spec: \{resolved}")
  let spec = match registry.get_spec(resolved) {
    Some(s) => s
    None => {
      println("Error: Spec '\{resolved}' not found")
      return
    }
  }
  let source = match read_source(config.file_path) {
    Some(s) => s
    None => {
      println("Error reading file: \{config.file_path}")
      return
    }
  }
  let (source, tokens) = prepare_and_tokenize(spec, source)
  println("Source length: \{source.length()} chars")
  println("")
  println("=== Tokens ===")
  println("Token count: \{tokens.length()}")
  for i, tok in tokens {
    if i < 50 {
      println("  [\{i}] \{tok.kind}: \"\{escape_string(tok.text)}\"")
    } else if i == 50 {
      println("  ... (\{tokens.length() - 50} more tokens)")
    }
  }
}

///|
/// Run events-only inspection.
fn run_events(config : KgfConfig) -> Unit {
  let c = { ..config, show_tokens: false, show_edges: false, }
  run_inspect(c)
}

///|
/// Run edges-only inspection.
fn run_edges(config : KgfConfig) -> Unit {
  let c = { ..config, show_tokens: false, show_events: false, }
  run_inspect(c)
}

///|
/// Format labels map for display.
fn format_labels(labels : Map[String, Json]) -> String {
  if labels.is_empty() {
    return ""
  }
  let parts : Array[String] = []
  for entry in labels {
    let k = entry.0
    let v = entry.1
    let v_str = match v {
      String(s) => "\"" + escape_string(s) + "\""
      Number(n, ..) => n.to_string()
      True => "true"
      False => "false"
      Null => "null"
      _ => v.stringify()
    }
    parts.push("\{k}=\{v_str}")
  }
  "{ " + parts.join(", ") + " }"
}

///|
/// Format edge attrs for display.
fn format_attrs(attrs : Map[String, String]) -> String {
  if attrs.is_empty() {
    return ""
  }
  let parts : Array[String] = []
  for entry in attrs {
    parts.push("\{entry.0}=\"\{entry.1}\"")
  }
  " [" + parts.join(", ") + "]"
}

///|
/// Escape string for display.
fn escape_string(s : String) -> String {
  let chars = s.to_array()
  let result : Array[Char] = []
  for c in chars {
    match c {
      '\n' => {
        result.push('\\')
        result.push('n')
      }
      '\r' => {
        result.push('\\')
        result.push('r')
      }
      '\t' => {
        result.push('\\')
        result.push('t')
      }
      '\\' => {
        result.push('\\')
        result.push('\\')
      }
      '"' => {
        result.push('\\')
        result.push('"')
      }
      _ => result.push(c)
    }
  }
  String::from_array(result)
}

///|
/// List installed KGF specs as JSON string.
pub fn list_specs_json() -> String {
  let specs = @kgf_manage.list_installed_specs()
  let arr : Array[Json] = specs
    .iter()
    .map(fn(spec) {
      let obj : Map[String, Json] = Map([])
      obj.set("name", spec.name.to_json())
      obj.set("category", spec.category.to_json())
      obj.set(
        "sources",
        Json::array(spec.sources.iter().map(fn(s) { s.to_json() }).collect()),
      )
      match spec.extends {
        Some(base) if base.length() > 0 => obj.set("extends", base.to_json())
        _ => ()
      }
      Json::object(obj)
    })
    .collect()
  Json::array(arr).stringify()
}

///|
/// Return a map of spec name -> spec content for all installed specs.
/// Used by serve to expose /api/kgf/specs/{name} routes.
pub fn all_specs_content() -> Map[String, String] {
  let result : Map[String, String] = Map([])
  let specs = @kgf_manage.list_installed_specs()
  for spec in specs {
    let content = @fs.read_file_to_string(spec.path) catch { _ => continue }
    result[spec.name] = content
  }
  result
}

///|
/// Resolve spec name from file path (shared resolution logic).
fn resolve_spec_name(
  file_path : String,
  spec_name : String,
  registry : @registry.KGFRegistry,
) -> String? {
  if spec_name.length() > 0 {
    Some(spec_name)
  } else {
    registry.detect_from_path(file_path)
  }
}

///|
/// Prepares source text and tokenizes it exactly the way the analysis pipeline
/// does (`parse_source` / `ToolkitRegistry::tokenize`): the spec's
/// `=== preprocess` steps run first, then the cached lexer.
///
/// Returns the prepared text alongside the tokens. Every position an inspect
/// command reports — line/col, `pos`, `source_length`, the parse-stop location
/// — is resolved against the PREPARED text, because that is what was
/// tokenized. For a spec with no preprocess section the prepared text is the
/// raw source, so nothing changes there.
fn prepare_and_tokenize(
  spec : @kgf_types.KGFSpec,
  source : String,
) -> (String, Array[@kgf_types.Tok]) {
  let toolkit = @kgf_toolkit.LanguageToolkit::from_spec(spec)
  let prepared = toolkit.preprocess(source)
  (prepared, toolkit.get_lexer().tokenize(prepared))
}

///|
/// Read file and ensure trailing newline.
fn read_source(file_path : String) -> String? {
  let source = @fs.read_file_to_string(file_path) catch { _ => return None }
  Some(if source.has_suffix("\n") { source } else { source + "\n" })
}

///|
/// Tokenize a file and return tokens as JSON string.
pub fn tokenize_json(
  file_path : String,
  spec_name : String,
  kgf_dirs : Array[String],
) -> String? {
  let registry = load_registry(kgf_dirs, targets=[file_path])
  let resolved = match resolve_spec_name(file_path, spec_name, registry) {
    Some(n) => n
    None => return None
  }
  let spec = match registry.get_spec(resolved) {
    Some(s) => s
    None => return None
  }
  let source = match read_source(file_path) {
    Some(s) => s
    None => return None
  }
  let (source, tokens) = prepare_and_tokenize(spec, source)
  // Build pos → (line, col) lookup from source
  let line_starts = build_line_starts(source)
  let arr : Array[Json] = tokens
    .iter()
    .map(fn(tok) {
      let (line, col) = pos_to_line_col(line_starts, tok.pos)
      let obj : Map[String, Json] = Map([])
      obj.set("kind", tok.kind.to_json())
      obj.set("text", tok.text.to_json())
      obj.set("line", line.to_json())
      obj.set("col", col.to_json())
      Json::object(obj)
    })
    .collect()
  Some(Json::array(arr).stringify())
}

///|
/// Extract parse events from a file and return as JSON string.
///
/// Each event is `{"rule": String, "labels": Object}`. Labels mirror the
/// per-event metadata produced by the PEG evaluator (id text/positions, span
/// tokens, captured slices). Used by transpilation/refactoring tools that
/// consume the AST without re-parsing the human-readable transcript.
pub fn events_json(
  file_path : String,
  spec_name : String,
  kgf_dirs : Array[String],
) -> String? {
  let registry = load_registry(kgf_dirs, targets=[file_path])
  let resolved = match resolve_spec_name(file_path, spec_name, registry) {
    Some(n) => n
    None => return None
  }
  let spec = match registry.get_spec(resolved) {
    Some(s) => s
    None => return None
  }
  let source = match read_source(file_path) {
    Some(s) => s
    None => return None
  }
  let (_, tokens) = prepare_and_tokenize(spec, source)
  let peg = @peg.build_peg(spec) catch { _ => return None }
  let start_rule = spec.get_start_rule()
  match @peg.run_parse(peg, spec, start_rule, tokens) {
    Some(eval_result) => {
      let events = eval_result.get_events()
      let arr : Array[Json] = events
        .iter()
        .map(fn(event) {
          let obj : Map[String, Json] = Map([])
          obj.set("rule", event.0.to_json())
          obj.set("labels", Json::object(event.1))
          Json::object(obj)
        })
        .collect()
      Some(Json::array(arr).stringify())
    }
    None => None
  }
}

///|
/// Combined inspection (tokens + events + edges) as JSON string.
///
/// Top-level keys: `spec`, `file`, `source_length`, `tokens`, `events`, `edges`.
/// Returns `None` when the file is unreadable or the spec cannot be resolved;
/// returns a partial object (with `parse_failed: true`) when the parse fails
/// so callers can still use the token stream.
pub fn inspect_json(
  file_path : String,
  spec_name : String,
  kgf_dirs : Array[String],
) -> String? {
  let registry = load_registry(kgf_dirs, targets=[file_path])
  let resolved = match resolve_spec_name(file_path, spec_name, registry) {
    Some(n) => n
    None => return None
  }
  let spec = match registry.get_spec(resolved) {
    Some(s) => s
    None => return None
  }
  let source = match read_source(file_path) {
    Some(s) => s
    None => return None
  }
  let (source, tokens) = prepare_and_tokenize(spec, source)
  let line_starts = build_line_starts(source)
  let tokens_json : Array[Json] = tokens
    .iter()
    .map(fn(tok) {
      let (line, col) = pos_to_line_col(line_starts, tok.pos)
      let obj : Map[String, Json] = Map([])
      obj.set("kind", tok.kind.to_json())
      obj.set("text", tok.text.to_json())
      obj.set("pos", tok.pos.to_json())
      obj.set("line", line.to_json())
      obj.set("col", col.to_json())
      Json::object(obj)
    })
    .collect()
  let root : Map[String, Json] = Map([])
  root.set("spec", resolved.to_json())
  root.set("file", file_path.to_json())
  root.set("source_length", source.length().to_json())
  root.set("tokens", Json::array(tokens_json))
  let peg = @peg.build_peg(spec) catch {
    _ => {
      root.set("parse_failed", true.to_json())
      return Some(Json::object(root).stringify())
    }
  }
  let start_rule = spec.get_start_rule()
  match @peg.run_parse(peg, spec, start_rule, tokens) {
    Some(eval_result) => {
      let events = eval_result.get_events()
      let events_arr : Array[Json] = events
        .iter()
        .map(fn(event) {
          let obj : Map[String, Json] = Map([])
          obj.set("rule", event.0.to_json())
          obj.set("labels", Json::object(event.1))
          Json::object(obj)
        })
        .collect()
      root.set("events", Json::array(events_arr))
      let graph = @graph.CodeGraph::new()
      let _ = graph.get_or_add_module(file_path, file=Some(file_path))
      let ctx = @semantics.SemEvalCtx::new(
        spec,
        graph,
        file_path,
        "",
        spec.get_language(),
        fn(_path) { false },
      )
      for event in events {
        @semantics.eval_rule_semantics(event.0, event.1, ctx)
      }
      let edges = graph.get_edges()
      let edges_arr : Array[Json] = edges
        .iter()
        .map(fn(edge) {
          let obj : Map[String, Json] = Map([])
          obj.set("from", edge.from.to_json())
          obj.set("to", edge.to.to_json())
          obj.set("kind", edge.kind.to_string().to_json())
          let attrs : Map[String, Json] = Map([])
          for entry in edge.attrs {
            attrs.set(entry.0, entry.1.to_json())
          }
          obj.set("attrs", Json::object(attrs))
          Json::object(obj)
        })
        .collect()
      root.set("edges", Json::array(edges_arr))
    }
    None => root.set("parse_failed", true.to_json())
  }
  Some(Json::object(root).stringify())
}

///|
/// Extract edges from a file and return as JSON string.
pub fn edges_json(
  file_path : String,
  spec_name : String,
  kgf_dirs : Array[String],
) -> String? {
  let registry = load_registry(kgf_dirs, targets=[file_path])
  let resolved = match resolve_spec_name(file_path, spec_name, registry) {
    Some(n) => n
    None => return None
  }
  let spec = match registry.get_spec(resolved) {
    Some(s) => s
    None => return None
  }
  let source = match read_source(file_path) {
    Some(s) => s
    None => return None
  }
  let (_, tokens) = prepare_and_tokenize(spec, source)
  let peg = @peg.build_peg(spec) catch { _ => return None }
  let start_rule = spec.get_start_rule()
  match @peg.run_parse(peg, spec, start_rule, tokens) {
    Some(eval_result) => {
      let events = eval_result.get_events()
      let graph = @graph.CodeGraph::new()
      let _ = graph.get_or_add_module(file_path, file=Some(file_path))
      let ctx = @semantics.SemEvalCtx::new(
        spec,
        graph,
        file_path,
        "",
        spec.get_language(),
        fn(_path) { false },
      )
      for event in events {
        @semantics.eval_rule_semantics(event.0, event.1, ctx)
      }
      let edges = graph.get_edges()
      let arr : Array[Json] = edges
        .iter()
        .map(fn(edge) {
          let obj : Map[String, Json] = Map([])
          obj.set("from", edge.from.to_json())
          obj.set("to", edge.to.to_json())
          obj.set("kind", edge.kind.to_string().to_json())
          Json::object(obj)
        })
        .collect()
      Some(Json::array(arr).stringify())
    }
    None => None
  }
}

///|
/// Build an array of byte offsets where each line starts (1-indexed).
fn build_line_starts(source : String) -> Array[Int] {
  let starts : Array[Int] = [0] // line 1 starts at offset 0
  for i, c in source {
    if c == '\n' {
      starts.push(i + 1)
    }
  }
  starts
}

///|
/// Convert a byte offset to (line, col), both 1-indexed.
fn pos_to_line_col(line_starts : Array[Int], pos : Int) -> (Int, Int) {
  // Binary search for the last line_start <= pos
  let mut lo = 0
  let mut hi = line_starts.length() - 1
  while lo < hi {
    let mid = (lo + hi + 1) / 2
    if line_starts[mid] <= pos {
      lo = mid
    } else {
      hi = mid - 1
    }
  }
  (lo + 1, pos - line_starts[lo] + 1)
}

///|
/// Run the `kgf classify train` subcommand.
fn run_classify_train(
  kgf_dirs : Array[String],
  spec_name : String,
  matches : @argparse.Matches,
) -> Unit {
  // Parse arguments
  let directories = matches.values.get("directory").unwrap_or([])
  if directories.length() == 0 {
    println("Error: No training directory specified")
    return
  }
  let default_class = match matches.values.get("default-class") {
    Some(vals) => if vals.length() > 0 { vals[0] } else { "normative" }
    None => "normative"
  }
  let include_pattern = match matches.values.get("include") {
    Some(vals) =>
      if vals.length() > 0 && vals[0].length() > 0 {
        vals[0]
      } else {
        ""
      }
    None => ""
  }
  let exclude_pattern = match matches.values.get("exclude") {
    Some(vals) =>
      if vals.length() > 0 && vals[0].length() > 0 {
        vals[0]
      } else {
        ""
      }
    None => ""
  }
  let min_weight = match matches.values.get("min-weight") {
    Some(vals) =>
      if vals.length() > 0 {
        @common.parse_double(vals[0])
      } else {
        0.5
      }
    None => 0.5
  }
  // Load registry and resolve spec
  let registry = load_registry(kgf_dirs, targets=directories)
  // Collect training files
  let includes = if include_pattern.length() > 0 {
    [include_pattern]
  } else {
    []
  }
  let excludes = if exclude_pattern.length() > 0 {
    [exclude_pattern]
  } else {
    []
  }
  let file_entries = @common.collect_files(directories, includes~, excludes~)
  if file_entries.length() == 0 {
    println("Error: No files found in the specified directories")
    return
  }
  // Resolve which spec to use — need a document spec with DocumentSection semantics
  let spec = if spec_name.length() > 0 {
    match registry.get_spec(spec_name) {
      Some(s) => s
      None => {
        println("Error: Spec '\{spec_name}' not found")
        return
      }
    }
  } else {
    // Auto-detect from first file
    let first_path = file_entries[0].0
    let detected = match registry.detect_from_path(first_path) {
      Some(lang) =>
        match registry.get_spec(lang) {
          Some(s) => s
          None => {
            println("Error: Detected spec '\{lang}' not found")
            return
          }
        }
      None => {
        println("Error: Cannot detect language from '\{first_path}'")
        println("Use --spec=<name> to specify explicitly")
        return
      }
    }
    detected
  }
  // Convert file entries to (path, content) pairs
  let files : Array[(String, String)] = []
  for entry in file_entries {
    files.push((entry.0, entry.1))
  }
  println("=== indexion kgf classify train ===")
  println("Spec: \{spec.get_language()}")
  println("Files: \{files.length()}")
  println("Default class: \{default_class}")
  println("")
  // Train
  match @kgf_classify.train(files, spec, registry, default_class, min_weight~) {
    Some(model) => {
      // Report statistics
      let sections_count = model.get_meta("corpus_sections").unwrap_or("?")
      let vocab_count = model.get_meta("vocabulary_size").unwrap_or("?")
      println(
        "Training complete: " +
        sections_count +
        " sections, " +
        vocab_count +
        " vocabulary terms",
      )
      let class_names = model.get_class_names()
      for name in class_names {
        match model.get_class(name) {
          Some(cls) => {
            let term_count = cls.get_vocab().length().to_string()
            let prior = cls.get_prior().to_string()
            println("  @" + name + ": " + term_count + " terms, prior=" + prior)
          }
          None => ()
        }
      }
      println("")
      println("=== classify section ===")
      println("")
      // Output the serialized section
      println(@kgf_classify.serialize_classify_section(model))
    }
    None => println("Error: No training data found (no sections extracted)")
  }
}

///|
/// Running totals for a `kgf check` invocation.
priv struct CheckTally {
  mut specs : Int
  mut errors : Int
  mut warnings : Int
}

///|
/// Resolves one `check` target to its raw spec source: a registered spec name
/// first, then a `.kgf` file path. Prints the reason and returns None when
/// neither works.
fn resolve_check_target(
  by_language : Map[String, @kgf_parser.KGFSpecSource],
  target : String,
) -> @kgf_parser.KGFSpecSource? {
  match by_language.get(target) {
    Some(source) => Some(source)
    None => {
      let content = @fs.read_file_to_string(target) catch {
        _ => {
          println(
            "Error: '" + target + "' is not a known spec name or readable file",
          )
          return None
        }
      }
      Some(@kgf_parser.parse_kgf_source(content))
    }
  }
}

///|
/// Validates one spec source, prints its diagnostics and folds the counts
/// into `tally`.
///
/// `extends:` is resolved against every spec of the directory, so a check
/// needs the whole set even when a single spec was named. The spec that is
/// then validated is the *resolved* one: an inherited grammar has to be
/// judged against the deriving spec's own semantics, or a semantics block
/// referring to a rule the base does not define would go unreported.
fn report_spec_check(
  source : @kgf_parser.KGFSpecSource,
  by_language : Map[String, @kgf_parser.KGFSpecSource],
  tally : CheckTally,
) -> Unit {
  let (resolved, _) = @registry.resolve_spec_source(source, by_language)
  let spec = resolved.to_spec()
  let diagnostics = @kgf_check.check_extends(source, by_language)
  for d in @kgf_check.check(spec) {
    diagnostics.push(d)
  }
  let mut errors = 0
  let mut warnings = 0
  for d in diagnostics {
    match d.get_severity() {
      "error" => errors += 1
      _ => warnings += 1
    }
  }
  tally.specs += 1
  tally.errors += errors
  tally.warnings += warnings
  let name = spec.get_language()
  if diagnostics.length() == 0 {
    println(name + ": ok")
    return
  }
  println(
    name +
    ": " +
    errors.to_string() +
    " error(s), " +
    warnings.to_string() +
    " warning(s)",
  )
  for d in diagnostics {
    let prefix = if d.get_severity() == "error" { "  ERROR" } else { "  WARN " }
    println(prefix + " [" + d.get_section() + "] " + d.get_message())
  }
}

///|
/// Prints one warning per source pattern that several specs claim.
///
/// The registry resolves such a collision silently — the last general-purpose
/// spec to register keeps the pattern — so files matching it are never
/// analysed with the specs that lost. Reporting does not change the outcome;
/// it only makes the shadowing visible.
fn report_source_conflicts(
  registry : @registry.KGFRegistry,
  tally : CheckTally,
) -> Unit {
  let conflicts = registry.get_source_conflicts()
  if conflicts.length() == 0 {
    return
  }
  for conflict in conflicts {
    tally.warnings += 1
    let losers = conflict.get_losers()
    // "never sees" for one shadowed spec, "never see" for several.
    let verb = if losers.length() == 1 { " never sees " } else { " never see " }
    println(
      "  WARN  [sources] '" +
      conflict.get_pattern() +
      "' is claimed by several specs; '" +
      conflict.get_winner() +
      "' wins and " +
      losers.join(", ") +
      verb +
      "files matching it",
    )
  }
}

///|
/// Run the `kgf check` subcommand.
fn run_check(kgf_dirs : Array[String], matches : @argparse.Matches) -> Unit {
  let targets = matches.values.get("spec-or-file").unwrap_or([])
  // Naming nothing is a request to check everything, which is what a project
  // wants after adding an overlay; `--all` stays as the explicit spelling.
  let check_all = matches.flags.get("all").unwrap_or(false) ||
    targets.length() == 0
  // Resolve `extends:` against the flattened chain, not one directory, so a
  // spec may extend a base another layer provides and an overlay's version is
  // the one every deriving spec inherits from.
  let dirs = resolve_kgfs_dirs(kgf_dirs)
  let by_language = @kgf_check.load_spec_sources_from_dirs(dirs)
  if check_all && by_language.is_empty() && targets.length() == 0 {
    println(@help.no_specs_loaded)
    return
  }
  let tally : CheckTally = { specs: 0, errors: 0, warnings: 0, }
  if check_all {
    // Every spec of the resolved chain, in a stable order so the output can be
    // diffed.
    let languages : Array[String] = []
    for entry in by_language {
      languages.push(entry.0)
    }
    languages.sort()
    for lang in languages {
      match by_language.get(lang) {
        Some(source) => report_spec_check(source, by_language, tally)
        None => ()
      }
    }
    report_source_conflicts(load_registry(kgf_dirs), tally)
  }
  for target in targets {
    match resolve_check_target(by_language, target) {
      Some(source) => report_spec_check(source, by_language, tally)
      None => ()
    }
  }
  println("")
  println(
    "Checked " +
    tally.specs.to_string() +
    " spec(s): " +
    tally.errors.to_string() +
    " error(s), " +
    tally.warnings.to_string() +
    " warning(s)",
  )
  if tally.errors == 0 && tally.warnings == 0 {
    println("All checks passed.")
  }
}
