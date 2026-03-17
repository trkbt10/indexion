///|
/// # indexion plan unwrap
///
/// Detect unnecessary wrapper functions and plan their removal.
///
/// ## Overview
///
/// Scans source files for wrapper functions whose body is a single delegation
/// call with no added logic. Callers should use the delegate directly.
/// Supports report, dry-run preview, and auto-fix modes.
///
/// ## Modes
///
/// - (default): Report wrappers found (md/json/text)
/// - `--dry-run`: Preview all edits (call site replacements + definition deletions)
/// - `--fix`: Apply edits to files
///
/// ## Usage
///
/// ```bash
/// indexion plan unwrap [options] <directory>
/// indexion plan unwrap --dry-run --include='*.mbt' src/
/// indexion plan unwrap --fix --include='*.mbt' src/
/// ```

///|
/// CLI configuration.
pub struct UnwrapConfig {
  target_dir : String
  includes : Array[String]
  excludes : Array[String]
  output : String
  format : String
  include_self : Bool
  include_bare : Bool
  mode : String // "report", "dry-run", "fix"
  show_help : Bool
}

///|
/// Create a default configuration with report mode and markdown format.
pub fn UnwrapConfig::default() -> UnwrapConfig {
  {
    target_dir: "",
    includes: [],
    excludes: [],
    output: "",
    format: "md",
    include_self: false,
    include_bare: false,
    mode: "report",
    show_help: false,
  }
}

///|
/// Parse CLI arguments into an UnwrapConfig starting from the given index.
pub fn parse_args(args : Array[String], start_idx : Int) -> UnwrapConfig {
  let mut config = UnwrapConfig::default()
  for i = start_idx; i < args.length(); i = i + 1 {
    let arg = args[i]
    if arg == "--help" || arg == "-h" {
      config = { ..config, show_help: true }
    } else if arg.has_prefix("--include=") {
      config.includes.push(@common.get_arg_value(arg, 10))
    } else if arg.has_prefix("--exclude=") {
      config.excludes.push(@common.get_arg_value(arg, 10))
    } else if arg.has_prefix("--output=") || arg.has_prefix("-o=") {
      config = { ..config, output: @common.parse_output_arg(arg).unwrap() }
    } else if arg.has_prefix("--format=") {
      config = { ..config, format: @common.get_arg_value(arg, 9) }
    } else if arg == "--all" {
      config = { ..config, include_self: true, include_bare: true }
    } else if arg == "--include-self" {
      config = { ..config, include_self: true }
    } else if arg == "--include-bare" {
      config = { ..config, include_bare: true }
    } else if arg == "--dry-run" {
      config = { ..config, mode: "dry-run" }
    } else if arg == "--fix" {
      config = { ..config, mode: "fix" }
    } else if not(arg.has_prefix("-")) && config.target_dir.length() == 0 {
      config = { ..config, target_dir: arg }
    }
  }
  config
}

///|
/// Print usage information and available options to stdout.
pub fn show_help() -> Unit {
  println("indexion plan unwrap - Detect and remove unnecessary wrappers")
  println("")
  println("Usage:")
  println("  indexion plan unwrap [options] <directory>")
  println("")
  println("Modes:")
  println("  (default)            Report wrappers found")
  println("  --dry-run            Preview edits without applying")
  println(
    "  --fix                Apply edits (replace call sites, delete wrappers)",
  )
  println("")
  println("Options:")
  println(
    "  --include=PATTERN    Include files matching pattern (can be repeated)",
  )
  println(
    "  --exclude=PATTERN    Exclude files matching pattern (can be repeated)",
  )
  println("  --output=FILE, -o=   Output file path (default: stdout)")
  println("  --format=FORMAT      Output format: md, json, text (default: md)")
  println(
    "  --all                Include self-delegation and bare constructor wrappers",
  )
  println(
    "  --include-self       Include self.field.method delegation patterns",
  )
  println(
    "  --include-bare       Include bare constructor wrappers (no qualifier)",
  )
  println("  --help               Show this help message")
  println("")
  println("Examples:")
  println("  indexion plan unwrap --include='*.mbt' src/")
  println("  indexion plan unwrap --dry-run --include='*.mbt' src/")
  println(
    "  indexion plan unwrap --fix --include='*.mbt' --exclude='*_wbtest.mbt' src/",
  )
}

///|
/// Entry point: detect wrappers and report, preview, or apply fixes.
pub fn run(args : Array[String], start_idx : Int) -> Unit {
  let config = parse_args(args, start_idx)
  if config.show_help {
    show_help()
    return
  }
  if config.target_dir.length() == 0 {
    println("Error: Directory path required.")
    println("")
    show_help()
    return
  }
  let show_progress = config.output.length() > 0 || config.format != "json"
  let mode_label = match config.mode {
    "dry-run" => " --dry-run"
    "fix" => " --fix"
    _ => ""
  }
  if show_progress {
    println("=== indexion plan unwrap" + mode_label + " ===")
    println("Directory: " + config.target_dir)
    println("")
  }
  let registry = @kgf_features.load_registry(target_dir=config.target_dir)
  // [1/4] Collect files
  if show_progress {
    println("[1/4] Collecting files...")
  }
  let files = @common.collect_files(
    [config.target_dir],
    includes=config.includes,
    excludes=config.excludes,
  )
  if show_progress {
    println("      Found " + files.length().to_string() + " files")
  }
  if files.length() == 0 {
    println("No files found.")
    return
  }
  // [2/4] Detect wrappers
  if show_progress {
    println("[2/4] Detecting wrappers...")
  }
  let wrappers : Array[@kgf_features.ProxyFunction] = []
  for file in files {
    let (path, content) = file
    let detected = @kgf_features.detect_proxy_functions_from_file(
      content,
      path,
      registry,
      include_self_delegation=config.include_self,
      include_bare_constructors=config.include_bare,
    )
    for p in detected {
      wrappers.push(p)
    }
  }
  if show_progress {
    println(
      "      Found " + wrappers.length().to_string() + " wrappers to unwrap",
    )
  }
  if wrappers.length() == 0 {
    println("No wrappers found.")
    return
  }
  // For report mode, use the existing render path
  if config.mode == "report" {
    run_report(config, files, wrappers, registry, show_progress)
    return
  }
  // [3/4] Find call sites for each wrapper
  if show_progress {
    println("[3/4] Finding call sites...")
  }
  // Tokenize all files once
  let file_tokens : Map[String, Array[@kgf_types.Tok]] = {}
  let reg = match registry {
    Some(r) => r
    None => {
      println("Error: KGF registry not available.")
      return
    }
  }
  for file in files {
    let (path, content) = file
    let lang = match reg.detect_from_path(path) {
      Some(l) => l
      None => continue
    }
    let spec = match reg.get_spec(lang) {
      Some(s) => s
      None => continue
    }
    let lexer = @kgf_lexer.Lexer::new(spec.get_tokens())
    file_tokens.set(path, lexer.tokenize(content))
  }
  // For each wrapper, find call sites across all files
  let all_edits : Array[(String, Array[@kgf_features.UnwrapEdit])] = []
  // wrapper name → (delegate_target, def_start_line, def_end_line, def_file)
  let wrapper_defs : Array[(String, String, Int, Int, String)] = []
  for w in wrappers {
    let total_edits : Array[@kgf_features.UnwrapEdit] = []
    for file in files {
      let (path, _content) = file
      let tokens = match file_tokens.get(path) {
        Some(t) => t
        None => continue
      }
      let edits = @kgf_features.find_call_sites(
        w.name,
        w.delegate_target,
        tokens,
        path,
      )
      for e in edits {
        total_edits.push(e)
      }
    }
    all_edits.push((w.name, total_edits))
    wrapper_defs.push(
      (w.name, w.delegate_target, w.def_start_line, w.def_end_line, w.file),
    )
  }
  let mut total_replacements = 0
  for pair in all_edits {
    total_replacements += pair.1.length()
  }
  if show_progress {
    println(
      "      Found " + total_replacements.to_string() + " call sites to replace",
    )
  }
  // [4/4] Apply or preview
  if config.mode == "dry-run" {
    if show_progress {
      println("[4/4] Preview (dry-run)...")
      println("")
    }
    render_dry_run(wrappers, all_edits, wrapper_defs, files)
  } else {
    // --fix mode
    if show_progress {
      println("[4/4] Applying fixes...")
    }
    apply_fixes(all_edits, wrapper_defs, files, config.target_dir)
    if show_progress {
      println("")
      println(
        "Done: " +
        total_replacements.to_string() +
        " call sites replaced, " +
        wrappers.length().to_string() +
        " wrappers deleted.",
      )
    }
  }
}

///|
/// Report mode: existing behavior.
fn run_report(
  config : UnwrapConfig,
  files : Array[(String, String)],
  wrappers : Array[@kgf_features.ProxyFunction],
  registry : @kgf_registry.KGFRegistry?,
  show_progress : Bool,
) -> Unit {
  let candidates : Array[UnwrapEntry] = []
  let mut total_functions = 0
  for w in wrappers {
    candidates.push({
      file: w.file,
      line: w.line,
      name: w.name,
      delegate_target: w.delegate_target,
      params: w.params,
      delegate_args: w.delegate_args,
      all_forwarded: w.all_forwarded,
    })
  }
  // Count functions
  let reg = match registry {
    Some(r) => r
    None => {
      total_functions = 0
      let plan = build_plan(config, candidates, files.length(), total_functions)
      output_plan(config, plan, show_progress)
      return
    }
  }
  for file in files {
    let (path, content) = file
    let lang = match reg.detect_from_path(path) {
      Some(l) => l
      None => continue
    }
    let spec = match reg.get_spec(lang) {
      Some(s) => s
      None => continue
    }
    let lexer = @kgf_lexer.Lexer::new(spec.get_tokens())
    let tokens = lexer.tokenize(content)
    let funcs = @kgf_features.extract_functions(tokens, path)
    total_functions += funcs.length()
  }
  let plan = build_plan(config, candidates, files.length(), total_functions)
  output_plan(config, plan, show_progress)
}

///|
fn build_plan(
  config : UnwrapConfig,
  candidates : Array[UnwrapEntry],
  file_count : Int,
  func_count : Int,
) -> UnwrapPlanJSON {
  {
    config: {
      target_dir: config.target_dir,
      includes: config.includes,
      excludes: config.excludes,
    },
    candidates,
    summary: {
      total_files_scanned: file_count,
      total_functions_scanned: func_count,
      unwrap_count: candidates.length(),
    },
  }
}

///|
fn output_plan(
  config : UnwrapConfig,
  plan : UnwrapPlanJSON,
  show_progress : Bool,
) -> Unit {
  if show_progress {
    println("[3/3] Rendering " + config.format + " output...")
    println("")
  }
  let output_content = match config.format {
    "json" => render_json(plan)
    "text" => render_text(plan)
    _ => render_markdown(plan)
  }
  if config.output.length() > 0 {
    try {
      @fs.write_string_to_file(config.output, output_content)
      println("Unwrap report written to: " + config.output)
    } catch {
      e => println("Error writing file: " + e.to_string())
    }
  } else {
    println(output_content)
  }
}

///|
/// Render dry-run preview.
fn render_dry_run(
  wrappers : Array[@kgf_features.ProxyFunction],
  all_edits : Array[(String, Array[@kgf_features.UnwrapEdit])],
  wrapper_defs : Array[(String, String, Int, Int, String)],
  files : Array[(String, String)],
) -> Unit {
  // Build file contents map for showing context
  let file_contents : Map[String, String] = {}
  for f in files {
    file_contents.set(f.0, f.1)
  }
  for i, w in wrappers {
    let (name, edits) = all_edits[i]
    let (_name2, delegate, start_line, end_line, def_file) = wrapper_defs[i]
    println(
      "[" +
      (i + 1).to_string() +
      "/" +
      wrappers.length().to_string() +
      "] " +
      w.file +
      ":" +
      w.line.to_string() +
      " " +
      name +
      " -> " +
      delegate,
    )
    println("")
    // Show call sites
    if edits.length() > 0 {
      println("  Call sites (" + edits.length().to_string() + " replacements):")
      for edit in edits {
        println(
          "    " +
          edit.file +
          ":" +
          edit.line.to_string() +
          "   " +
          edit.old_text +
          "(...) -> " +
          edit.new_text +
          "(...)",
        )
      }
    } else {
      println("  Call sites: none found")
    }
    println("")
    // Show definition to delete
    println(
      "  Delete definition: " +
      def_file +
      ":" +
      start_line.to_string() +
      "-" +
      end_line.to_string(),
    )
    match file_contents.get(def_file) {
      Some(content) => {
        let lines = @common.split_lines(content)
        for li = start_line - 1
            li < end_line && li < lines.length()
            li = li + 1 {
          println("    - " + lines[li])
        }
      }
      None => ()
    }
    println("")
  }
  // Summary
  let mut total = 0
  for pair in all_edits {
    total += pair.1.length()
  }
  println(
    "Total: " +
    total.to_string() +
    " replacements + " +
    wrappers.length().to_string() +
    " deletions",
  )
}

///|
/// Apply fixes: replace call sites and delete wrapper definitions.
fn apply_fixes(
  all_edits : Array[(String, Array[@kgf_features.UnwrapEdit])],
  wrapper_defs : Array[(String, String, Int, Int, String)],
  files : Array[(String, String)],
  target_dir : String,
) -> Unit {
  // Build file contents map
  let file_contents : Map[String, String] = {}
  for f in files {
    file_contents.set(f.0, f.1)
  }
  // Collect all edits per file
  let edits_by_file : Map[String, Array[@kgf_features.UnwrapEdit]] = {}
  for pair in all_edits {
    let edits = pair.1
    for edit in edits {
      match edits_by_file.get(edit.file) {
        Some(arr) => arr.push(edit)
        None => edits_by_file.set(edit.file, [edit])
      }
    }
  }
  // Collect deletions per file (def_start_line, def_end_line) sorted descending
  let deletions_by_file : Map[String, Array[(Int, Int)]] = {}
  for def in wrapper_defs {
    let (_name, _target, start, end, file) = def
    match deletions_by_file.get(file) {
      Some(arr) => arr.push((start, end))
      None => deletions_by_file.set(file, [(start, end)])
    }
  }
  // Sort deletions descending by start_line (delete from bottom up)
  for _, dels in deletions_by_file {
    dels.sort_by(fn(a, b) { b.0 - a.0 })
  }
  // Collect all affected files
  let affected_files : Map[String, Bool] = {}
  for _, edits in edits_by_file {
    for edit in edits {
      affected_files.set(edit.file, true)
    }
  }
  for _, dels in deletions_by_file {
    ignore(dels)
  }
  for file, _ in deletions_by_file {
    affected_files.set(file, true)
  }
  // Apply edits to each affected file
  for file, _ in affected_files {
    let content = match file_contents.get(file) {
      Some(c) => c
      None => continue
    }
    // Step 1: Apply call site replacements (character offset based)
    let mut modified = match edits_by_file.get(file) {
      Some(edits) => @kgf_features.apply_edits(content, edits)
      None => content
    }
    // Step 2: Delete wrapper definitions (line based, bottom-up)
    match deletions_by_file.get(file) {
      Some(dels) =>
        for del in dels {
          modified = @kgf_features.delete_lines(modified, del.0, del.1)
        }
      None => ()
    }
    // Write back (reconstruct full path from target_dir + relative display name)
    let full_path = @common.normalize_path(target_dir) + "/" + file
    try {
      @fs.write_string_to_file(full_path, modified)
      println("  Updated: " + file)
    } catch {
      e => println("  Error writing " + file + ": " + e.to_string())
    }
  }
}
