///|
/// Current version of indexion.
/// NOTE: SoT is moon.mod.json "version" field.
/// This constant must be kept in sync manually (MoonBit has no compile-time embedding).
pub let current_version : String = "0.5.0"

///|
/// GitHub repository owner/name.
/// NOTE: SoT is moon.mod.json "repository" field.
let repo : String = "trkbt10/indexion"

///|
/// Parsed semver components.
priv struct Semver {
  major : Int
  minor : Int
  patch : Int
}

///|
/// Parse a version string like "0.1.0" or "v0.1.0" into Semver.
fn parse_semver(version : String) -> Semver? {
  let raw = if version.has_prefix("v") {
    strip_prefix_v(version)
  } else {
    version
  }
  let parts = split_by_dot(raw)
  if parts.length() != 3 {
    return None
  }
  let major = parse_int_opt(parts[0])
  let minor = parse_int_opt(parts[1])
  let patch = parse_int_opt(parts[2])
  match (major, minor, patch) {
    (Some(ma), Some(mi), Some(pa)) => Some({ major: ma, minor: mi, patch: pa })
    _ => None
  }
}

///|
/// Compare two semver: returns positive if a > b, negative if a < b, 0 if equal.
pub fn compare_versions(a : String, b : String) -> Int {
  let sa = parse_semver(a)
  let sb = parse_semver(b)
  match (sa, sb) {
    (Some(va), Some(vb)) => {
      let major_diff = va.major - vb.major
      if major_diff != 0 {
        return major_diff
      }
      let minor_diff = va.minor - vb.minor
      if minor_diff != 0 {
        return minor_diff
      }
      va.patch - vb.patch
    }
    _ => 0
  }
}

///|
fn strip_prefix_v(s : String) -> String {
  let chars = s.to_array()
  let result : Array[Char] = []
  for i in 1..<chars.length() {
    result.push(chars[i])
  }
  String::from_array(result)
}

///|
fn split_by_dot(s : String) -> Array[String] {
  let parts : Array[String] = []
  let current : Array[Char] = []
  for ch in s {
    if ch == '.' {
      parts.push(String::from_array(current))
      current.clear()
    } else {
      current.push(ch)
    }
  }
  if current.length() > 0 {
    parts.push(String::from_array(current))
  }
  parts
}

///|
fn parse_int_opt(s : String) -> Int? {
  if s.length() == 0 {
    return None
  }
  let mut result = 0
  for ch in s {
    if ch >= '0' && ch <= '9' {
      result = result * 10 + (ch.to_int() - '0'.to_int())
    } else {
      return None
    }
  }
  Some(result)
}
