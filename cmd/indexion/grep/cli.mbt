///|
/// # indexion grep
///
/// KGF-aware token pattern search across source files.
///
/// ## Overview
///
/// Searches source files using KGF token patterns instead of raw text regex.
/// Token-level matching enables structural searches like "pub fn without doc
/// comment" or "nested for loops" that are impossible with text-based grep.
///
/// ## Usage
///
/// ```bash
/// indexion grep [options] <pattern> [paths...]
/// ```
///
/// ## Pattern Syntax
///
/// Patterns are space-separated token matchers:
///
/// - `KW_fn` — match token kind exactly
/// - `Ident:foo` — match kind and text (`kind:text`)
/// - `*` — match any single token
/// - `...` — match zero or more tokens (non-greedy)
/// - `!KW_pub` — negation (any token except this kind)
///
/// ## Options
///
/// | Option | Description | Default |
/// |--------|-------------|---------|
/// | `--include=GLOB` | Include file pattern | (all) |
/// | `--exclude=GLOB` | Exclude file pattern | |
/// | `--kind=KIND` | List all tokens of this kind | |
/// | `--undocumented` | Find pub declarations without doc comments | false |
/// | `--context=N` | Lines of context around matches | 0 |
/// | `--count` | Show match count per file only | false |
/// | `--files` | Show matching file paths only | false |
///
/// ## Examples
///
/// ```bash
/// # Find all pub fn declarations
/// indexion grep "KW_pub KW_fn Ident" src/
///
/// # Find nested for loops (potential O(n²))
/// indexion grep "KW_for ... KW_for" src/
///
/// # Find undocumented public declarations
/// indexion grep --undocumented src/
///
/// # List all struct names
/// indexion grep --kind=TypeIdent "KW_struct TypeIdent" src/
///
/// # Find functions named "sort"
/// indexion grep "KW_fn Ident:sort" src/
/// ```

///|
/// CLI configuration for grep.
pub struct GrepConfig {
  pattern : String
  paths : Array[String]
  includes : Array[String]
  excludes : Array[String]
  specs_dir : String
  semantic : String
  undocumented : Bool
  context_lines : Int
  count_only : Bool
  files_only : Bool
}

///|
pub fn GrepConfig::default() -> GrepConfig {
  {
    pattern: "",
    paths: [],
    includes: [],
    excludes: [],
    specs_dir: "kgfs",
    semantic: "",
    undocumented: false,
    context_lines: 0,
    count_only: false,
    files_only: false,
  }
}

///|
pub fn GrepConfig::from_matches(matches : @argparse.Matches) -> GrepConfig {
  let get_str = fn(key : String, default_ : String) -> String {
    match matches.values.get(key) {
      Some(arr) => if arr.length() > 0 { arr[0] } else { default_ }
      None => default_
    }
  }
  let get_flag = fn(key : String, default_ : Bool) -> Bool {
    match matches.flags.get(key) {
      Some(v) => v
      None => default_
    }
  }
  let get_all = fn(key : String) -> Array[String] {
    match matches.values.get(key) {
      Some(arr) => arr
      None => []
    }
  }
  {
    pattern: get_str("pattern", ""),
    paths: get_all("paths"),
    includes: get_all("include"),
    excludes: get_all("exclude"),
    specs_dir: get_str("specs-dir", "kgfs"),
    semantic: get_str("semantic", ""),
    undocumented: get_flag("undocumented", false),
    context_lines: @common.parse_int(get_str("context", "0")),
    count_only: get_flag("count", false),
    files_only: get_flag("files", false),
  }
}

///|
pub fn command() -> @argparse.Command {
  @argparse.Command::new(
    "grep",
    about="KGF-aware token pattern search",
    flags=[
      @argparse.FlagArg::new(
        "undocumented",
        about="Find pub declarations without doc comments",
      ),
      @argparse.FlagArg::new("count", about="Show match count per file only"),
      @argparse.FlagArg::new("files", about="Show matching file paths only"),
    ],
    options=[
      @argparse.OptionArg(
        "include",
        action=Append,
        about="Include file glob pattern (repeatable)",
      ),
      @argparse.OptionArg(
        "exclude",
        action=Append,
        about="Exclude file glob pattern (repeatable)",
      ),
      @argparse.OptionArg(
        "semantic",
        about="Semantic query: proxy, short:N, long:N, params-gte:N, name:substr, undocumented",
      ),
      @argparse.OptionArg(
        "specs-dir",
        about="KGF specs directory",
        default_values=["kgfs"],
      ),
      @argparse.OptionArg(
        "context",
        about="Lines of context around matches",
        default_values=["0"],
      ),
    ],
    positionals=[
      @argparse.PositionArg(
        "pattern",
        about="Token pattern (space-separated token matchers, or empty with --undocumented)",
      ),
      @argparse.PositionArg(
        "paths",
        about="Paths to search",
        num_args=@argparse.ValueRange(lower=0),
      ),
    ],
  )
}

///|
pub fn run_matches(matches : @argparse.Matches) -> Unit {
  let config = GrepConfig::from_matches(matches)
  let paths = if config.paths.length() == 0 { ["."] } else { config.paths }
  // Handle --semantic queries
  if config.semantic.length() > 0 {
    match parse_semantic_query(config.semantic) {
      Some(query) => {
        run_semantic_search(paths, query, config)
        return
      }
      None => {
        println("Error: Unknown semantic query '" + config.semantic + "'")
        println(
          "Available: proxy, short:N, long:N, params-gte:N, name:substr, undocumented",
        )
        return
      }
    }
  }
  if config.undocumented {
    run_semantic_search(paths, Undocumented, config)
    return
  }
  if config.pattern.length() == 0 {
    println("Error: Pattern required (or use --undocumented / --semantic=QUERY)")
    return
  }
  let matchers = parse_pattern(config.pattern)
  if matchers.length() == 0 {
    println("Error: Empty pattern")
    return
  }
  run_pattern_search(paths, matchers, config)
}
