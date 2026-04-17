///|
/// Walk up from the directory of `from_file` checking for a sibling file
/// whose basename is `marker`. Returns the directory containing the marker
/// (or an empty string when no ancestor contains it). Used by
/// `$findAncestor` to locate project roots (Cargo.toml, pyproject.toml, …).
fn walk_up_for_marker(
  from_file : String,
  marker : String,
  file_exists : (String) -> Bool,
) -> String {
  let mut dir = parent_dir_of(from_file)
  // Bound the walk to avoid pathological inputs; real projects are never
  // more than a few dozen directories deep.
  let mut hops = 0
  while hops < 64 {
    hops = hops + 1
    let candidate = if dir.length() == 0 { marker } else { dir + "/" + marker }
    if file_exists(candidate) {
      return dir
    }
    if dir.length() == 0 {
      return ""
    }
    let parent = parent_dir_of(dir)
    if parent == dir {
      return ""
    }
    dir = parent
  }
  ""
}

///|
fn parent_dir_of(path : String) -> String {
  let chars = path.to_array()
  let mut last = -1
  for i = 0; i < chars.length(); i = i + 1 {
    if chars[i] == '/' {
      last = i
    }
  }
  if last < 0 {
    return ""
  }
  let sb = StringBuilder::new()
  for i = 0; i < last; i = i + 1 {
    sb.write_char(chars[i])
  }
  sb.to_string()
}

///|
/// Checks if a value is truthy according to KGF semantics.
/// - null/undefined -> false
/// - boolean -> itself
/// - empty string -> false
/// - empty array -> false
/// - other -> true
pub fn is_truthy(v : Json) -> Bool {
  match v {
    Null => false
    True => true
    False => false
    String(s) => s.length() > 0
    Array(arr) => arr.length() > 0
    _ => true
  }
}

///|
/// Converts a Json value to a string.
fn json_to_string(v : Json) -> String {
  match v {
    Null => ""
    True => "true"
    False => "false"
    String(s) => s
    Number(n, ..) => n.to_string()
    Array(_) => v.stringify()
    Object(_) => v.stringify()
  }
}

///|
/// Converts a Json value to a number.
fn json_to_number(v : Json) -> Double {
  match v {
    Null => 0.0
    True => 1.0
    False => 0.0
    Number(n, ..) => n
    String(s) => {
      let result : Double = @string.parse_double(s) catch { _ => 0.0 }
      result
    }
    _ => 0.0
  }
}

///|
/// Evaluates a semantic expression and returns a Json value.
pub fn eval_expr(expr : @types.SemExpr, env : Env, ctx : SemEvalCtx) -> Json {
  match expr {
    Str(value) => value.to_json()
    Num(value) => value.to_json()
    Bool(value) => value.to_json()
    Null => Json::null()
    Var(name) => eval_var(name, env, ctx)
    Call(name, args) => eval_call(name, args, env, ctx)
    Func(name, args) => eval_func(name, args, env, ctx)
  }
}

///|
/// Evaluates a variable reference.
fn eval_var(name : String, env : Env, ctx : SemEvalCtx) -> Json {
  // Check built-in variables first
  if name == "file" {
    return ctx.file.to_json()
  }
  if name == "root" {
    return ctx.root.to_json()
  }
  if name == "language" {
    return ctx.language.to_json()
  }
  // Check locals and labels
  match env.get(name) {
    Some(v) => v
    None => Json::null()
  }
}

///|
/// Evaluates a special call expression ($resolve, $scope, etc.).
fn eval_call(
  name : String,
  args : Array[@types.SemExpr],
  env : Env,
  ctx : SemEvalCtx,
) -> Json {
  let evaluated_args = args.map(fn(e) { eval_expr(e, env, ctx) })
  match name {
    "resolve" => {
      let mod = if evaluated_args.length() > 0 {
        json_to_string(evaluated_args[0])
      } else {
        ""
      }
      let result = @resolver.resolve_module_cached(
        ctx.resolution_cache,
        ctx.spec.get_resolver(),
        ctx.language,
        ctx.file,
        mod,
        ctx.root,
        ctx.file_exists,
        ctx.read_file,
      )
      result.to_string().to_json()
    }
    "resolveFrom" => {
      // $resolveFrom(base_dir, path) — resolve `path` against a caller-
      // chosen base directory (as opposed to $resolve, which always uses
      // the current file's dir). Needed for language constructs where the
      // base is not the importing file — e.g. Rust's `use crate::..`
      // (resolve against the crate root + src), or Python's
      // `from ..pkg import x` (resolve against an ancestor of the source
      // file). The resolver chain remains the spec's own so all
      // ext/manifest/marker steps apply.
      let base_dir = if evaluated_args.length() > 0 {
        json_to_string(evaluated_args[0])
      } else {
        ""
      }
      let mod = if evaluated_args.length() > 1 {
        json_to_string(evaluated_args[1])
      } else {
        ""
      }
      // Rewrite the module path into a relative form anchored at base_dir
      // so the resolver picks `base_dir/...` as its base_path. The resolver
      // recognises "./"-prefixed paths and uses `dirname(from_file)` for
      // them, so we inject a pseudo-file inside base_dir.
      let rebased_mod = "./" + mod
      let pseudo_from = if base_dir.length() == 0 {
        ctx.file
      } else {
        base_dir + "/anchor"
      }
      let result = @resolver.resolve_module_cached(
        ctx.resolution_cache,
        ctx.spec.get_resolver(),
        ctx.language,
        pseudo_from,
        rebased_mod,
        ctx.root,
        ctx.file_exists,
        ctx.read_file,
      )
      result.to_string().to_json()
    }
    "findAncestor" => {
      // $findAncestor(marker) — walk up from the current file's directory
      // until a file named `marker` exists; returns the directory path
      // that contains the marker, or an empty string if none is found.
      // Used by language specs whose `use`/`import` semantics resolve
      // against a project-root marker (Cargo.toml, pyproject.toml, etc.).
      let marker = if evaluated_args.length() > 0 {
        json_to_string(evaluated_args[0])
      } else {
        ""
      }
      if marker.length() == 0 {
        return "".to_json()
      }
      walk_up_for_marker(ctx.file, marker, ctx.file_exists).to_json()
    }
    "scope" => {
      let ns = if evaluated_args.length() > 0 {
        json_to_string(evaluated_args[0])
      } else {
        "value"
      }
      let id = if evaluated_args.length() > 1 {
        json_to_string(evaluated_args[1])
      } else {
        ""
      }
      match ctx.lookup_scope(ns, id) {
        Some(v) => v.to_json()
        None => Json::null()
      }
    }
    "callId" =>
      match ctx.current_call_id() {
        Some(id) => id.to_json()
        None => Json::null()
      }
    "autoSym" => ctx.next_sym_id().to_json()
    "autoCall" => ctx.next_call_id().to_json()
    "collectRefs" => {
      let refs = ctx.collect_refs()
      let json_refs : Array[Json] = refs.map(fn(m) { Json::object(m) })
      Json::array(json_refs)
    }
    _ => Json::null()
  }
}

///|
/// Evaluates a function expression (concat, obj, etc.).
fn eval_func(
  name : String,
  args : Array[@types.SemExpr],
  env : Env,
  ctx : SemEvalCtx,
) -> Json {
  // Special handling for children() - needs access to label name before evaluation
  if name == "children" && args.length() == 1 {
    match args[0] {
      Var(label_name) => {
        // Look for ${labelName}_children in labels
        let children_key = label_name + "_children"
        match env.labels.get(children_key) {
          Some(Array(children)) => return Json::array(children)
          _ => ()
        }
        // Fallback to _children
        match env.labels.get("_children") {
          Some(Array(children)) => return Json::array(children)
          _ => return Json::array([])
        }
      }
      _ => ()
    }
  }
  let evaluated_args = args.map(fn(e) { eval_expr(e, env, ctx) })
  match name {
    "concat" => {
      let sb = StringBuilder::new()
      for arg in evaluated_args {
        sb.write_string(json_to_string(arg))
      }
      sb.to_string().to_json()
    }
    "obj" => eval_func_obj(evaluated_args)
    "coalesce" =>
      if evaluated_args.length() > 0 && !(evaluated_args[0] is Null) {
        evaluated_args[0]
      } else if evaluated_args.length() > 1 {
        evaluated_args[1]
      } else {
        Json::null()
      }
    "not" => {
      let val = if evaluated_args.length() > 0 {
        evaluated_args[0]
      } else {
        Json::null()
      }
      (!is_truthy(val)).to_json()
    }
    "eq" => {
      let a = if evaluated_args.length() > 0 {
        json_to_string(evaluated_args[0])
      } else {
        ""
      }
      let b = if evaluated_args.length() > 1 {
        json_to_string(evaluated_args[1])
      } else {
        ""
      }
      (a == b).to_json()
    }
    "add" => {
      let a = if evaluated_args.length() > 0 {
        json_to_number(evaluated_args[0])
      } else {
        0.0
      }
      let b = if evaluated_args.length() > 1 {
        json_to_number(evaluated_args[1])
      } else {
        0.0
      }
      (a + b).to_json()
    }
    "sub" => {
      let a = if evaluated_args.length() > 0 {
        json_to_number(evaluated_args[0])
      } else {
        0.0
      }
      let b = if evaluated_args.length() > 1 {
        json_to_number(evaluated_args[1])
      } else {
        0.0
      }
      (a - b).to_json()
    }
    "mul" => {
      let a = if evaluated_args.length() > 0 {
        json_to_number(evaluated_args[0])
      } else {
        0.0
      }
      let b = if evaluated_args.length() > 1 {
        json_to_number(evaluated_args[1])
      } else {
        0.0
      }
      (a * b).to_json()
    }
    "div" => {
      let a = if evaluated_args.length() > 0 {
        json_to_number(evaluated_args[0])
      } else {
        0.0
      }
      let b = if evaluated_args.length() > 1 {
        json_to_number(evaluated_args[1])
      } else {
        0.0
      }
      if b == 0.0 {
        Json::null()
      } else {
        (a / b).to_json()
      }
    }
    "floor" => {
      let n = if evaluated_args.length() > 0 {
        json_to_number(evaluated_args[0])
      } else {
        0.0
      }
      n.floor().to_json()
    }
    "hexToInt" => eval_func_hex_to_int(evaluated_args)
    "slice" => eval_func_slice(evaluated_args)
    "stripQuotes" => eval_func_strip_quotes(evaluated_args)
    "first" => eval_func_first(evaluated_args)
    "last" => eval_func_last(evaluated_args)
    "toUpper" => eval_func_to_upper(evaluated_args)
    "toLower" => eval_func_to_lower(evaluated_args)
    "trim" => eval_func_trim(evaluated_args)
    "containsStr" => eval_func_contains_str(evaluated_args)
    "startsWith" => eval_func_starts_with(evaluated_args)
    "beforeFirst" => eval_func_before_first(evaluated_args)
    "afterFirst" => eval_func_after_first(evaluated_args)
    "digits" => eval_func_digits(evaluated_args)
    "countOccurrences" => eval_func_count_occurrences(evaluated_args)
    "collectLinesAfterPrefixes" =>
      eval_func_collect_lines_after_prefixes(evaluated_args)
    "regexCaptures" => eval_func_regex_captures(evaluated_args)
    "regexPairs" => eval_func_regex_pairs(evaluated_args)
    "cond" => eval_func_cond(evaluated_args)
    "children" =>
      // Fallback for children() when not a simple var
      if evaluated_args.length() > 0 {
        match evaluated_args[0] {
          Array(arr) => Json::array(arr)
          _ =>
            // Check for _children in labels
            match env.labels.get("_children") {
              Some(Array(children)) => Json::array(children)
              _ => Json::array([])
            }
        }
      } else {
        Json::array([])
      }
    _ => Json::null()
  }
}

///|
fn json_to_int(v : Json) -> Int {
  match v {
    Number(n, ..) => n.to_int()
    String(s) => @string.parse_int(s) catch { _ => 0 }
    True => 1
    _ => 0
  }
}

///|
fn json_to_bool(v : Json) -> Bool {
  match v {
    True => true
    False => false
    Number(n, ..) => n != 0.0
    String(s) => s == "true" || s == "1"
    _ => false
  }
}

///|
fn unique_strings(values : Array[String]) -> Array[String] {
  let result : Array[String] = []
  for value in values {
    if value.length() > 0 && !result.contains(value) {
      result.push(value)
    }
  }
  result
}

///|
fn eval_func_regex_captures(args : Array[Json]) -> Json {
  let text = if args.length() > 0 { json_to_string(args[0]) } else { "" }
  let pattern = if args.length() > 1 { json_to_string(args[1]) } else { "" }
  let group = if args.length() > 2 { json_to_int(args[2]) } else { 0 }
  let case_insensitive = if args.length() > 3 {
    json_to_bool(args[3])
  } else {
    false
  }
  if pattern.length() == 0 {
    return Json::array([])
  }
  let values : Array[String] = []
  for matched in @regexp.find_pattern_captures(pattern, text, case_insensitive~) {
    let value = if group <= 0 {
      matched.text
    } else if group <= matched.captures.length() {
      matched.captures[group - 1]
    } else {
      ""
    }
    if value.length() > 0 {
      values.push(value)
    }
  }
  Json::array(unique_strings(values).map(fn(value) { value.to_json() }))
}

///|
fn eval_func_regex_pairs(args : Array[Json]) -> Json {
  let text = if args.length() > 0 { json_to_string(args[0]) } else { "" }
  let pattern = if args.length() > 1 { json_to_string(args[1]) } else { "" }
  let key_group = if args.length() > 2 { json_to_int(args[2]) } else { 1 }
  let value_group = if args.length() > 3 { json_to_int(args[3]) } else { 2 }
  let case_insensitive = if args.length() > 4 {
    json_to_bool(args[4])
  } else {
    false
  }
  if pattern.length() == 0 {
    return Json::array([])
  }
  let seen : Map[String, Bool] = {}
  let values : Array[Json] = []
  for matched in @regexp.find_pattern_captures(pattern, text, case_insensitive~) {
    if key_group <= 0 ||
      value_group <= 0 ||
      key_group > matched.captures.length() ||
      value_group > matched.captures.length() {
      continue
    }
    let key = matched.captures[key_group - 1]
    let value = matched.captures[value_group - 1]
    if key.length() == 0 || value.length() == 0 {
      continue
    }
    let dedupe = key + "\u0001" + value
    if seen.contains(dedupe) {
      continue
    }
    seen.set(dedupe, true)
    values.push(
      Json::object({ "label": key.to_json(), "literal": value.to_json() }),
    )
  }
  Json::array(values)
}

///|
/// Evaluates the obj() function to create an object from key-value pairs.
/// Null values are skipped — obj("a", "1", "b", null) produces {"a": "1"}.
fn eval_func_obj(args : Array[Json]) -> Json {
  let obj : Map[String, Json] = {}
  let n = args.length()
  for i = 0; i < n; i = i + 2 {
    let key = json_to_string(args[i])
    let value = if i + 1 < n { args[i + 1] } else { Json::null() }
    if !(value is Null) {
      obj.set(key, value)
    }
  }
  Json::object(obj)
}

///|
/// Evaluates the hexToInt() function.
fn eval_func_hex_to_int(args : Array[Json]) -> Json {
  if args.length() == 0 {
    return Json::null()
  }
  match args[0] {
    String(s) => {
      let trimmed = trim_string(s)
      if !is_valid_hex(trimmed) {
        return Json::null()
      }
      match parse_hex(trimmed) {
        Some(n) => n.to_double().to_json()
        None => Json::null()
      }
    }
    _ => Json::null()
  }
}

///|
/// Trims leading and trailing whitespace from a string.
fn trim_string(s : String) -> String {
  let chars = s.to_array()
  let mut start = 0
  let mut end = chars.length()
  while start < end && is_whitespace(chars[start]) {
    start = start + 1
  }
  while end > start && is_whitespace(chars[end - 1]) {
    end = end - 1
  }
  if start >= end {
    return ""
  }
  let sb = StringBuilder::new()
  for i = start; i < end; i = i + 1 {
    sb.write_char(chars[i])
  }
  sb.to_string()
}

///|
/// Checks if a character is whitespace.
fn is_whitespace(c : Char) -> Bool {
  c == ' ' || c == '\t' || c == '\n' || c == '\r'
}

///|
/// Checks if a string is a valid hexadecimal number.
fn is_valid_hex(s : String) -> Bool {
  if s.length() == 0 {
    return false
  }
  for c in s {
    if !is_hex_char(c) {
      return false
    }
  }
  true
}

///|
/// Checks if a character is a valid hex digit.
fn is_hex_char(c : Char) -> Bool {
  (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F')
}

///|
/// Parses a hexadecimal string to an integer.
fn parse_hex(s : String) -> Int? {
  let mut result = 0
  for c in s {
    let digit = hex_char_value(c)
    match digit {
      Some(d) => result = result * 16 + d
      None => return None
    }
  }
  Some(result)
}

///|
/// Gets the numeric value of a hex character.
fn hex_char_value(c : Char) -> Int? {
  if c >= '0' && c <= '9' {
    Some(c.to_int() - '0'.to_int())
  } else if c >= 'a' && c <= 'f' {
    Some(c.to_int() - 'a'.to_int() + 10)
  } else if c >= 'A' && c <= 'F' {
    Some(c.to_int() - 'A'.to_int() + 10)
  } else {
    None
  }
}

///|
/// Evaluates the slice() function.
fn eval_func_slice(args : Array[Json]) -> Json {
  if args.length() < 3 {
    return Json::null()
  }
  match args[0] {
    String(s) => {
      let start = json_to_number(args[1]).to_int()
      let len = json_to_number(args[2]).to_int()
      if start < 0 || len < 0 {
        return Json::null()
      }
      let chars = s.to_array()
      if start > chars.length() {
        return "".to_json()
      }
      let end = if start + len > chars.length() {
        chars.length()
      } else {
        start + len
      }
      let sb = StringBuilder::new()
      for i = start; i < end; i = i + 1 {
        sb.write_char(chars[i])
      }
      sb.to_string().to_json()
    }
    _ => Json::null()
  }
}

///|
/// Evaluates the stripQuotes() function.
fn eval_func_strip_quotes(args : Array[Json]) -> Json {
  if args.length() == 0 {
    return "".to_json()
  }
  let s = json_to_string(args[0])
  if s.length() >= 2 {
    let chars = s.to_array()
    let first = chars[0]
    let last = chars[chars.length() - 1]
    if (first == '"' && last == '"') || (first == '\'' && last == '\'') {
      let sb = StringBuilder::new()
      for i = 1; i < chars.length() - 1; i = i + 1 {
        sb.write_char(chars[i])
      }
      return sb.to_string().to_json()
    }
  }
  s.to_json()
}

///|
/// Evaluates the first() function.
fn eval_func_first(args : Array[Json]) -> Json {
  if args.length() == 0 {
    return Json::null()
  }
  match args[0] {
    Array(arr) => if arr.length() > 0 { arr[0] } else { Json::null() }
    _ => Json::null()
  }
}

///|
/// Evaluates the last() function.
fn eval_func_last(args : Array[Json]) -> Json {
  if args.length() == 0 {
    return Json::null()
  }
  match args[0] {
    Array(arr) =>
      if arr.length() > 0 {
        arr[arr.length() - 1]
      } else {
        Json::null()
      }
    _ => Json::null()
  }
}

///|
/// Evaluates the toUpper() function.
/// Converts ASCII letters in the string to uppercase.
fn eval_func_to_upper(args : Array[Json]) -> Json {
  if args.length() == 0 {
    return "".to_json()
  }
  let s = json_to_string(args[0])
  let chars = s.to_array()
  let sb = StringBuilder::new()
  for c in chars {
    if c >= 'a' && c <= 'z' {
      sb.write_char(Int::unsafe_to_char(c.to_int() - 32))
    } else {
      sb.write_char(c)
    }
  }
  sb.to_string().to_json()
}

///|
/// Evaluates the toLower() function.
/// Converts ASCII letters in the string to lowercase.
fn eval_func_to_lower(args : Array[Json]) -> Json {
  if args.length() == 0 {
    return "".to_json()
  }
  let s = json_to_string(args[0])
  let chars = s.to_array()
  let sb = StringBuilder::new()
  for c in chars {
    if c >= 'A' && c <= 'Z' {
      sb.write_char(Int::unsafe_to_char(c.to_int() + 32))
    } else {
      sb.write_char(c)
    }
  }
  sb.to_string().to_json()
}

///|
fn eval_func_trim(args : Array[Json]) -> Json {
  if args.length() == 0 {
    return "".to_json()
  }
  trim_string(json_to_string(args[0])).to_json()
}

///|
fn eval_func_contains_str(args : Array[Json]) -> Json {
  if args.length() < 2 {
    return false.to_json()
  }
  json_to_string(args[0]).contains(json_to_string(args[1])).to_json()
}

///|
fn eval_func_starts_with(args : Array[Json]) -> Json {
  if args.length() < 2 {
    return false.to_json()
  }
  json_to_string(args[0]).has_prefix(json_to_string(args[1])).to_json()
}

///|
fn eval_func_before_first(args : Array[Json]) -> Json {
  if args.length() < 2 {
    return "".to_json()
  }
  let text = json_to_string(args[0])
  let delimiter = json_to_string(args[1])
  if delimiter.length() == 0 {
    return text.to_json()
  }
  let index = find_substring(text, delimiter)
  if index < 0 {
    text.to_json()
  } else {
    text[:index].to_string().to_json()
  }
}

///|
fn eval_func_after_first(args : Array[Json]) -> Json {
  if args.length() < 2 {
    return "".to_json()
  }
  let text = json_to_string(args[0])
  let delimiter = json_to_string(args[1])
  if delimiter.length() == 0 {
    return text.to_json()
  }
  let index = find_substring(text, delimiter)
  if index < 0 {
    "".to_json()
  } else {
    text[index + delimiter.length():text.length()].to_string().to_json()
  }
}

///|
fn eval_func_digits(args : Array[Json]) -> Json {
  if args.length() == 0 {
    return "".to_json()
  }
  let buf = StringBuilder::new()
  for ch in json_to_string(args[0]) {
    if ch >= '0' && ch <= '9' {
      buf.write_char(ch)
    }
  }
  buf.to_string().to_json()
}

///|
fn eval_func_count_occurrences(args : Array[Json]) -> Json {
  if args.length() < 2 {
    return 0.0.to_json()
  }
  let text = json_to_string(args[0])
  let needle = json_to_string(args[1])
  if needle.length() == 0 {
    return 0.0.to_json()
  }
  let text_chars = text.to_array()
  let needle_chars = needle.to_array()
  if needle_chars.length() > text_chars.length() {
    return 0.0.to_json()
  }
  let mut count = 0
  let mut i = 0
  while i <= text_chars.length() - needle_chars.length() {
    let mut matched = true
    for j = 0; j < needle_chars.length(); j = j + 1 {
      if text_chars[i + j] != needle_chars[j] {
        matched = false
        break
      }
    }
    if matched {
      count += 1
      i += needle_chars.length()
    } else {
      i += 1
    }
  }
  count.to_double().to_json()
}

///|
fn eval_func_collect_lines_after_prefixes(args : Array[Json]) -> Json {
  if args.length() < 2 {
    return Json::array([])
  }
  let text = json_to_string(args[0])
  let prefixes : Array[String] = []
  for i = 1; i < args.length(); i = i + 1 {
    prefixes.push(json_to_string(args[i]))
  }
  let result : Array[Json] = []
  for line in text.split("\n") {
    let trimmed = trim_string(line.to_string())
    for prefix in prefixes {
      if trimmed.has_prefix(prefix) {
        result.push(
          trim_string(trimmed[prefix.length():trimmed.length()].to_string()).to_json(),
        )
        break
      }
    }
  }
  Json::array(result)
}

///|
fn find_substring(text : String, needle : String) -> Int {
  let text_arr = text.to_array()
  let needle_arr = needle.to_array()
  if needle_arr.length() == 0 {
    return 0
  }
  if needle_arr.length() > text_arr.length() {
    return -1
  }
  for i = 0; i <= text_arr.length() - needle_arr.length(); i = i + 1 {
    let mut ok = true
    for j = 0; j < needle_arr.length(); j = j + 1 {
      if text_arr[i + j] != needle_arr[j] {
        ok = false
        break
      }
    }
    if ok {
      return i
    }
  }
  -1
}

///|
/// Evaluates the cond() function — conditional expression.
/// cond(condition, then_value) returns then_value if condition is truthy, null otherwise.
/// cond(condition, then_value, else_value) returns then_value or else_value.
/// Combined with obj()'s null-skipping, enables conditional attributes
/// without when/else duplication in KGF specs.
fn eval_func_cond(args : Array[Json]) -> Json {
  if args.length() < 2 {
    return Json::null()
  }
  if is_truthy(args[0]) {
    args[1]
  } else if args.length() >= 3 {
    args[2]
  } else {
    Json::null()
  }
}

// ── Known built-in registries (SoT) ─────────────────────
//
// These functions expose the set of names recognized by eval_call,
// eval_func, and eval_var. They are the single source of truth —
// check/check.mbt consumes them instead of maintaining a duplicate list.

///|
/// Returns true if `name` is a known context-dependent call ($resolve, $scope, etc.).
/// SoT: the match arms in eval_call above.
pub fn is_known_call(name : String) -> Bool {
  match name {
    "resolve"
    | "resolveFrom"
    | "findAncestor"
    | "scope"
    | "callId"
    | "autoSym"
    | "autoCall"
    | "collectRefs" => true
    _ => false
  }
}

///|
/// Returns true if `name` is a known pure built-in function (concat, obj, etc.).
/// SoT: the match arms in eval_func above.
pub fn is_known_func(name : String) -> Bool {
  match name {
    "concat"
    | "obj"
    | "coalesce"
    | "not"
    | "eq"
    | "add"
    | "sub"
    | "mul"
    | "div"
    | "floor"
    | "hexToInt"
    | "slice"
    | "stripQuotes"
    | "first"
    | "last"
    | "toUpper"
    | "toLower"
    | "trim"
    | "containsStr"
    | "startsWith"
    | "beforeFirst"
    | "afterFirst"
    | "digits"
    | "countOccurrences"
    | "collectLinesAfterPrefixes"
    | "regexCaptures"
    | "regexPairs"
    | "cond"
    | "children" => true
    _ => false
  }
}

///|
/// Returns true if `name` is a known built-in variable ($file, $root, etc.).
/// SoT: the if-chain in eval_var above.
pub fn is_known_builtin_var(name : String) -> Bool {
  match name {
    "file" | "root" | "language" => true
    _ => false
  }
}
