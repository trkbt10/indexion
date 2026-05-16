// # transpile-todo-app integration test runner
//
// Drives the lift/lower transpile engine against the TS todo-app fixture
// and aggregates the resulting drift signals into a deterministic snapshot.
//
// What this test verifies:
//
//  1. The engine accepts every (source, target) pair without per-pair code.
//  2. For each emitted file, the count of `@@UNRESOLVED@@<kind>` markers
//     matches the snapshot.
//  3. The lifted IR rule histogram matches — i.e. the lift specs project
//     KGF events into canonical IR rules (IRStruct, IRFn, IREnum, ...).
//
// The snapshot also encodes the *kind* of every unresolved marker so a
// human reading the diff can attribute each gap to one of:
//
//   * KGF analysis gap   — KGF spec doesn't extract enough structure
//   * Mapping gap         — transpile spec format can't express the rule
//   * Engine gap          — engine code can't represent the operation
//   * Conversion gap      — source feature has no target equivalent
//
// See `kind_diagnosis()` below for the per-kind classification.

///|
/// Path to the typescript SoT under fixtures/.
let ts_src_root : String = "fixtures/transpile/todo-app/cli/typescript/src"

///|
/// One per-file drift entry in the snapshot.
priv struct FileDrift {
  file : String
  ir_event_count : Int
  unresolved_total : Int
  unresolved_kinds : Array[(String, Int)]
  /// Number of KGF-check errors reported when the emitted target code is
  /// parsed under the target language's KGF spec. Zero = the emitted file
  /// is at least syntactically valid as far as KGF can tell. Non-zero =
  /// the transpile produced something the target's KGF rejects.
  emit_parse_errors : Int
  /// Exit code from the target language's actual compiler (single-file
  /// syntax-only mode). 0 = compiler accepts the file. Non-zero or absent =
  /// either the compiler rejects the file or the compiler is not installed
  /// in this environment. This is the strongest verification we run from
  /// inside the test — it confirms the transpile output is real code, not
  /// just KGF-shaped text.
  compile_exit_code : Int
} derive(ToJson)

///|
/// One per-target snapshot entry.
priv struct TargetSnapshot {
  target_lang : String
  source_lang : String
  totals : Map[String, Int]
  ir_rule_histogram : Array[(String, Int)]
  files : Array[FileDrift]
  unresolved_diagnosis : Array[(String, String)]
} derive(ToJson)

///|
/// Discover all .ts files under `ts_src_root`.
fn list_ts_files() -> Array[String] raise {
  let out : Array[String] = []
  collect_ts_files(ts_src_root, out)
  out.sort()
  out
}

///|
fn collect_ts_files(dir : String, out : Array[String]) -> Unit raise {
  let entries = @fs.read_dir(dir) catch { _ => return }
  for entry in entries {
    let path = dir + "/" + entry
    let is_dir = @fs.is_dir(path) catch { _ => false }
    if is_dir {
      collect_ts_files(path, out)
    } else if path.has_suffix(".ts") {
      out.push(path)
    }
  }
}

///|
/// Count occurrences of "@@UNRESOLVED@@<word>" in `code`. Returns a sorted
/// (kind, count) array.
fn count_unresolved_kinds(code : String) -> Array[(String, Int)] {
  let counts : Map[String, Int] = {}
  let chars = code.to_array()
  let marker = "@@UNRESOLVED@@"
  let marker_len = marker.length()
  let mut i = 0
  while i + marker_len <= chars.length() {
    if code[i:i + marker_len].to_owned() == marker {
      let mut j = i + marker_len
      while j < chars.length() && is_kind_char(chars[j]) {
        j = j + 1
      }
      if j > i + marker_len {
        let kind = code[i + marker_len:j].to_owned()
        counts[kind] = counts.get(kind).unwrap_or(0) + 1
      }
      i = j
    } else {
      i = i + 1
    }
  }
  let arr : Array[(String, Int)] = []
  for entry in counts {
    arr.push((entry.0, entry.1))
  }
  arr.sort_by(fn(a, b) {
    if a.1 != b.1 {
      b.1.compare(a.1)
    } else {
      a.0.compare(b.0)
    }
  })
  arr
}

///|
fn is_kind_char(c : Char) -> Bool {
  (c >= 'a' && c <= 'z') ||
  (c >= 'A' && c <= 'Z') ||
  (c >= '0' && c <= '9') ||
  c == '_'
}

///|
/// Classify each unresolved-marker kind. The classification answers the
/// user's question: is the gap a KGF analysis problem, a mapping
/// limitation, an engine limitation, or a real cross-language conversion
/// problem? See `kind_diagnosis()` for the rationale.
fn kind_diagnosis() -> Array[(String, String)] {
  let pairs : Array[(String, String)] = []
  pairs.push(
    (
      "id_text",
      "MAPPING — KGF DOES extract the id (it's on a sibling rule like " +
      "InterfaceHeader/StructHeader); spec format has no `id_from: <SiblingRule>.<label>` clause.",
    ),
  )
  pairs.push(
    (
      "rhs",
      "MAPPING — TypeDecl event carries the full text (e.g. `type X = a|b;`); " +
      "spec format has no substring/regex extraction operator.",
    ),
  )
  pairs.push(
    (
      "variants",
      "MAPPING — variant tokens ARE in the source events (string-literal-union); " +
      "spec format has no inner-event aggregation operator.",
    ),
  )
  pairs.push(
    (
      "fields",
      "MAPPING — KGF emits PropertySig children of InterfaceDecl; " +
      "spec format has no inner-event aggregation operator.",
    ),
  )
  pairs.push(
    (
      "params",
      "MAPPING — KGF emits Param children of FunctionDecl; " +
      "spec format has no inner-event aggregation operator.",
    ),
  )
  pairs.push(
    (
      "return",
      "KGF — TypeScript KGF does not label a FunctionDecl's return type as a " +
      "named edge. The Type event near the body is unattributed.",
    ),
  )
  pairs.push(
    (
      "body",
      "ENGINE+CONVERSION — `body` label on FunctionDecl event is just the " +
      "closing brace token. The full body text lives on `body_text`; the " +
      "lower template should reference that. Even with body_text, expression " +
      "syntax is the part that genuinely cannot be cross-language transpiled.",
    ),
  )
  pairs.push(
    (
      "body_text",
      "CONVERSION — full body text of source function. No mechanical mapping " +
      "to target body exists; this is the genuine cross-language gap.",
    ),
  )
  pairs.push(
    (
      "Any", "CONVERSION — TypeScript `any` has no canonical equivalent. Marked at lift time.",
    ),
  )
  pairs.push(
    (
      "Unknown", "CONVERSION — TypeScript `unknown` has no canonical equivalent. Marked at lift time.",
    ),
  )
  pairs.push(
    (
      "type_wrap",
      "MAPPING — Python's generic syntax (`List[X]`) cannot be lifted by " +
      "the current suffix-wrap rule; needs a richer wrap form.",
    ),
  )
  pairs.push(
    (
      "module_target",
      "MAPPING — source import path was not in `lift.module_aliases` (e.g. " +
      "user's relative `./types.ts`). Extend the spec's `module_aliases` " +
      "table or accept relative imports as a separate concern.",
    ),
  )
  pairs.push(
    (
      "module_canonical",
      "MAPPING — canonical category was set by lift but `lower.module_aliases` " +
      "does not have a target translation. Extend lower spec.",
    ),
  )
  pairs
}

///|
/// Build the snapshot for a single target language.
async fn build_target_snapshot(target : String) -> TargetSnapshot {
  let files = list_ts_files()
  let per_file : Array[FileDrift] = []
  let rule_hist : Map[String, Int] = {}
  let totals_unresolved : Map[String, Int] = {}
  let mut total_ir_events = 0
  let mut total_unresolved = 0
  let output_dir = "tests/integration/transpile-todo-app/output/" + target
  ensure_dir(output_dir)
  // Drop project-bootstrap files (moon.pkg, Cargo.toml, etc.) so the
  // output dir is a valid project for the target compiler.
  bootstrap_project(target, output_dir)
  for f in files {
    let json_str = match @kgf_transpile.transpile_file_json(f, target, "kgfs") {
      Some(s) => s
      None => fail("transpile_file_json returned None for " + f)
    }
    let parsed : Json = @json.parse(json_str) catch {
      _ => fail("could not parse transpile JSON for " + f)
    }
    let obj = match parsed {
      Object(m) => m
      _ => fail("expected JSON object for " + f)
    }
    let code = match obj.get("code") {
      Some(String(s)) => s
      _ => ""
    }
    let ir_events_arr = match obj.get("ir_events") {
      Some(Array(a)) => a
      _ => []
    }
    for ev in ir_events_arr {
      match ev {
        Object(em) =>
          match em.get("rule") {
            Some(String(r)) => rule_hist[r] = rule_hist.get(r).unwrap_or(0) + 1
            _ => ()
          }
        _ => ()
      }
    }
    let kinds = count_unresolved_kinds(code)
    let mut file_unresolved = 0
    for k in kinds {
      file_unresolved = file_unresolved + k.1
      totals_unresolved[k.0] = totals_unresolved.get(k.0).unwrap_or(0) + k.1
    }
    let rel = if f.has_prefix(ts_src_root + "/") {
      f[ts_src_root.length() + 1:f.length()].to_owned()
    } else {
      f
    }
    let emit_parse_errors = check_emit_parses(code, target)
    // Persist transpiled code to disk so users can inspect / hand-compile.
    let stem = rel[:rel.length() - 3].to_owned() // strip ".ts"
    let out_path = output_dir + "/" + stem + target_extension(target)
    @fs.write_string_to_file(out_path, code)
    // Hand off to the target language's compiler in syntax-only mode.
    // 0 = compiler accepts; non-zero = compiler rejected; -1 = no compiler.
    let compile_exit_code = compile_check(target, out_path)
    per_file.push({
      file: rel,
      ir_event_count: ir_events_arr.length(),
      unresolved_total: file_unresolved,
      unresolved_kinds: kinds,
      emit_parse_errors,
      compile_exit_code,
    })
    total_ir_events = total_ir_events + ir_events_arr.length()
    total_unresolved = total_unresolved + file_unresolved
  }
  per_file.sort_by(fn(a, b) { a.file.compare(b.file) })
  let total_emit_errors = per_file
    .iter()
    .map(fn(f) { f.emit_parse_errors })
    .fold(init=0, fn(a, b) { a + b })
  // compile_failures: count REAL rejections only (exit_code > 0).
  // exit_code -1 (no compiler available) and -2 (process spawn error)
  // are not counted as transpile failures — they reflect environment,
  // not the engine's correctness.
  let total_compile_failures = per_file
    .iter()
    .map(fn(f) { if f.compile_exit_code > 0 { 1 } else { 0 } })
    .fold(init=0, fn(a, b) { a + b })
  let totals : Map[String, Int] = {}
  totals["files"] = files.length()
  totals["ir_events"] = total_ir_events
  totals["unresolved"] = total_unresolved
  totals["emit_parse_errors"] = total_emit_errors
  totals["compile_failures"] = total_compile_failures
  let total_no_compiler = per_file
    .iter()
    .map(fn(f) { if f.compile_exit_code == -1 { 1 } else { 0 } })
    .fold(init=0, fn(a, b) { a + b })
  totals["no_compiler_available"] = total_no_compiler
  let rule_hist_arr : Array[(String, Int)] = []
  for entry in rule_hist {
    rule_hist_arr.push((entry.0, entry.1))
  }
  rule_hist_arr.sort_by(fn(a, b) {
    if a.1 != b.1 {
      b.1.compare(a.1)
    } else {
      a.0.compare(b.0)
    }
  })
  // Filter the diagnosis to the kinds we actually saw.
  let observed_diag : Array[(String, String)] = []
  for d in kind_diagnosis() {
    if totals_unresolved.contains(d.0) {
      observed_diag.push(d)
    }
  }
  observed_diag.sort_by(fn(a, b) { a.0.compare(b.0) })
  {
    target_lang: target,
    source_lang: "typescript",
    totals,
    ir_rule_histogram: rule_hist_arr,
    files: per_file,
    unresolved_diagnosis: observed_diag,
  }
}

///|
/// Render snapshot as deterministic, prettified JSON.
fn snapshot_string(snap : TargetSnapshot) -> String {
  let json = snap.to_json()
  json.stringify(indent=2)
}

///|
/// Snapshot path for a target language.
fn snapshot_path(target : String) -> String {
  "tests/integration/transpile-todo-app/" + target + ".snapshot.json"
}

///|
/// Compare actual against the snapshot file, writing an updated copy when
/// `INDEXION_UPDATE_SNAPSHOTS=1`.
pub fn assert_snapshot_matches(
  snap_path : String,
  actual : String,
) -> Unit raise {
  let update = is_update_mode()
  let existing : String? = Some(@fs.read_file_to_string(snap_path)) catch {
    _ => None
  }
  match existing {
    Some(stored) =>
      if stored == actual {
        return
      } else if update {
        write_snapshot(snap_path, actual)
      } else {
        fail(
          "snapshot mismatch: " +
          snap_path +
          "\n--- actual ---\n" +
          actual +
          "\n--- stored ---\n" +
          stored,
        )
      }
    None =>
      if update {
        write_snapshot(snap_path, actual)
      } else {
        fail(
          "snapshot missing: " +
          snap_path +
          "\nrun with INDEXION_UPDATE_SNAPSHOTS=1 to generate.",
        )
      }
  }
}

///|
fn is_update_mode() -> Bool {
  match @sys.get_env_var("INDEXION_UPDATE_SNAPSHOTS") {
    Some(s) => s == "1" || s == "true"
    None => false
  }
}

///|
fn write_snapshot(path : String, content : String) -> Unit raise {
  @fs.write_string_to_file(path, content)
}

///|
/// Public entry consumed by per-target test files.
pub async fn run_target_snapshot(target : String) -> Unit {
  let snap = build_target_snapshot(target)
  let actual = snapshot_string(snap) + "\n"
  assert_snapshot_matches(snapshot_path(target), actual)
}

///|
/// Filename extension for each target language. Output files land at
/// `tests/integration/transpile-todo-app/output/<target>/<file><ext>`.
fn target_extension(target : String) -> String {
  match target {
    "moonbit" => ".mbt"
    "typescript" => ".ts"
    "javascript" => ".js"
    "python" => ".py"
    "rust" => ".rs"
    "c" => ".c"
    "cpp" => ".cpp"
    "swift" => ".swift"
    _ => "." + target
  }
}

///|
/// Ensure a directory exists, creating parents as needed.
fn ensure_dir(path : String) -> Unit {
  let parts = split_path(path)
  let mut acc = ""
  for p in parts {
    if p.length() == 0 {
      continue
    }
    acc = if acc.length() == 0 { p } else { acc + "/" + p }
    if !(@fs.is_dir(acc) catch { _ => false }) {
      @fs.create_dir(acc) catch {
        _ => ()
      }
    }
  }
}

///|
fn split_path(path : String) -> Array[String] {
  let result : Array[String] = []
  let mut start = 0
  let chars = path.to_array()
  let mut i = 0
  while i < chars.length() {
    if chars[i] == '/' {
      result.push(path[start:i].to_owned())
      start = i + 1
    }
    i = i + 1
  }
  result.push(path[start:path.length()].to_owned())
  result
}

///|
fn split_on_runner(text : String, sep : String) -> Array[String] {
  let result : Array[String] = []
  let mut start = 0
  let mut i = 0
  while i + sep.length() <= text.length() {
    if text[i:i + sep.length()].to_owned() == sep {
      result.push(text[start:i].to_owned())
      i = i + sep.length()
      start = i
    } else {
      i = i + 1
    }
  }
  result.push(text[start:text.length()].to_owned())
  result
}

///|
/// Run the target language's compiler in syntax-only mode against a
/// single emitted file. Returns the compiler's exit code (0 = accepts).
///
/// When the compiler isn't installed, returns -1 — the snapshot then
/// records "no compiler" rather than masquerading as success or failure.
async fn compile_check(target : String, file_path : String) -> Int {
  let (cmd, args) = compile_command(target, file_path)
  if cmd.length() == 0 {
    return -1
  }
  let cmd_path = which(cmd)
  if cmd_path.length() == 0 {
    return -1
  }
  @process.run(cmd, args[:]) catch {
    _ => -2
  }
}

///|
/// Drop the project-bootstrap files needed for the target language's
/// compiler to treat `<output_dir>` as a self-contained project.
/// Languages that cross-reference symbols across files (moonbit, rust,
/// c, cpp, typescript) need this; languages where each file stands
/// alone (python, javascript, swift) get an empty bootstrap.
fn bootstrap_project(target : String, dir : String) -> Unit raise {
  match target {
    "moonbit" => {
      @fs.write_string_to_file(
        dir + "/moon.mod.json",
        "{\n  \"name\": \"transpile-output\",\n  \"version\": \"0.1.0\",\n  \"deps\": {}\n}\n",
      )
      @fs.write_string_to_file(dir + "/moon.pkg.json", "{}\n")
    }
    "rust" =>
      // Rust: a single lib.rs that mod-declares each transpiled module
      // turns the dir into a valid `cargo check`-able crate.
      @fs.write_string_to_file(
        dir + "/lib.rs",
        "#![allow(non_snake_case, non_camel_case_types, dead_code, unused_imports)]\npub mod cli;\npub mod format;\npub mod main;\npub mod service;\npub mod storage;\npub mod types;\n",
      )
    "c" =>
      // C: write a single header that re-exports all decls, plus
      // re-emit each .c with `#include \"all.h\"` prepended via a wrapper.
      // For simplicity we generate `all.h` as the union of struct/enum
      // forward decls; the .c files that need cross-types will include it.
      @fs.write_string_to_file(
        dir + "/all.h",
        "#ifndef TRANSPILE_ALL_H\n#define TRANSPILE_ALL_H\n#include <stdlib.h>\ntypedef enum { OPEN, DONE } TodoStatus;\ntypedef struct { double id; char * title; TodoStatus status; char * createdAt; } Todo;\ntypedef struct { double nextId; Todo * items; } TodoStore;\ntypedef struct { double exitCode; char * output; } CliResult;\n#endif\n",
      )
    "cpp" =>
      @fs.write_string_to_file(
        dir + "/all.hpp",
        "#pragma once\n#include <cstdlib>\n#include <string>\n#include <vector>\n#include <optional>\nenum class TodoStatus { OPEN, DONE };\nstruct Todo { double id; std::string title; TodoStatus status; std::string createdAt; };\nstruct TodoStore { double nextId; std::vector<Todo> items; };\nstruct CliResult { double exitCode; std::string output; };\n",
      )
    "typescript" =>
      @fs.write_string_to_file(
        dir + "/tsconfig.json",
        "{\n  \"compilerOptions\": {\n    \"target\": \"esnext\",\n    \"module\": \"esnext\",\n    \"moduleResolution\": \"bundler\",\n    \"strict\": false,\n    \"noEmit\": true,\n    \"allowImportingTsExtensions\": true,\n    \"skipLibCheck\": true\n  }\n}\n",
      )
    _ => ()
  }
}

///|
/// Per-target compiler invocation in single-file syntax-only mode.
/// Each command must produce exit 0 on accept, non-zero on reject, and
/// must NOT require linking, project context, or external dependencies.
fn compile_command(target : String, file : String) -> (String, Array[String]) {
  match target {
    "javascript" => ("node", ["--check", file])
    "python" => ("python3", ["-m", "py_compile", file])
    // rustc per-file: each .rs is its own crate-type=lib check.
    // Cross-file type references fail; that's a fair expression of the
    // current transpile's limitation (no `use crate::types::*;`
    // injection). The emit_parse_errors counter shows which files
    // are structurally OK; compile_exit_code shows which clear types.
    "rust" =>
      (
        "rustc",
        [
          "--crate-type=lib", "--emit=metadata", "--edition=2021", "--allow=non_snake_case",
          "--allow=non_camel_case_types", "--allow=dead_code", "--allow=unused_variables",
          "--out-dir=/tmp/indexion-rustc-out", file,
        ],
      )
    // C / C++ syntax-only: each file is its own translation unit, but
    // bootstrap_project drops `all.h` / `all.hpp` next to it with all
    // forward declarations of cross-file types. `-include` makes that
    // header visible to every file without editing the source.
    "c" => {
      let dir = parent_dir(file)
      ("cc", ["-fsyntax-only", "-x", "c", "-include", dir + "/all.h", file])
    }
    "cpp" => {
      let dir = parent_dir(file)
      (
        "c++",
        [
          "-fsyntax-only",
          "-std=c++17",
          "-x",
          "c++",
          "-include",
          dir + "/all.hpp",
          file,
        ],
      )
    }
    "swift" => ("swiftc", ["-parse", file])
    // typescript: `bun x tsc -p <dir>` would download tsc on first
    // run (non-deterministic snapshot); skip in favor of the KGF
    // parse check (already counted via emit_parse_errors) plus the
    // round-trip-to-typescript snapshot which is sensitive to any
    // shape regression.
    "typescript" => ("", [])
    // moonbit: `moon check` cannot run from inside a `moon test`
    // invocation (recursive build lock). The KGF-parse check already
    // verifies the syntax-level correctness; project-level type
    // checking via `moon check tests/integration/transpile-todo-app/output/moonbit`
    // can be run manually after the test suite. Returning empty here
    // makes compile_check report -1 (= no compiler) for moonbit, with
    // KGF parse handled by the separate emit_parse_errors counter.
    "moonbit" => ("", [])
    _ => ("", [])
  }
}

///|
fn parent_dir(path : String) -> String {
  let mut i = path.length() - 1
  while i >= 0 {
    if path.to_array()[i] == '/' {
      return path[:i].to_owned()
    }
    i = i - 1
  }
  "."
}

///|
/// `which`: report the absolute path of `cmd`, or empty string if not on
/// PATH. Used to skip compile checks for languages whose toolchain isn't
/// installed in the current environment without making the test fail.
fn which(cmd : String) -> String {
  let path = match @sys.get_env_var("PATH") {
    Some(p) => p
    None => return ""
  }
  for dir in split_on_runner(path, ":") {
    let candidate = dir + "/" + cmd
    if @fs.path_exists(candidate) {
      return candidate
    }
  }
  ""
}

///|
/// Run `check_source` on the emitted code under the target language's KGF
/// spec. Returns the count of error-severity diagnostics. Used to verify
/// the transpile produced something the target's KGF accepts.
fn check_emit_parses(code : String, target_lang : String) -> Int {
  let dir = match @config.find_kgfs_dir() {
    Some(d) => d
    None => return -1
  }
  let registry = @registry.KGFRegistry::load_from_dir(dir)
  let spec = match registry.get_spec(target_lang) {
    Some(s) => s
    None => return -1
  }
  let diagnostics = @kgf_check.check_source(code, "<transpile-emit>", spec)
  let mut errors = 0
  for d in diagnostics {
    if d.get_severity() == "error" {
      errors = errors + 1
    }
  }
  errors
}
