///|
/// Parses the `=== classify` section of a KGF spec.
///
/// The classify section contains a trained classification model persisted
/// by a training tool (e.g., `indexion classify train`). The weights are
/// computed from a document corpus, NOT hand-authored.
///
/// ## Syntax
///
/// ```
/// # Metadata: key = value (model parameters, corpus statistics)
/// model_type = naive_bayes
/// corpus_size = 150
/// smoothing = laplace
///
/// # Class definition: @class_name prior=log_probability
/// # Followed by indented term=weight lines (conditional log-probabilities)
/// @normative prior=-0.693
///   shall=-0.105
///   must=-0.223
///   required=-0.511
///
/// @meta prior=-1.204
///   introduction=-0.693
///   scope=-1.099
/// ```
///
/// Lines starting with `#` are comments. Blank lines are ignored.
pub fn parse_classify(text : String) -> @types.ClassifyModel? {
  let lines = split_lines(text)
  let metadata : Map[String, String] = {}
  let classes : Map[String, @types.ClassifyClass] = {}
  let mut current_class : String = ""
  let mut current_prior : Double = 0.0
  let mut current_vocab : Map[String, Double] = {}
  for line in lines {
    let trimmed = trim_str(line)
    if trimmed.length() == 0 || starts_with(trimmed, "#") {
      continue
    }
    // Class definition: @class_name prior=value
    if starts_with(trimmed, "@") {
      // Finalize previous class if any
      if current_class.length() > 0 {
        classes.set(
          current_class,
          @types.ClassifyClass::new(current_prior, current_vocab),
        )
      }
      let (name, prior) = parse_class_header(substr_from(trimmed, 1))
      current_class = name
      current_prior = prior
      current_vocab = {}
      continue
    }
    // Indented term=weight line (inside a class definition)
    if current_class.length() > 0 && is_indented(line) {
      match parse_term_weight(trimmed) {
        Some((term, weight)) => current_vocab.set(term, weight)
        None => ()
      }
      continue
    }
    // Top-level metadata: key = value
    if current_class.length() == 0 {
      match parse_metadata_line(trimmed) {
        Some((key, value)) => metadata.set(key, value)
        None => ()
      }
    } else {
      // Non-indented line after a class definition — could be a new class
      // or metadata. Finalize current class and re-process.
      classes.set(
        current_class,
        @types.ClassifyClass::new(current_prior, current_vocab),
      )
      current_class = ""
      current_prior = 0.0
      current_vocab = {}
      // Re-check if this is a new class or metadata
      if starts_with(trimmed, "@") {
        let (name, prior) = parse_class_header(substr_from(trimmed, 1))
        current_class = name
        current_prior = prior
        current_vocab = {}
      } else {
        match parse_metadata_line(trimmed) {
          Some((key, value)) => metadata.set(key, value)
          None => ()
        }
      }
    }
  }
  // Finalize last class
  if current_class.length() > 0 {
    classes.set(
      current_class,
      @types.ClassifyClass::new(current_prior, current_vocab),
    )
  }
  if classes.is_empty() && metadata.is_empty() {
    None
  } else {
    Some(@types.ClassifyModel::new(metadata, classes))
  }
}

// is_indented is defined in parse_resolver.mbt and reused here.

///|
/// Parses a class header: `class_name prior=value`
/// Returns (class_name, prior_value).
fn parse_class_header(text : String) -> (String, Double) {
  let trimmed = trim_str(text)
  // Find the first space to separate name from parameters
  let space_idx = find_char(trimmed, 0, ' ')
  if space_idx < 0 {
    // Just a class name with no prior
    return (trimmed, 0.0)
  }
  let name = substr(trimmed, 0, space_idx)
  let params = trim_str(substr_from(trimmed, space_idx + 1))
  // Parse prior=value
  let mut prior = 0.0
  if starts_with(params, "prior=") {
    let value_str = trim_str(substr_from(params, 6))
    prior = parse_double(value_str)
  }
  (name, prior)
}

///|
/// Parses a metadata line: `key = value`
fn parse_metadata_line(text : String) -> (String, String)? {
  let eq_idx = find_char(text, 0, '=')
  if eq_idx < 0 {
    return None
  }
  let key = trim_str(substr(text, 0, eq_idx))
  let value = trim_str(substr_from(text, eq_idx + 1))
  if key.length() == 0 {
    return None
  }
  Some((key, value))
}

///|
/// Parses a `term=weight` entry.
fn parse_term_weight(text : String) -> (String, Double)? {
  let eq_idx = find_last_eq(text)
  if eq_idx <= 0 {
    return None
  }
  let term = trim_str(substr(text, 0, eq_idx))
  if term.length() == 0 {
    return None
  }
  let weight_str = trim_str(substr_from(text, eq_idx + 1))
  if weight_str.length() == 0 {
    return None
  }
  let weight = parse_double(weight_str)
  // Verify it actually parsed (0.0 is valid for "0" or "0.0")
  if weight == 0.0 && weight_str != "0" && weight_str != "0.0" &&
    weight_str != "0.00" {
    return None
  }
  Some((term, weight))
}

///|
/// Finds the last `=` in a string. Used to separate term from weight
/// in case the term itself contains `=`.
fn find_last_eq(text : String) -> Int {
  let arr = text.to_array()
  let mut last = -1
  for i in 0..<arr.length() {
    if arr[i] == '=' {
      last = i
    }
  }
  last
}

///|
/// Parses a decimal number string into a Double.
/// Handles integers, decimals, and negative numbers.
fn parse_double(text : String) -> Double {
  let arr = text.to_array()
  if arr.length() == 0 {
    return 0.0
  }
  let mut is_negative = false
  let mut start = 0
  if arr[0] == '-' {
    is_negative = true
    start = 1
  }
  let mut integer_part = 0.0
  let mut i = start
  while i < arr.length() && arr[i] >= '0' && arr[i] <= '9' {
    integer_part = integer_part * 10.0 + (arr[i].to_int() - '0'.to_int()).to_double()
    i += 1
  }
  let mut decimal_part = 0.0
  if i < arr.length() && arr[i] == '.' {
    i += 1
    let mut divisor = 10.0
    while i < arr.length() && arr[i] >= '0' && arr[i] <= '9' {
      decimal_part += (arr[i].to_int() - '0'.to_int()).to_double() / divisor
      divisor *= 10.0
      i += 1
    }
  }
  let result = integer_part + decimal_part
  if is_negative {
    -result
  } else {
    result
  }
}
