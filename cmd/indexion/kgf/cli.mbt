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
/// ```

///|
/// CLI configuration.
priv struct KgfConfig {
  mut subcommand : String
  mut file_path : String
  mut spec_name : String // empty means auto-detect
  mut kgf_dir : String
  show_tokens : Bool
  show_events : Bool
  show_edges : Bool
  mut show_help : Bool
}

///|
fn KgfConfig::default() -> KgfConfig {
  {
    subcommand: "inspect",
    file_path: "",
    spec_name: "",
    kgf_dir: "kgfs",
    show_tokens: true,
    show_events: true,
    show_edges: true,
    show_help: false,
  }
}

///|
/// Main entry point for kgf command.
pub fn run(args : Array[String], start_idx : Int) -> Unit {
  let config = parse_args(args, start_idx)
  if config.show_help {
    show_help()
    return
  }
  if config.file_path.length() == 0 {
    println("Error: No file specified")
    println("")
    show_help()
    return
  }
  match config.subcommand {
    "inspect" => run_inspect(config)
    "tokens" => run_tokens(config)
    "events" => run_events(config)
    "edges" => run_edges(config)
    _ => {
      println("Unknown subcommand: \{config.subcommand}")
      show_help()
    }
  }
}

///|
/// Parse command line arguments.
fn parse_args(args : Array[String], start_idx : Int) -> KgfConfig {
  let config = KgfConfig::default()
  let mut i = start_idx
  let mut subcommand_set = false
  while i < args.length() {
    let arg = args[i]
    if arg.has_prefix("--spec=") {
      config.spec_name = substr_from(arg, 7)
    } else if arg.has_prefix("--kgf-dir=") {
      config.kgf_dir = substr_from(arg, 10)
    } else if arg == "--help" || arg == "-h" {
      config.show_help = true
    } else if arg.has_prefix("-") {
      println("Warning: Unknown option: \{arg}")
    } else if not(subcommand_set) {
      config.subcommand = arg
      subcommand_set = true
    } else {
      config.file_path = arg
    }
    i += 1
  }
  config
}

///|
/// Run full inspection.
fn run_inspect(config : KgfConfig) -> Unit {
  println("=== indexion kgf inspect ===")
  println("File: \{config.file_path}")
  println("")
  let registry = @registry.KGFRegistry::load_from_dir(config.kgf_dir)
  let spec_name = if config.spec_name.length() > 0 {
    config.spec_name
  } else {
    match registry.detect_from_path(config.file_path) {
      Some(name) => name
      None => {
        println("Error: Cannot detect language for file")
        println("Use --spec=<name> to specify explicitly")
        return
      }
    }
  }
  println("Detected spec: \{spec_name}")
  let spec = match registry.get_spec(spec_name) {
    Some(s) => s
    None => {
      println("Error: Spec '\{spec_name}' not found")
      return
    }
  }
  let source = @fs.read_file_to_string(config.file_path) catch {
    err => {
      println("Error reading file: \{err}")
      return
    }
  }
  // Ensure trailing newline
  let source = if source.has_suffix("\n") { source } else { source + "\n" }
  println("Source length: \{source.length()} chars")
  println("")
  // Tokenize
  println("=== Tokens ===")
  let lexer = @lexer.Lexer::new(spec.get_tokens())
  let tokens = lexer.tokenize(source)
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
  let parse_result = @peg.run_parse(peg, spec, start_rule, tokens)
  match parse_result {
    Some(eval_result) => {
      let events = eval_result.get_events()
      println("Parse: SUCCESS")
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
      println("")
      println("Possible issues:")
      println("  - Grammar doesn't match file structure")
      println("  - Missing tokens or rules")
      println("  - File format issues")
    }
  }
}

///|
/// Run tokens-only inspection.
fn run_tokens(config : KgfConfig) -> Unit {
  let c = { ..config, show_events: false, show_edges: false }
  run_inspect(c)
}

///|
/// Run events-only inspection.
fn run_events(config : KgfConfig) -> Unit {
  let c = { ..config, show_tokens: false, show_edges: false }
  run_inspect(c)
}

///|
/// Run edges-only inspection.
fn run_edges(config : KgfConfig) -> Unit {
  let c = { ..config, show_tokens: false, show_events: false }
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
/// Substring from index.
fn substr_from(s : String, start : Int) -> String {
  let chars = s.to_array()
  let result : Array[Char] = []
  for i = start; i < chars.length(); i = i + 1 {
    result.push(chars[i])
  }
  String::from_array(result)
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
/// Show help message.
fn show_help() -> Unit {
  println("indexion kgf - KGF inspection tools")
  println("")
  println("Usage:")
  println("  indexion kgf <subcommand> [options] <file>")
  println("")
  println("Subcommands:")
  println("  inspect   Full inspection (tokens, events, edges)")
  println("  tokens    Show tokenization only")
  println("  events    Show parse events only")
  println("  edges     Show generated edges only")
  println("")
  println("Options:")
  println("  --spec=NAME      Specify KGF spec name (auto-detect if omitted)")
  println("  --kgf-dir=PATH   KGF specs directory (default: kgfs)")
  println("  --help, -h       Show this help message")
  println("")
  println("Examples:")
  println("  indexion kgf inspect Cargo.toml")
  println("  indexion kgf tokens --spec=go-mod go.mod")
  println("  indexion kgf edges fixtures/project/npm/package.json")
}
