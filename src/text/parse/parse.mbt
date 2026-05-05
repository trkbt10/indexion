///|
/// Text parsing: string to structured data.
/// SoT for text-to-data transformations.

///|
/// Parse a string to an integer. Returns 0 if the string is empty or
/// contains non-digit characters.
pub fn parse_int_or_zero(text : String) -> Int {
  let mut value = 0
  let mut has_digit = false
  for ch in text {
    if ch >= '0' && ch <= '9' {
      value = value * 10 + (ch.to_int() - '0'.to_int())
      has_digit = true
    } else {
      return 0
    }
  }
  if has_digit { value } else { 0 }
}
