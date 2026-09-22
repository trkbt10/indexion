///|
/// Checks one source file against a KGF spec and returns unified diagnostics.
pub fn check_source(
  content : String,
  path : String,
  spec : @kgf_types.KGFSpec,
) -> Array[CheckDiagnostic] {
  let diagnostics : Array[CheckDiagnostic] = []
  let source_map = SourceMap::new(content)
  let lexer = @kgf_lexer.Lexer::new(spec.get_tokens())
  let (tokens, lex_diagnostics) = lexer.tokenize_with_diagnostics(content)
  for diagnostic in lex_diagnostics {
    let (line, col) = source_map.resolve(diagnostic.get_pos())
    diagnostics.push(
      CheckDiagnostic::new(
        path,
        line,
        col,
        "error",
        "unrecognized input: " + diagnostic.get_text(),
        "lexer",
      ),
    )
  }
  if tokens.length() == 0 {
    return diagnostics
  }
  let start_rule = spec.get_start_rule()
  if start_rule.length() == 0 {
    diagnostics.push(
      CheckDiagnostic::new(
        path, 1, 1, "error", "no grammar start rule", "parser",
      ),
    )
    return diagnostics
  }
  let peg = @kgf_peg.build_peg(spec) catch {
    _ => {
      diagnostics.push(
        CheckDiagnostic::new(
          path, 1, 1, "error", "failed to build PEG grammar", "parser",
        ),
      )
      return diagnostics
    }
  }
  let (_, parse_diagnostic) = @kgf_peg.run_parse_with_diagnostics(
    peg, spec, start_rule, tokens,
  )
  if !parse_diagnostic.is_fully_consumed() {
    let pos = match parse_diagnostic.get_actual_token() {
      Some(tok) => tok.get_pos()
      None => content.length()
    }
    let (line, col) = source_map.resolve(pos)
    diagnostics.push(
      CheckDiagnostic::new(
        path,
        line,
        col,
        "error",
        parse_diagnostic.describe(),
        "parser",
      ),
    )
  }
  diagnostics
}
