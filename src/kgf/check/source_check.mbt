///|
/// Checks one source file against a KGF spec and returns unified diagnostics.
///
/// Phase A only exposes the public entry point. Lexer diagnostic collection and
/// PEG failure tracking are implemented in later phases.
pub fn check_source(
  content : String,
  path : String,
  spec : @kgf_types.KGFSpec,
) -> Array[CheckDiagnostic] {
  let _ = content
  let _ = path
  let _ = spec
  []
}
