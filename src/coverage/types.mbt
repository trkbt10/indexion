///|
/// Coverage report IR — Source-of-Truth shape for standard coverage outputs.
///
/// This module is the common in-memory representation that all coverage
/// writers (lcov.info, coverage.xml, future formats) consume. Producers
/// such as `plan documentation` build a `CoverageReport`, then a writer
/// renders it to the chosen format.
///
/// The shape mirrors what lcov tracefiles and the Cobertura DTD actually
/// require, so neither writer needs to invent values:
///
/// - `lines`  → DA records in lcov, `<line>` in cobertura
/// - `functions` → FN/FNDA records in lcov, `<methods>` in cobertura
/// - `branches`  → BRDA records in lcov, branch attributes in cobertura
///
/// A "line" here is not necessarily a literal source line of executable
/// code — for `plan documentation`, each public declaration is treated as
/// a line whose hit count is 1 if it carries a doc comment and 0 if it
/// does not. Any plan command that maps "things that should be addressed"
/// to file/line positions can produce a CoverageReport the same way.

///|
/// Hit record for a single line.
pub(all) struct LineHit {
  /// 1-based source line number.
  line : Int
  /// Number of times the line was "hit". 0 means uncovered.
  hits : Int
}

///|
/// Optional function-level record.
pub(all) struct FunctionHit {
  /// 1-based line where the function is declared.
  line : Int
  /// Function name.
  name : String
  /// Number of times the function was hit. 0 means uncovered.
  hits : Int
}

///|
/// Optional branch-level record.
pub(all) struct BranchHit {
  /// 1-based source line number of the branch.
  line : Int
  /// Basic-block ordinal within the line (lcov BRDA block).
  block : Int
  /// Branch ordinal within the block (lcov BRDA branch).
  branch : Int
  /// Times the branch was taken. -1 means "never evaluated" (lcov emits "-").
  taken : Int
}

///|
/// Coverage data for a single file.
pub(all) struct FileCoverage {
  /// Path to the source file. Should be relative to `CoverageReport.source_root`
  /// when one is set, otherwise an absolute or project-relative path.
  path : String
  /// Logical package/grouping the file belongs to. Used by Cobertura's
  /// `<package name=...>` element. Empty string is acceptable and will be
  /// rendered as the default package by the cobertura writer.
  pkg : String
  /// Per-line hits. Order does not have to be sorted; writers sort as needed.
  lines : Array[LineHit]
  /// Per-function hits (optional, may be empty).
  functions : Array[FunctionHit]
  /// Per-branch hits (optional, may be empty).
  branches : Array[BranchHit]
}

///|
/// Build a FileCoverage with empty functions/branches.
pub fn FileCoverage::new(
  path : String,
  pkg : String,
  lines : Array[LineHit],
) -> FileCoverage {
  { path, pkg, lines, functions: [], branches: [], }
}

///|
/// Complete coverage report.
pub(all) struct CoverageReport {
  /// Optional test-name label, written as lcov's `TN:` record.
  test_name : String
  /// Absolute path to the source root. Emitted as Cobertura's `<source>`.
  /// May be empty.
  source_root : String
  /// Per-file coverage.
  files : Array[FileCoverage]
  /// Unix timestamp (seconds) for Cobertura's `timestamp` attribute.
  /// 0 means "unspecified" — writers will substitute a stable placeholder.
  timestamp : Int64
}

///|
/// Build a CoverageReport.
pub fn CoverageReport::new(
  files : Array[FileCoverage],
  test_name? : String = "",
  source_root? : String = "",
  timestamp? : Int64 = 0L,
) -> CoverageReport {
  { test_name, source_root, files, timestamp, }
}

///|
/// Aggregate stats over a `CoverageReport`. Convenience used by writers
/// and tests; kept in the IR so neither writer recomputes it inconsistently.
pub(all) struct CoverageTotals {
  lines_found : Int
  lines_hit : Int
  functions_found : Int
  functions_hit : Int
  branches_found : Int
  branches_hit : Int
}

///|
/// Compute totals for a single file.
pub fn FileCoverage::totals(self : FileCoverage) -> CoverageTotals {
  let mut lf = 0
  let mut lh = 0
  for l in self.lines {
    lf = lf + 1
    if l.hits > 0 {
      lh = lh + 1
    }
  }
  let mut fnf = 0
  let mut fnh = 0
  for f in self.functions {
    fnf = fnf + 1
    if f.hits > 0 {
      fnh = fnh + 1
    }
  }
  let mut brf = 0
  let mut brh = 0
  for b in self.branches {
    brf = brf + 1
    if b.taken > 0 {
      brh = brh + 1
    }
  }
  {
    lines_found: lf,
    lines_hit: lh,
    functions_found: fnf,
    functions_hit: fnh,
    branches_found: brf,
    branches_hit: brh,
  }
}

///|
/// Sum FileCoverage totals across any iterable of files. The single
/// SoT for "add up coverage stats" — used both for whole-report totals
/// and for per-package totals inside Cobertura output.
pub fn aggregate_totals(files : Array[FileCoverage]) -> CoverageTotals {
  let mut lf = 0
  let mut lh = 0
  let mut fnf = 0
  let mut fnh = 0
  let mut brf = 0
  let mut brh = 0
  for file in files {
    let t = file.totals()
    lf = lf + t.lines_found
    lh = lh + t.lines_hit
    fnf = fnf + t.functions_found
    fnh = fnh + t.functions_hit
    brf = brf + t.branches_found
    brh = brh + t.branches_hit
  }
  {
    lines_found: lf,
    lines_hit: lh,
    functions_found: fnf,
    functions_hit: fnh,
    branches_found: brf,
    branches_hit: brh,
  }
}

///|
/// Compute totals across the whole report.
pub fn CoverageReport::totals(self : CoverageReport) -> CoverageTotals {
  aggregate_totals(self.files)
}

///|
/// Return a stable, line-then-name-sorted copy of a FunctionHit array.
/// Used by every writer so output is deterministic across runs.
pub fn sort_functions(functions : Array[FunctionHit]) -> Array[FunctionHit] {
  let copy : Array[FunctionHit] = []
  for f in functions {
    copy.push(f)
  }
  copy.sort_by(fn(a, b) {
    let cmp = a.line.compare(b.line)
    if cmp != 0 {
      cmp
    } else {
      a.name.compare(b.name)
    }
  })
  copy
}

///|
/// Return a stable, line-sorted copy of a LineHit array. Used by every
/// writer so output is deterministic across runs.
pub fn sort_lines(lines : Array[LineHit]) -> Array[LineHit] {
  let copy : Array[LineHit] = []
  for l in lines {
    copy.push(l)
  }
  copy.sort_by(fn(a, b) { a.line.compare(b.line) })
  copy
}

///|
/// Return a stable, (line, block, branch)-sorted copy of a BranchHit
/// array. Used by every writer so output is deterministic across runs.
pub fn sort_branches(branches : Array[BranchHit]) -> Array[BranchHit] {
  let copy : Array[BranchHit] = []
  for b in branches {
    copy.push(b)
  }
  copy.sort_by(fn(a, b) {
    let cmp = a.line.compare(b.line)
    if cmp != 0 {
      cmp
    } else {
      let cmp_block = a.block.compare(b.block)
      if cmp_block != 0 {
        cmp_block
      } else {
        a.branch.compare(b.branch)
      }
    }
  })
  copy
}

///|
/// Rate = hit / found, with the convention that "found == 0" yields 1.0
/// (matches Cobertura and lcov behaviour: an empty unit is fully covered).
pub fn coverage_rate(hit : Int, found : Int) -> Double {
  if found == 0 {
    1.0
  } else {
    hit.to_double() / found.to_double()
  }
}
