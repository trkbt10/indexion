///|
/// CheckDiagnostic is the unified diagnostic emitted by `indexion check`.
pub struct CheckDiagnostic {
  file : String
  line : Int
  col : Int
  severity : String
  message : String
  source : String
} derive(Eq, Debug, ToJson, @json.FromJson)

///|
/// Creates a check diagnostic with file and resolved source position.
pub fn CheckDiagnostic::new(
  file : String,
  line : Int,
  col : Int,
  severity : String,
  message : String,
  source : String,
) -> CheckDiagnostic {
  { file, line, col, severity, message, source }
}

///|
pub fn CheckDiagnostic::get_file(self : CheckDiagnostic) -> String {
  self.file
}

///|
pub fn CheckDiagnostic::get_line(self : CheckDiagnostic) -> Int {
  self.line
}

///|
pub fn CheckDiagnostic::get_col(self : CheckDiagnostic) -> Int {
  self.col
}

///|
pub fn CheckDiagnostic::get_severity(self : CheckDiagnostic) -> String {
  self.severity
}

///|
pub fn CheckDiagnostic::get_message(self : CheckDiagnostic) -> String {
  self.message
}

///|
pub fn CheckDiagnostic::get_source(self : CheckDiagnostic) -> String {
  self.source
}

///|
/// Compares diagnostics by file, line, then column for stable output ordering.
pub fn CheckDiagnostic::compare(
  self : CheckDiagnostic,
  other : CheckDiagnostic,
) -> Int {
  let file_cmp = self.file.compare(other.file)
  if file_cmp != 0 {
    return file_cmp
  }
  let line_cmp = self.line.compare(other.line)
  if line_cmp != 0 {
    return line_cmp
  }
  self.col.compare(other.col)
}

///|
/// Formats a diagnostic in standard compiler style.
pub fn CheckDiagnostic::format_human(self : CheckDiagnostic) -> String {
  self.file +
  ":" +
  self.line.to_string() +
  ":" +
  self.col.to_string() +
  ": " +
  self.severity +
  ": " +
  self.message
}

///|
/// Converts an array of check diagnostics to a JSON string.
pub fn diagnostics_to_json(diagnostics : Array[CheckDiagnostic]) -> String {
  let items : Array[Json] = []
  for diagnostic in diagnostics {
    items.push(diagnostic.to_json())
  }
  Json::array(items).stringify(indent=2)
}
