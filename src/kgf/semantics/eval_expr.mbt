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
/// Evaluates the obj() function to create an object from key-value pairs.
fn eval_func_obj(args : Array[Json]) -> Json {
  let obj : Map[String, Json] = {}
  let n = args.length()
  for i = 0; i < n; i = i + 2 {
    let key = json_to_string(args[i])
    let value = if i + 1 < n { args[i + 1] } else { Json::null() }
    obj.set(key, value)
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
      if !(is_valid_hex(trimmed)) {
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
    if !(is_hex_char(c)) {
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
