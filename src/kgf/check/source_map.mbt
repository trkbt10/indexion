///|
/// SourceMap maps byte offsets in a source string to 1-based line and column
/// coordinates.
pub struct SourceMap {
  line_starts : Array[Int]
}

///|
/// Builds a source map by recording the byte offset where each line begins.
/// Both LF and CRLF line endings are treated as one line break.
pub fn SourceMap::new(text : String) -> SourceMap {
  let line_starts : Array[Int] = [0]
  let mut pos = 0
  while pos < text.length() {
    let ch = text[pos].to_int().unsafe_to_char()
    if ch == '\r' {
      if pos + 1 < text.length() &&
        text[pos + 1].to_int().unsafe_to_char() == '\n' {
        line_starts.push(pos + 2)
        pos = pos + 2
      } else {
        line_starts.push(pos + 1)
        pos = pos + 1
      }
    } else if ch == '\n' {
      line_starts.push(pos + 1)
      pos = pos + 1
    } else {
      pos = pos + 1
    }
  }
  { line_starts, }
}

///|
/// Returns the precomputed line starts.
pub fn SourceMap::get_line_starts(self : SourceMap) -> Array[Int] {
  self.line_starts
}

///|
/// Resolves a byte offset to a 1-based `(line, column)` pair.
pub fn SourceMap::resolve(self : SourceMap, pos : Int) -> (Int, Int) {
  let target = if pos < 0 { 0 } else { pos }
  let mut low = 0
  let mut high = self.line_starts.length()
  while low < high {
    let mid = (low + high) / 2
    if self.line_starts[mid] <= target {
      low = mid + 1
    } else {
      high = mid
    }
  }
  let line_index = if low == 0 { 0 } else { low - 1 }
  let line_start = self.line_starts[line_index]
  (line_index + 1, target - line_start + 1)
}
