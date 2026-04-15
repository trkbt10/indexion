///|
/// # indexion wiki hook
///
/// Manage VCS hooks for automatic wiki maintenance.
///
/// Hooks are non-destructive: they append to existing hook files using
/// comment markers, so other tools can coexist. Uninstall cleanly removes
/// only the indexion section. VCS detection is automatic (Git, Jujutsu);
/// use --vcs-dir to override the repository root.
///
/// Comment markers are parsed with the KGF shell lexer — no hand-rolled
/// string scanning. Adding support for a new VCS requires only adding an
/// entry to `src/vcs/vcs.mbt`.
///
/// ## Installed hooks
///
/// - `post-commit`   — runs `indexion wiki pages ingest` after every commit
/// - `post-checkout` — runs `indexion wiki pages ingest` after branch switches
///                     (Git only; for Jujutsu this maps to `post-new-working-copy`)
///
/// ## Subcommands
///
/// - `install`   - Install VCS hooks
/// - `uninstall` - Remove indexion VCS hooks
/// - `status`    - Show whether hooks are currently installed

///|
/// Comment marker that opens the indexion-managed section in hook files.
/// Parsed by the KGF shell lexer as a `Comment` token.
let hook_start_marker : String = "# indexion-hook-start"

///|
/// Comment marker that closes the indexion-managed section.
let hook_end_marker : String = "# indexion-hook-end"

///|
/// Hooks managed by indexion, per VCS.
/// Each entry is (hook_name, section_generator).
/// The section generator receives no arguments — it returns the shell snippet.
let managed_hooks : Array[(String, () -> String)] = [
  (post_commit_hook_name(), build_post_commit_script),
  (post_checkout_hook_name(), build_post_checkout_script),
]

///|
fn post_commit_hook_name() -> String {
  "post-commit"
}

///|
fn post_checkout_hook_name() -> String {
  "post-checkout"
}

///|
pub fn command() -> @argparse.Command {
  @argparse.Command(
    "hook",
    about="Manage VCS hooks for wiki maintenance",
    subcommand_required=true,
    subcommands=[install_command(), uninstall_command(), status_command()],
  )
}

///|
pub async fn dispatch(matches : @argparse.Matches) -> Unit {
  guard matches.subcommand is Some((name, sub)) else { return }
  match name {
    "install" => run_install(sub)
    "uninstall" => run_uninstall(sub)
    "status" => run_status(sub)
    _ => ()
  }
}

// --- Subcommand definitions ---

///|
fn install_command() -> @argparse.Command {
  @argparse.Command("install", about="Install VCS hooks", options=[
    @argparse.OptionArg(
      "vcs-dir",
      about="Repository root (default: auto-detect from cwd)",
      default_values=[],
    ),
  ])
}

///|
fn uninstall_command() -> @argparse.Command {
  @argparse.Command(
    "uninstall",
    about="Remove indexion sections from VCS hooks",
    options=[
      @argparse.OptionArg(
        "vcs-dir",
        about="Repository root (default: auto-detect from cwd)",
        default_values=[],
      ),
    ],
  )
}

///|
fn status_command() -> @argparse.Command {
  @argparse.Command(
    "status",
    about="Show whether indexion VCS hooks are installed",
    options=[
      @argparse.OptionArg(
        "vcs-dir",
        about="Repository root (default: auto-detect from cwd)",
        default_values=[],
      ),
    ],
  )
}

// --- Subcommand handlers ---

///|
async fn run_install(matches : @argparse.Matches) -> Unit {
  let (vcs, hooks_dir) = match resolve_vcs(matches) {
    Some(pair) => pair
    None => return
  }
  @config.ensure_dir_recursive(hooks_dir)
  println("VCS: " + @debug.to_string(vcs))
  for entry in managed_hooks {
    let (hook_name, build_section) = entry
    let result = install_hook(hooks_dir, hook_name, build_section())
    println(hook_name + ": " + result)
  }
}

///|
fn run_uninstall(matches : @argparse.Matches) -> Unit {
  let (vcs, hooks_dir) = match resolve_vcs(matches) {
    Some(pair) => pair
    None => return
  }
  println("VCS: " + @debug.to_string(vcs))
  for entry in managed_hooks {
    let (hook_name, _) = entry
    let result = uninstall_hook(hooks_dir, hook_name)
    println(hook_name + ": " + result)
  }
}

///|
fn run_status(matches : @argparse.Matches) -> Unit {
  let (vcs, hooks_dir) = match resolve_vcs(matches) {
    Some(pair) => pair
    None => return
  }
  println("VCS: " + @debug.to_string(vcs))
  for entry in managed_hooks {
    let (hook_name, _) = entry
    let status = hook_status(hooks_dir, hook_name)
    println(hook_name + ": " + status)
  }
}

// --- Hook script generators ---

///|
/// Runs `indexion wiki pages ingest` for every commit.
fn build_post_commit_script() -> String {
  hook_start_marker +
  "\n" +
  "indexion wiki pages ingest --format=md > /dev/null 2>&1 || true\n" +
  hook_end_marker +
  "\n"
}

///|
/// Runs `indexion wiki pages ingest` only on branch switches (not file checkouts).
/// In POSIX shell hooks, $3 == 1 signals a branch switch; $3 == 0 is a file checkout.
fn build_post_checkout_script() -> String {
  hook_start_marker +
  "\n" +
  "if [ \"$3\" = \"1\" ]; then\n" +
  "  indexion wiki pages ingest --format=md > /dev/null 2>&1 || true\n" +
  "fi\n" +
  hook_end_marker +
  "\n"
}

// --- Install / uninstall / status ---

///|
/// Install an indexion section into a hook file.
/// - Missing file: create with `#!/bin/sh` shebang, set executable.
/// - File exists, already has marker: report "already installed".
/// - File exists, no marker: append the section.
async fn install_hook(
  hooks_dir : String,
  hook_name : String,
  section : String,
) -> String {
  let hook_path = hooks_dir + "/" + hook_name
  if @fs.path_exists(hook_path) {
    let existing = @fs.read_file_to_string(hook_path) catch {
      e => return "error reading hook: " + @debug.to_string(e)
    }
    if section_installed(existing) {
      return "already installed"
    }
    let sep = if existing.has_suffix("\n") { "" } else { "\n" }
    @fs.write_string_to_file(hook_path, existing + sep + section) catch {
      e => return "error writing hook: " + @debug.to_string(e)
    }
    return "installed (appended to existing hook)"
  }
  @fs.write_string_to_file(hook_path, "#!/bin/sh\n" + section) catch {
    e => return "error writing hook: " + @debug.to_string(e)
  }
  @platform.make_executable(hook_path)
  "installed"
}

///|
/// Remove the indexion-managed section from a hook file.
/// If only a shebang remains, the file is deleted.
fn uninstall_hook(hooks_dir : String, hook_name : String) -> String {
  let hook_path = hooks_dir + "/" + hook_name
  if !@fs.path_exists(hook_path) {
    return "not installed"
  }
  let existing = @fs.read_file_to_string(hook_path) catch {
    e => return "error reading hook: " + @debug.to_string(e)
  }
  if !section_installed(existing) {
    return "not installed"
  }
  let stripped = remove_hook_section(existing)
  if is_shebang_only(stripped) {
    @fs.remove_file(hook_path) catch {
      e => return "error removing hook file: " + @debug.to_string(e)
    }
    return "uninstalled (hook file removed)"
  }
  @fs.write_string_to_file(hook_path, stripped) catch {
    e => return "error writing hook: " + @debug.to_string(e)
  }
  "uninstalled"
}

///|
/// Return "installed" or "not installed" for a hook file.
fn hook_status(hooks_dir : String, hook_name : String) -> String {
  let hook_path = hooks_dir + "/" + hook_name
  if !@fs.path_exists(hook_path) {
    return "not installed"
  }
  let content = @fs.read_file_to_string(hook_path) catch {
    _ => return "not installed"
  }
  if section_installed(content) {
    "installed"
  } else {
    "not installed"
  }
}

// --- KGF-based section detection and removal ---
//
// The shell KGF spec defines a `Comment` token: /#[^\r\n]*/
// We use the lexer to find comment tokens whose text equals one of the
// two markers, and use their `pos` and `text.length()` to slice the string.
// This means new shell syntax never breaks our scanner — the KGF grammar
// handles quoting, escaping, and multi-line strings correctly.

///|
/// Return true if `content` already contains the indexion start marker.
/// Uses the KGF shell lexer to identify comment tokens precisely.
fn section_installed(content : String) -> Bool {
  find_marker_range(content) is Some(_)
}

///|
/// Remove the indexion-managed section from `content` using the KGF shell
/// lexer to locate the marker comment tokens.
/// Returns `content` unchanged if no markers are found.
fn remove_hook_section(content : String) -> String {
  let (section_start, section_end) = match find_marker_range(content) {
    Some(pair) => pair
    None => return content
  }
  // Also absorb the leading newline separator that install_hook may have added.
  let cut_start = if section_start > 0 && content[section_start - 1] == '\n' {
    section_start - 1
  } else {
    section_start
  }
  content[:cut_start].to_string() + content[section_end:].to_string()
}

///|
/// Locate the start/end character positions of the indexion section.
///
/// Scans KGF `Comment` tokens for the start and end markers.
/// Returns `Some((section_start, section_end))` where:
///   - `section_start` is the position of the first character of the start marker line
///   - `section_end`   is the position just after the end marker line (newline included)
fn find_marker_range(content : String) -> (Int, Int)? {
  let tokens = shell_comment_tokens(content)
  let mut start_pos : Int = -1
  let mut end_pos : Int = -1
  for tok in tokens {
    if tok.text == hook_start_marker {
      start_pos = tok.pos
    } else if tok.text == hook_end_marker && start_pos >= 0 {
      // end_pos: just past the end-marker text, plus the trailing newline if present
      let after = tok.pos + tok.text.length()
      end_pos = if after < content.length() && content[after] == '\n' {
        after + 1
      } else {
        after
      }
      break
    }
  }
  if start_pos < 0 || end_pos < 0 {
    None
  } else {
    Some((start_pos, end_pos))
  }
}

///|
/// Tokenize `content` as a POSIX shell script using the KGF shell lexer
/// and return only the `Comment` tokens.
fn shell_comment_tokens(content : String) -> Array[@kgf_types.Tok] {
  let lexer = @kgf_lexer.Lexer::new(shell_token_defs())
  let all_tokens = lexer.tokenize(content)
  let comments : Array[@kgf_types.Tok] = []
  for tok in all_tokens {
    if tok.kind == "Comment" {
      comments.push(tok)
    }
  }
  comments
}

///|
/// Token definitions for the KGF shell lexer — mirrors `kgfs/dsl/shell.kgf`.
/// Kept in sync with the KGF spec so that the lexer correctly handles quoting
/// and escaping before we scan for marker comments.
fn shell_token_defs() -> Array[@kgf_types.TokenDef] {
  [
    @kgf_types.TokenDef::new("SKIP_WS", "[ \\t]+", skip=true),
    @kgf_types.TokenDef::new("NL", "\\r?\\n"),
    @kgf_types.TokenDef::new("Comment", "#[^\\r\\n]*"),
    @kgf_types.TokenDef::new("KW_export", "export\\b"),
    @kgf_types.TokenDef::new("KW_if", "if\\b"),
    @kgf_types.TokenDef::new("KW_then", "then\\b"),
    @kgf_types.TokenDef::new("KW_fi", "fi\\b"),
    @kgf_types.TokenDef::new("KW_for", "for\\b"),
    @kgf_types.TokenDef::new("KW_do", "do\\b"),
    @kgf_types.TokenDef::new("KW_done", "done\\b"),
    @kgf_types.TokenDef::new("Assign", "="),
    @kgf_types.TokenDef::new(
      "StringLit", "\"([^\"\\\\]|\\\\.)*\"|'([^'\\\\]|\\\\.)*'",
    ),
    @kgf_types.TokenDef::new("Ident", "[A-Za-z_][A-Za-z0-9_]*"),
    @kgf_types.TokenDef::new("Word", "[^\\s#]+"),
  ]
}

///|
/// Return true if `content` has no meaningful content beyond an optional shebang.
fn is_shebang_only(content : String) -> Bool {
  let lines = content.split("\n")
  let mut meaningful = 0
  for line in lines {
    let trimmed = line.trim()
    if trimmed.length() == 0 {
      continue
    }
    if trimmed.has_prefix("#!") {
      continue
    }
    meaningful += 1
  }
  meaningful == 0
}

// --- VCS resolution ---

///|
/// Resolve the VCS type and hooks directory from CLI matches or auto-detection.
/// Prints an error and returns None on failure.
fn resolve_vcs(matches : @argparse.Matches) -> (@vcs.VCS, String)? {
  let explicit = @common.get_option(matches, "vcs-dir", "")
  let start = if explicit.length() > 0 { explicit } else { "." }
  match @vcs.detect(start) {
    Some((vcs, root)) => {
      let dir = @vcs.hooks_dir(vcs, root)
      Some((vcs, dir))
    }
    None => {
      let hint = if explicit.length() > 0 {
        " (searched from: " + explicit + ")"
      } else {
        " Use --vcs-dir to specify the repository root."
      }
      println("Error: No supported VCS repository found." + hint)
      None
    }
  }
}
