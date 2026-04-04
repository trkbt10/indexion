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
pub(all) struct UnwrapConfig {
  target_dir : String
  includes : Array[String]
  excludes : Array[String]
  output : String
  format : String
  include_self : Bool
  include_bare : Bool
  mode : String // "report", "dry-run", "fix"
  specs_dir : String // KGF specs directory
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
    specs_dir: "kgfs",
  }
}

///|
/// Create UnwrapConfig from argparse matches.
pub fn UnwrapConfig::from_matches(matches : @argparse.Matches) -> UnwrapConfig {
  let includes = match matches.values.get("include") {
    Some(arr) => arr
    _ => []
  }
  let excludes = match matches.values.get("exclude") {
    Some(arr) => arr
    _ => []
  }
  let output = match matches.values.get("output") {
    Some(arr) => if arr.length() > 0 { arr[0] } else { "" }
    _ => ""
  }
  let format = match matches.values.get("format") {
    Some(arr) => if arr.length() > 0 { arr[0] } else { "md" }
    _ => "md"
  }
  let specs_dir = match matches.values.get("specs-dir") {
    Some(arr) => if arr.length() > 0 { arr[0] } else { "kgfs" }
    _ => "kgfs"
  }
  let target_dir = match matches.values.get("directory") {
    Some(arr) => if arr.length() > 0 { arr[0] } else { "" }
    _ => ""
  }
  // Handle --all flag: sets both include_self and include_bare
  let all_flag = matches.flags.get("all").unwrap_or(false)
  let include_self = all_flag ||
    matches.flags.get("include-self").unwrap_or(false)
  let include_bare = all_flag ||
    matches.flags.get("include-bare").unwrap_or(false)
  // Handle mode flags: --dry-run and --fix
  let mode = if matches.flags.get("fix").unwrap_or(false) {
    "fix"
  } else if matches.flags.get("dry-run").unwrap_or(false) {
    "dry-run"
  } else {
    "report"
  }
  {
    target_dir,
    includes,
    excludes,
    output,
    format,
    include_self,
    include_bare,
    mode,
    specs_dir,
  }
}

///|
/// Define the unwrap command for argparse.
pub fn command() -> @argparse.Command {
  @argparse.Command(
    "unwrap",
    about="Detect and remove unnecessary wrapper functions",
    options=[
      @argparse.OptionArg("include", action=Append, about=@help.include_pattern),
      @argparse.OptionArg("exclude", action=Append, about=@help.exclude_pattern),
      @argparse.OptionArg("output", short='o', about=@help.output),
      @argparse.OptionArg("format", about="Output format: md, json, text", default_values=[
        "md",
      ]),
      @argparse.OptionArg("specs-dir", about=@help.specs_dir, default_values=[
        "kgfs",
      ]),
    ],
    flags=[
      @argparse.FlagArg(
        "all",
        about="Include self-delegation and bare constructor wrappers",
      ),
      @argparse.FlagArg(
        "include-self",
        about="Include self.field.method delegation patterns",
      ),
      @argparse.FlagArg(
        "include-bare",
        about="Include bare constructor wrappers (no qualifier)",
      ),
      @argparse.FlagArg("dry-run", about="Preview edits without applying"),
      @argparse.FlagArg(
        "fix",
        about="Apply edits (replace call sites, delete wrappers)",
      ),
    ],
    positionals=[
      @argparse.PositionArg(
        "directory",
        num_args=@argparse.ValueRange(lower=1),
        about="Target directory to analyze",
      ),
    ],
  )
}

///|
/// Shared scan: collect files, detect wrappers.
fn collect_wrappers(
  config : UnwrapConfig,
) -> (
  Array[(String, String)],
  Array[@kgf_features.ProxyFunction],
  @kgf_registry.KGFRegistry?,
)? {
  if config.target_dir.length() == 0 {
    return None
  }
  let registry = @kgf_features.load_registry(
    specs_dir=config.specs_dir,
    target_dir=config.target_dir,
  )
  let files = @common.collect_files(
    [config.target_dir],
    includes=config.includes,
    excludes=config.excludes,
  )
  if files.length() == 0 {
    return None
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
  if wrappers.length() == 0 {
    return None
  }
  Some((files, wrappers, registry))
}

///|
/// Build candidates + count functions from wrappers (shared by report paths).
fn build_report_plan(
  config : UnwrapConfig,
  files : Array[(String, String)],
  wrappers : Array[@kgf_features.ProxyFunction],
  registry : @kgf_registry.KGFRegistry?,
) -> UnwrapPlanJSON {
  let candidates : Array[UnwrapEntry] = []
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
  let mut total_functions = 0
  match registry {
    Some(reg) =>
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
        let funcs = @kgf_features.extract_functions(tokens, path, spec~)
        total_functions += funcs.length()
      }
    None => ()
  }
  build_plan(config, candidates, files.length(), total_functions)
}

///|
/// Core unwrap analysis (report mode). Returns rendered output or None.
pub fn run_to_string(config : UnwrapConfig) -> String? {
  let (files, wrappers, registry) = match collect_wrappers(config) {
    Some(r) => r
    None => return None
  }
  let plan = build_report_plan(config, files, wrappers, registry)
  Some(
    match config.format {
      "json" => render_json(plan)
      "text" => render_text(plan)
      _ => render_markdown(plan)
    },
  )
}

///|
/// Entry point using argparse matches.
pub fn run_matches(matches : @argparse.Matches) -> Unit {
  let config = UnwrapConfig::from_matches(matches)
  run_with_config(config)
}

///|
/// Entry point with a pre-built configuration.
fn run_with_config(config : UnwrapConfig) -> Unit {
  if config.target_dir.length() == 0 {
    println(@help.dir_required)
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
  let (files, wrappers, registry) = match collect_wrappers(config) {
    Some(r) => r
    None => {
      println("No wrappers found.")
      return
    }
  }
  if show_progress {
    println(
      "      Found " +
      files.length().to_string() +
      " files, " +
      wrappers.length().to_string() +
      " wrappers",
    )
  }
  // For report mode, delegate to run_to_string (SoT)
  if config.mode == "report" {
    match run_to_string(config) {
      Some(output) =>
        @common.write_output(config.output, output, label="Unwrap report")
      None => println("No wrappers found.")
    }
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
      let s = match reg.detect_from_path(path) {
        Some(lang) =>
          match reg.get_spec(lang) {
            Some(s) => s
            None => continue
          }
        None => continue
      }
      let edits = @kgf_features.find_call_sites(
        w.name,
        w.delegate_target,
        tokens,
        path,
        spec=s,
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
