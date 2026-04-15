///|
/// # Wiki Log
///
/// Append-only operation log for wiki operations.
/// Tracks ingest, lint, query, and maintenance operations
/// with timestamps and affected page references.

///|
/// A single log entry recording a wiki operation.
pub struct WikiLogEntry {
  /// Unix timestamp in milliseconds.
  timestamp : UInt64
  /// Operation type: "ingest", "lint", "query", "index", "export", "import",
  /// "add-page", "update-page", "plan", "manual".
  operation : String
  /// Who performed the operation: "indexion", "agent:<name>", "user".
  actor : String
  /// Human-readable summary of what happened.
  summary : String
  /// Operation-specific key-value details.
  details : Map[String, String]
  /// Page IDs that were created, modified, or examined.
  affected_pages : Array[String]
} derive(ToJson)

///|
pub fn WikiLogEntry::new(
  timestamp~ : UInt64,
  operation~ : String,
  actor~ : String,
  summary~ : String,
  details? : Map[String, String] = {},
  affected_pages? : Array[String] = [],
) -> WikiLogEntry {
  { timestamp, operation, actor, summary, details, affected_pages }
}

///|
impl @json.FromJson for WikiLogEntry with from_json(json, path) {
  guard json is Object(obj) else {
    raise @json.JsonDecodeError(
      (path, "WikiLogEntry::from_json: expected object"),
    )
  }
  let timestamp : UInt64 = match obj.get("timestamp") {
    Some(Number(n, ..)) => n.to_uint64()
    _ => 0UL
  }
  let operation = match obj.get("operation") {
    Some(String(s)) => s
    _ => ""
  }
  let actor = match obj.get("actor") {
    Some(String(s)) => s
    _ => ""
  }
  let summary = match obj.get("summary") {
    Some(String(s)) => s
    _ => ""
  }
  let details : Map[String, String] = {}
  match obj.get("details") {
    Some(Object(d)) =>
      for entry in d {
        match entry.1 {
          String(s) => details[entry.0] = s
          _ => ()
        }
      }
    _ => ()
  }
  let affected_pages : Array[String] = []
  match obj.get("affected_pages") {
    Some(Array(arr)) =>
      for item in arr {
        match item {
          String(s) => affected_pages.push(s)
          _ => ()
        }
      }
    _ => ()
  }
  { timestamp, operation, actor, summary, details, affected_pages }
}

///|
/// The full wiki log, wrapping an array of entries.
pub struct WikiLog {
  entries : Array[WikiLogEntry]
}

///|
pub fn WikiLog::new() -> WikiLog {
  { entries: [] }
}

///|
/// Load the wiki log from the given wiki directory.
/// Returns an empty log if the file does not exist or cannot be parsed.
pub fn WikiLog::load(wiki_dir : String) -> WikiLog {
  let path = @wiki_types.wiki_log_path(wiki_dir)
  if !@fs.path_exists(path) {
    return WikiLog::new()
  }
  let content = @fs.read_file_to_string(path) catch {
    _ => return WikiLog::new()
  }
  let json = @json.parse(content) catch { _ => return WikiLog::new() }
  match json {
    Array(arr) => {
      let entries : Array[WikiLogEntry] = []
      for item in arr {
        let entry : WikiLogEntry = @json.from_json(item) catch { _ => continue }
        entries.push(entry)
      }
      { entries, }
    }
    _ => WikiLog::new()
  }
}

///|
/// Append a new entry to the log.
pub fn WikiLog::append(self : WikiLog, entry : WikiLogEntry) -> Unit {
  self.entries.push(entry)
}

///|
/// Save the log to the given wiki directory.
pub fn WikiLog::save(self : WikiLog, wiki_dir : String) -> Unit {
  let path = @wiki_types.wiki_log_path(wiki_dir)
  @config.ensure_dir_recursive(wiki_dir)
  let json : Array[Json] = []
  for entry in self.entries {
    json.push(entry.to_json())
  }
  let content = Json::array(json).stringify(indent=2)
  @fs.write_string_to_file(path, content) catch {
    _ => ()
  }
}

///|
/// Get the last N entries (most recent last).
pub fn WikiLog::tail(self : WikiLog, n : Int) -> Array[WikiLogEntry] {
  let len = self.entries.length()
  if n >= len {
    return self.entries
  }
  let result : Array[WikiLogEntry] = []
  for i in (len - n)..<len {
    result.push(self.entries[i])
  }
  result
}

///|
/// Get total number of entries.
pub fn WikiLog::length(self : WikiLog) -> Int {
  self.entries.length()
}

///|
/// Render a log entry as a human-readable line.
pub fn WikiLogEntry::to_display(self : WikiLogEntry) -> String {
  let buf = StringBuilder::new()
  buf.write_string("[")
  buf.write_string(self.timestamp.to_string())
  buf.write_string("] ")
  buf.write_string(self.operation)
  buf.write_string(" (")
  buf.write_string(self.actor)
  buf.write_string(") ")
  buf.write_string(self.summary)
  if self.affected_pages.length() > 0 {
    buf.write_string(" | pages: ")
    buf.write_string(self.affected_pages.join(", "))
  }
  buf.to_string()
}

///|
/// Render the full log as human-readable text.
pub fn WikiLog::to_display(self : WikiLog) -> String {
  let lines : Array[String] = []
  for entry in self.entries {
    lines.push(entry.to_display())
  }
  lines.join("\n")
}
