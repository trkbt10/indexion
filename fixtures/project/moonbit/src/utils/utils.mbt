pub fn trim(s : String) -> String {
  // Simple whitespace trimming
  let chars = s.to_array()
  let start = find_non_space(chars, 0, 1)
  let end = find_non_space(chars, chars.length() - 1, -1)
  if start > end {
    ""
  } else {
    s.substring(start, end + 1)
  }
}

fn find_non_space(chars : Array[Char], idx : Int, step : Int) -> Int {
  if idx < 0 || idx >= chars.length() {
    idx
  } else if chars[idx] == ' ' || chars[idx] == '\t' {
    find_non_space(chars, idx + step, step)
  } else {
    idx
  }
}
