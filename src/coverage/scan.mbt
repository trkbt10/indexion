///|
/// Bridge between measurement-style `plan` commands and the coverage IR.
///
/// Every measurement plan in indexion has the same shape underneath:
///
///   "I scanned a set of files. In each file, certain *units* (a pub
///    declaration, a function definition, a candidate refactor site, a
///    flagged symbol, …) were checked. Each unit either passed or failed
///    the check."
///
/// `ScanResult` is the canonical representation of that shape. Every
/// producer builds one, then calls `ScanResult::to_coverage_report` to
/// project it onto a `CoverageReport`. This is the *only* place that
/// decides:
///
/// - passed unit → `hits = 1`, failed unit → `hits = 0`
/// - multiple units on the same line are merged via `max(hits)` so DA
///   records stay unique (lcov requires one DA per source line)
/// - units flagged as functions also emit `FunctionHit` records, so
///   lcov consumers can show per-symbol coverage
///
/// Without this SoT every plan command would re-implement the same
/// dedup-by-line + function-emission logic.

///|
/// A single scanned unit — one item that can pass or fail a check.
pub(all) struct ScanUnit {
  /// 1-based source line where the unit lives.
  line : Int
  /// Symbol name (function, type, magic string, …). Empty means "no name".
  /// Drives whether a `FunctionHit` is emitted.
  name : String
  /// If true and `name` is non-empty, the converter also emits a
  /// `FunctionHit` so downstream tooling can show per-symbol coverage.
  is_function : Bool
  /// `true` = unit passed the check (covered, hits=1).
  /// `false` = unit failed (uncovered, hits=0 — a finding).
  passed : Bool
}

///|
/// Build a ScanUnit.
pub fn ScanUnit::new(
  line : Int,
  passed : Bool,
  name? : String = "",
  is_function? : Bool = false,
) -> ScanUnit {
  { line, name, is_function, passed }
}

///|
/// All units scanned in one source file.
pub(all) struct ScanFile {
  /// Relative path to the source file (used as `SF:` in lcov and as
  /// `filename` in cobertura).
  path : String
  /// Package/grouping label — propagated to `FileCoverage.pkg`.
  pkg : String
  units : Array[ScanUnit]
}

///|
/// Build a ScanFile.
pub fn ScanFile::new(
  path : String,
  pkg? : String = "",
  units? : Array[ScanUnit] = [],
) -> ScanFile {
  { path, pkg, units }
}

///|
/// Append a unit to a ScanFile.
pub fn ScanFile::add(self : ScanFile, unit : ScanUnit) -> Unit {
  self.units.push(unit)
}

///|
/// Top-level scan result. One producer = one `ScanResult`.
pub(all) struct ScanResult {
  /// Label written as `TN:` in lcov output. Producer-defined, e.g.
  /// `"indexion-plan-documentation"`, `"indexion-plan-unwrap"`.
  test_name : String
  /// Project-relative root, written as Cobertura's `<source>`.
  source_root : String
  files : Array[ScanFile]
}

///|
/// Build a ScanResult.
pub fn ScanResult::new(
  test_name : String,
  source_root : String,
  files? : Array[ScanFile] = [],
) -> ScanResult {
  { test_name, source_root, files }
}

///|
/// Append a file to a ScanResult.
pub fn ScanResult::add_file(self : ScanResult, file : ScanFile) -> Unit {
  self.files.push(file)
}

///|
/// Builder for `ScanResult` — handles the file-dedup-and-order bookkeeping
/// that every converter would otherwise re-implement.
///
/// Without this builder, every converter ends up with the same triple:
/// an order-preserving `Array[String]`, a `Map[String, ScanFile]` for
/// fast lookup, and a small `record_finding` / `add_unit` helper that
/// ensures-or-creates the right `ScanFile` before pushing a `ScanUnit`.
/// `ScanBuilder` collapses that to one type.
///
/// Two usage patterns:
///
/// 1. **Findings-only** producers (`plan refactor`, `plan solid`,
///    `plan reconcile`, `identity audit`) call `record(...)` per
///    finding — each finding lands as an uncovered (`passed=false`)
///    ScanUnit.
/// 2. **Pass-and-fail** producers (`plan documentation`, `plan unwrap`,
///    `spec verify`) call `add_unit(file, ScanUnit::new(...), pkg=...)`
///    so they can mark individual units as passed.
pub(all) struct ScanBuilder {
  by_file : Map[String, ScanFile]
  file_order : Array[String]
}

///|
/// Construct an empty `ScanBuilder`.
pub fn ScanBuilder::new() -> ScanBuilder {
  { by_file: {}, file_order: [] }
}

///|
/// Get the `ScanFile` for `path`, creating it on first use. The `pkg`
/// argument is used only on creation; subsequent calls return the
/// already-recorded `ScanFile` regardless of the `pkg` value passed in.
///
/// If `pkg` is omitted the parent directory of `path` is used as the
/// package label. Pass an explicit value when the producer has a richer
/// package concept (e.g. KGF module path).
pub fn ScanBuilder::ensure_file(
  self : ScanBuilder,
  path : String,
  pkg? : String = "",
) -> ScanFile {
  match self.by_file.get(path) {
    Some(sf) => sf
    None => {
      let resolved_pkg = if pkg.length() > 0 { pkg } else { default_pkg(path) }
      let sf = ScanFile::new(path, pkg=resolved_pkg)
      self.by_file.set(path, sf)
      self.file_order.push(path)
      sf
    }
  }
}

///|
/// Append a `ScanUnit` to the file's bucket. General-purpose — use this
/// when the unit might be passing or failing. For findings-only flows
/// `record(...)` is shorter.
pub fn ScanBuilder::add_unit(
  self : ScanBuilder,
  file : String,
  unit : ScanUnit,
  pkg? : String = "",
) -> Unit {
  self.ensure_file(file, pkg~).add(unit)
}

///|
/// Record a finding — an uncovered unit at `(file, line)`. Convenience
/// over `add_unit(file, ScanUnit::new(line, false, …))`.
///
/// `name` is attached when non-empty; `is_function` controls whether a
/// `FunctionHit` is emitted by `ScanResult::to_coverage_report`. When
/// `name` is empty the `is_function` flag is silently suppressed so
/// callers can pass `is_function=name.length() > 0` without thinking.
pub fn ScanBuilder::record(
  self : ScanBuilder,
  file : String,
  line : Int,
  name? : String = "",
  is_function? : Bool = false,
  pkg? : String = "",
) -> Unit {
  let emit_function = is_function && name.length() > 0
  self.add_unit(
    file,
    ScanUnit::new(line, false, name~, is_function=emit_function),
    pkg~,
  )
}

///|
/// Project the accumulated state onto a `ScanResult`. Producer order is
/// preserved: files appear in the order they were first recorded.
pub fn ScanBuilder::to_scan_result(
  self : ScanBuilder,
  test_name : String,
  source_root : String,
) -> ScanResult {
  let scan = ScanResult::new(test_name, source_root)
  for path in self.file_order {
    match self.by_file.get(path) {
      Some(sf) => scan.add_file(sf)
      None => ()
    }
  }
  scan
}

///|
/// Project directly to a `CoverageReport`. Equivalent to
/// `to_scan_result(...).to_coverage_report()` — the common shortcut.
pub fn ScanBuilder::to_coverage_report(
  self : ScanBuilder,
  test_name : String,
  source_root : String,
) -> CoverageReport {
  self.to_scan_result(test_name, source_root).to_coverage_report()
}

///|
/// Derive the conventional package label from a file path: the parent
/// directory, or `"."` when the file lives at the source root.
fn default_pkg(path : String) -> String {
  let chars = path.to_array()
  let mut last_sep = -1
  for i = 0; i < chars.length(); i = i + 1 {
    if chars[i] == '/' || chars[i] == '\\' {
      last_sep = i
    }
  }
  if last_sep <= 0 {
    return "."
  }
  let out : Array[Char] = []
  for i = 0; i < last_sep; i = i + 1 {
    out.push(chars[i])
  }
  String::from_array(out)
}

///|
/// Project a ScanResult onto the coverage IR.
///
/// Rules — the *only* place these decisions are made:
///
/// 1. `passed = true`  → `hits = 1`
///    `passed = false` → `hits = 0`
/// 2. When multiple units share the same source line, the line's final
///    `hits` is `max` of the per-unit hits. (One passing unit covers a
///    line even if a same-line failing unit existed — passing wins by
///    convention. The opposite convention would collapse mixed lines to
///    "failed", which is too noisy for coverage UIs.)
/// 3. A unit emits a `FunctionHit` iff `is_function && name.length() > 0`.
/// 4. Empty ScanFiles still appear in the output (as 100%-covered shells)
///    — producers can use them to record "this file was inspected and
///    nothing matched".
pub fn ScanResult::to_coverage_report(self : ScanResult) -> CoverageReport {
  let files : Array[FileCoverage] = []
  for sf in self.files {
    // line → max hits seen so far. First-seen order is preserved via
    // `line_order` so the converted lines reflect producer order.
    let line_hits : Map[Int, Int] = {}
    let line_order : Array[Int] = []
    let functions : Array[FunctionHit] = []
    for u in sf.units {
      let hits = if u.passed { 1 } else { 0 }
      match line_hits.get(u.line) {
        Some(existing) => if hits > existing { line_hits.set(u.line, hits) }
        None => {
          line_hits.set(u.line, hits)
          line_order.push(u.line)
        }
      }
      if u.is_function && u.name.length() > 0 {
        functions.push({ line: u.line, name: u.name, hits })
      }
    }
    let lines : Array[LineHit] = []
    for line in line_order {
      lines.push({ line, hits: line_hits.get(line).unwrap_or(0) })
    }
    files.push({ path: sf.path, pkg: sf.pkg, lines, functions, branches: [] })
  }
  CoverageReport::new(
    files,
    test_name=self.test_name,
    source_root=self.source_root,
  )
}
