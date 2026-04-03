///|
/// A parsed numeric value with its original text.
pub struct ParsedValue {
  value : Int
  source : String
}

pub fn parse(input : String) -> Result[Int, String] {
  let trimmed = @utils.trim(input)
  match @strconv.parse_int?(trimmed) {
    Some(n) => Ok(n)
    None => Err("invalid number")
  }
}

pub fn format(n : Int) -> String {
  n.to_string()
}
