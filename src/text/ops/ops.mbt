///|
/// Text operations: split, join, merge.
/// SoT for text-to-text transformations.

///|
/// Split text into lines by newline characters.
/// Handles both \n and \r\n line endings (skips \r).
pub fn split_by_newline(text : String) -> Array[String] {
  let lines : Array[String] = []
  let chars = text.to_array()
  let buf : Array[Char] = []
  for c in chars {
    if c == '\n' {
      lines.push(String::from_array(buf))
      buf.clear()
    } else if c == '\r' {
      continue
    } else {
      buf.push(c)
    }
  }
  if buf.length() > 0 {
    lines.push(String::from_array(buf))
  }
  lines
}

///|
/// Join up to `n` elements of an array with ", " separator.
/// If the array has more than `n` elements, appends " (+M more)".
pub fn join_with_limit(arr : Array[String], n : Int) -> String {
  let buf = StringBuilder::new()
  let limit = if n < arr.length() { n } else { arr.length() }
  for i = 0; i < limit; i = i + 1 {
    if i > 0 {
      buf.write_string(", ")
    }
    buf.write_string(arr[i])
  }
  if arr.length() > limit {
    buf.write_string(" (+")
    buf.write_string((arr.length() - limit).to_string())
    buf.write_string(" more)")
  }
  buf.to_string()
}

///|
/// Merge values into target array, skipping empty strings and duplicates.
pub fn merge_unique_strings(
  target : Array[String],
  values : Array[String],
) -> Unit {
  for value in values {
    if value.length() > 0 && !target.contains(value) {
      target.push(value)
    }
  }
}
