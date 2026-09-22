///|
/// LCOV tracefile writer.
///
/// Produces text in the format consumed by `genhtml`, `lcov --summary`,
/// SonarQube, Codecov, and most CI viewers. Reference: the geninfo(1) man
/// page (lcov suite). The grammar this writer emits is:
///
/// ```
/// TN:<test_name>
/// SF:<source_file>
/// FN:<line>,<function_name>
/// FNDA:<execution_count>,<function_name>
/// FNF:<functions_found>
/// FNH:<functions_hit>
/// BRDA:<line>,<block>,<branch>,<taken|->
/// BRF:<branches_found>
/// BRH:<branches_hit>
/// DA:<line>,<execution_count>
/// LF:<lines_found>
/// LH:<lines_hit>
/// end_of_record
/// ```
///
/// Per the spec every record block is terminated with `end_of_record` and
/// records appear in the order shown above. We honour that ordering even
/// when sub-sections are empty so downstream parsers behave consistently.

///|
/// Render a CoverageReport as an lcov.info tracefile string.
pub fn render_lcov(report : @coverage.CoverageReport) -> String {
  let buf = StringBuilder()
  for file in report.files {
    render_lcov_file(buf, report.test_name, file)
  }
  buf.to_string()
}

///|
fn render_lcov_file(
  buf : StringBuilder,
  test_name : String,
  file : @coverage.FileCoverage,
) -> Unit {
  // TN must be present even when empty so parsers see the section boundary.
  buf.write_string("TN:")
  buf.write_string(test_name)
  buf.write_string("\n")
  buf.write_string("SF:")
  buf.write_string(file.path)
  buf.write_string("\n")
  let functions = @coverage.sort_functions(file.functions)
  for f in functions {
    buf.write_string("FN:")
    buf.write_string(f.line.to_string())
    buf.write_string(",")
    buf.write_string(f.name)
    buf.write_string("\n")
  }
  for f in functions {
    buf.write_string("FNDA:")
    buf.write_string(f.hits.to_string())
    buf.write_string(",")
    buf.write_string(f.name)
    buf.write_string("\n")
  }
  let totals = file.totals()
  buf.write_string("FNF:")
  buf.write_string(totals.functions_found.to_string())
  buf.write_string("\n")
  buf.write_string("FNH:")
  buf.write_string(totals.functions_hit.to_string())
  buf.write_string("\n")
  let branches = @coverage.sort_branches(file.branches)
  for b in branches {
    buf.write_string("BRDA:")
    buf.write_string(b.line.to_string())
    buf.write_string(",")
    buf.write_string(b.block.to_string())
    buf.write_string(",")
    buf.write_string(b.branch.to_string())
    buf.write_string(",")
    if b.taken < 0 {
      buf.write_string("-")
    } else {
      buf.write_string(b.taken.to_string())
    }
    buf.write_string("\n")
  }
  buf.write_string("BRF:")
  buf.write_string(totals.branches_found.to_string())
  buf.write_string("\n")
  buf.write_string("BRH:")
  buf.write_string(totals.branches_hit.to_string())
  buf.write_string("\n")
  let lines = @coverage.sort_lines(file.lines)
  for l in lines {
    buf.write_string("DA:")
    buf.write_string(l.line.to_string())
    buf.write_string(",")
    buf.write_string(l.hits.to_string())
    buf.write_string("\n")
  }
  buf.write_string("LF:")
  buf.write_string(totals.lines_found.to_string())
  buf.write_string("\n")
  buf.write_string("LH:")
  buf.write_string(totals.lines_hit.to_string())
  buf.write_string("\n")
  buf.write_string("end_of_record\n")
}

// sort_lines, sort_functions, sort_branches: use @coverage (types.mbt) SoT.
