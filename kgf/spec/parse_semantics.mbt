///|
/// Parses semantics section into rule -> on-blocks mapping.
/// Minimal parser using line scanning and balanced braces.
/// Syntax:
///   on RuleName when condition {
///     statements
///   } else {
///     statements
///   }
pub fn parse_semantics(text : String) -> Map[String, Array[@types.SemOnBlock]]? {
  let src = trim_str(text)
  if src.length() == 0 {
    return None
  }
  let blocks = parse_on_blocks(src)
  if blocks.is_empty() {
    return None
  }
  let result : Map[String, Array[@types.SemOnBlock]] = {}
  for block in blocks {
    let rule = block.get_rule()
    match result.get(rule) {
      Some(arr) => arr.push(block)
      None => result.set(rule, [block])
    }
  }
  Some(result)
}

///|
/// Parses all on-blocks from the source.
fn parse_on_blocks(src : String) -> Array[@types.SemOnBlock] {
  let result : Array[@types.SemOnBlock] = []
  let arr = src.to_array()
  let mut pos = 0
  while pos < src.length() {
    pos = skip_ws(arr, pos)
    if pos >= src.length() {
      break
    }
    // Check for "on" keyword
    if not(starts_with_at(src, pos, "on")) {
      pos += 1
      continue
    }
    // Check it's not part of a larger identifier
    let after_on = pos + 2
    if after_on < src.length() && is_ident_char(arr[after_on]) {
      pos += 1
      continue
    }
    // Parse the on-block
    let (block, next_pos) = parse_single_on_block(src, arr, pos)
    match block {
      Some(b) => result.push(b)
      None => ()
    }
    pos = next_pos
  }
  result
}

///|
/// Parses a single on-block starting at pos.
fn parse_single_on_block(
  src : String,
  arr : Array[Char],
  start : Int,
) -> (@types.SemOnBlock?, Int) {
  // Skip "on"
  let mut pos = skip_ws(arr, start + 2)
  // Read rule name
  let (rule, after_rule) = read_ident_at(src, arr, pos)
  if rule.length() == 0 {
    return (None, start + 1)
  }
  pos = skip_ws(arr, after_rule)
  // Check for "when"
  let mut when_cond : @types.SemExpr? = None
  if starts_with_at(src, pos, "when") {
    pos = skip_ws(arr, pos + 4)
    // Find opening brace to get condition
    let brace_pos = find_char(src, pos, '{')
    if brace_pos > pos {
      let cond_str = trim_str(substr(src, pos, brace_pos))
      if cond_str.length() > 0 {
        when_cond = Some(parse_expr(cond_str))
      }
      pos = brace_pos
    }
  }
  // Parse then block
  let (then_body, after_then) = read_brace_block(src, arr, pos)
  let then_stmts = parse_block_stmts(then_body)
  pos = skip_ws(arr, after_then)
  // Check for "else"
  let mut else_stmts : Array[@types.SemStmt]? = None
  if starts_with_at(src, pos, "else") {
    pos = skip_ws(arr, pos + 4)
    let (else_body, after_else) = read_brace_block(src, arr, pos)
    else_stmts = Some(parse_block_stmts(else_body))
    pos = after_else
  }
  let block = @types.SemOnBlock::new(rule, then_stmts, when_cond~, else_stmts~)
  (Some(block), pos)
}

///|
/// Skips whitespace characters.
fn skip_ws(arr : Array[Char], start : Int) -> Int {
  let mut i = start
  while i < arr.length() && is_whitespace(arr[i]) {
    i += 1
  }
  i
}

///|
/// Reads an identifier at the given position.
fn read_ident_at(src : String, arr : Array[Char], start : Int) -> (String, Int) {
  if start >= arr.length() || not(is_ident_start(arr[start])) {
    return ("", start)
  }
  let mut end = start + 1
  while end < arr.length() && is_ident_char(arr[end]) {
    end += 1
  }
  (substr(src, start, end), end)
}

///|
/// Reads a brace-delimited block, handling nested braces.
fn read_brace_block(
  src : String,
  arr : Array[Char],
  start : Int,
) -> (String, Int) {
  let pos = skip_ws(arr, start)
  if pos >= arr.length() || arr[pos] != '{' {
    return ("", start)
  }
  let mut depth = 0
  let mut i = pos
  while i < arr.length() {
    let c = arr[i]
    if c == '{' {
      depth += 1
    } else if c == '}' {
      depth -= 1
      if depth == 0 {
        let body = substr(src, pos + 1, i)
        return (body, i + 1)
      }
    }
    i += 1
  }
  // Unmatched brace
  ("", start)
}

///|
/// Parses statements inside a block.
fn parse_block_stmts(body : String) -> Array[@types.SemStmt] {
  let lines = split_lines(body)
  let result : Array[@types.SemStmt] = []
  for line in lines {
    let ln = trim_str(line)
    if ln.length() == 0 || starts_with(ln, "#") {
      continue
    }
    match parse_stmt(ln) {
      Some(stmt) => result.push(stmt)
      None => ()
    }
  }
  result
}

///|
/// Parses a single statement.
fn parse_stmt(ln : String) -> @types.SemStmt? {
  if starts_with(ln, "edge ") {
    return parse_edge_stmt(ln)
  }
  if starts_with(ln, "bind ") {
    return parse_bind_stmt(ln)
  }
  if starts_with(ln, "note ") {
    return parse_note_stmt(ln)
  }
  if starts_with(ln, "let ") {
    return parse_let_stmt(ln)
  }
  if starts_with(ln, "module ") {
    return parse_module_stmt(ln)
  }
  None
}

///|
/// Parses: edge kind from <expr> to <expr> [attrs <expr>]
fn parse_edge_stmt(ln : String) -> @types.SemStmt? {
  let arr = ln.to_array()
  // Skip "edge "
  let mut pos = skip_ws(arr, 5)
  // Read edge kind
  let (kind, after_kind) = read_ident_at(ln, arr, pos)
  if kind.length() == 0 {
    return None
  }
  pos = skip_ws(arr, after_kind)
  // Expect "from"
  if not(starts_with_at(ln, pos, "from")) {
    return None
  }
  pos = skip_ws(arr, pos + 4)
  // Read from expression (until "to")
  let to_pos = find_keyword(ln, pos, "to")
  if to_pos < 0 {
    return None
  }
  let from_str = trim_str(substr(ln, pos, to_pos))
  let from_expr = parse_expr(from_str)
  pos = skip_ws(arr, to_pos + 2)
  // Read to expression (until "attrs" or end)
  let attrs_pos = find_keyword(ln, pos, "attrs")
  let (to_str, attrs_expr) = if attrs_pos > 0 {
    let to = trim_str(substr(ln, pos, attrs_pos))
    let attrs_str = trim_str(substr_from(ln, attrs_pos + 5))
    (to, Some(parse_expr(attrs_str)))
  } else {
    (trim_str(substr_from(ln, pos)), None)
  }
  let to_expr = parse_expr(to_str)
  Some(@types.SemStmt::edge(kind, from_expr, to_expr, attrs=attrs_expr))
}

///|
/// Parses: bind ns <expr> name <expr> to <expr>
fn parse_bind_stmt(ln : String) -> @types.SemStmt? {
  let arr = ln.to_array()
  // Skip "bind "
  let mut pos = skip_ws(arr, 5)
  // Expect "ns"
  if not(starts_with_at(ln, pos, "ns")) {
    return None
  }
  pos = skip_ws(arr, pos + 2)
  // Find "name"
  let name_pos = find_keyword(ln, pos, "name")
  if name_pos < 0 {
    return None
  }
  let ns_str = trim_str(substr(ln, pos, name_pos))
  let ns_expr = parse_expr(ns_str)
  pos = skip_ws(arr, name_pos + 4)
  // Find "to"
  let to_pos = find_keyword(ln, pos, "to")
  if to_pos < 0 {
    return None
  }
  let name_str = trim_str(substr(ln, pos, to_pos))
  let name_expr = parse_expr(name_str)
  let to_str = trim_str(substr_from(ln, to_pos + 2))
  let to_expr = parse_expr(to_str)
  Some(@types.SemStmt::bind(ns_expr, name_expr, to_expr))
}

///|
/// Parses: note <type> [payload <expr>]
fn parse_note_stmt(ln : String) -> @types.SemStmt? {
  let arr = ln.to_array()
  // Skip "note "
  let mut pos = skip_ws(arr, 5)
  // Read note type
  let (note_type, after_type) = read_ident_at(ln, arr, pos)
  if note_type.length() == 0 {
    return None
  }
  pos = skip_ws(arr, after_type)
  // Check for "payload"
  let payload = if starts_with_at(ln, pos, "payload") {
    let payload_str = trim_str(substr_from(ln, pos + 7))
    Some(parse_expr(payload_str))
  } else {
    None
  }
  Some(@types.SemStmt::note(note_type, payload~))
}

///|
/// Parses: let <id> = <expr>
fn parse_let_stmt(ln : String) -> @types.SemStmt? {
  let arr = ln.to_array()
  // Skip "let "
  let mut pos = skip_ws(arr, 4)
  // Read identifier
  let (id, after_id) = read_ident_at(ln, arr, pos)
  if id.length() == 0 {
    return None
  }
  pos = skip_ws(arr, after_id)
  // Expect "="
  if pos >= ln.length() || arr[pos] != '=' {
    return None
  }
  let value_str = trim_str(substr_from(ln, pos + 1))
  let value_expr = parse_expr(value_str)
  Some(@types.SemStmt::let_(id, value_expr))
}

///|
/// Parses: module <id> [file <expr>]
fn parse_module_stmt(ln : String) -> @types.SemStmt? {
  // Skip "module "
  let pos = skip_whitespace(ln, 7)
  // Find "file" keyword or end
  let file_pos = find_keyword(ln, pos, "file")
  let (id_str, file_expr) = if file_pos > 0 {
    let id = trim_str(substr(ln, pos, file_pos))
    let file_str = trim_str(substr_from(ln, file_pos + 4))
    (id, Some(parse_expr(file_str)))
  } else {
    (trim_str(substr_from(ln, pos)), None)
  }
  let id_expr = parse_expr(id_str)
  Some(@types.SemStmt::mod_(id_expr, file=file_expr))
}

///|
/// Finds a keyword position, ensuring it's a separate word.
fn find_keyword(src : String, start : Int, keyword : String) -> Int {
  let arr = src.to_array()
  let mut i = start
  while i < src.length() {
    if starts_with_at(src, i, keyword) {
      // Check it's not part of a larger identifier
      let before_ok = i == 0 || not(is_ident_char(arr[i - 1]))
      let after_pos = i + keyword.length()
      let after_ok = after_pos >= src.length() ||
        not(is_ident_char(arr[after_pos]))
      if before_ok && after_ok {
        return i
      }
    }
    i += 1
  }
  -1
}

///|
/// Parses an expression.
fn parse_expr(s : String) -> @types.SemExpr {
  let trimmed = trim_str(s)
  // Boolean literals
  if trimmed == "true" {
    return @types.SemExpr::bool(true)
  }
  if trimmed == "false" {
    return @types.SemExpr::bool(false)
  }
  // Null literal
  if trimmed == "null" {
    return @types.SemExpr::null()
  }
  // Number literal
  if is_number(trimmed) {
    return @types.SemExpr::num(parse_number(trimmed))
  }
  // String literal
  if trimmed.length() >= 2 {
    let arr = trimmed.to_array()
    if arr[0] == '"' && arr[trimmed.length() - 1] == '"' {
      let content = substr(trimmed, 1, trimmed.length() - 1)
      return @types.SemExpr::str(content)
    }
  }
  // $call(args) - special call syntax
  if starts_with(trimmed, "$") && has_call_syntax(trimmed, 1) {
    let (name, args) = parse_call_parts(trimmed, 1)
    return @types.SemExpr::call(name, args)
  }
  // func(args) - function syntax
  if has_call_syntax(trimmed, 0) {
    let (name, args) = parse_call_parts(trimmed, 0)
    return @types.SemExpr::func(name, args)
  }
  // $variable
  if starts_with(trimmed, "$") {
    return @types.SemExpr::variable(substr_from(trimmed, 1))
  }
  // Plain identifier as variable
  if is_identifier(trimmed) {
    return @types.SemExpr::variable(trimmed)
  }
  // Fallback to string
  @types.SemExpr::str(trimmed)
}

///|
/// Checks if a string represents a number.
fn is_number(s : String) -> Bool {
  if s.length() == 0 {
    return false
  }
  let arr = s.to_array()
  let mut has_digit = false
  let mut i = 0
  if arr[0] == '-' || arr[0] == '+' {
    i = 1
  }
  while i < arr.length() {
    let c = arr[i]
    if is_digit(c) {
      has_digit = true
    } else if c == '.' {
      // Allow one decimal point
      ()
    } else {
      return false
    }
    i += 1
  }
  has_digit
}

///|
/// Parses a number string to double.
fn parse_number(s : String) -> Double {
  // Simple integer parsing for now
  let trimmed = trim_str(s)
  let arr = trimmed.to_array()
  let mut result = 0.0
  let mut is_negative = false
  let mut i = 0
  if arr[0] == '-' {
    is_negative = true
    i = 1
  } else if arr[0] == '+' {
    i = 1
  }
  let mut after_decimal = false
  let mut decimal_factor = 0.1
  while i < arr.length() {
    let c = arr[i]
    if c == '.' {
      after_decimal = true
    } else if is_digit(c) {
      let digit = (c.to_int() - '0'.to_int()).to_double()
      if after_decimal {
        result = result + digit * decimal_factor
        decimal_factor = decimal_factor * 0.1
      } else {
        result = result * 10.0 + digit
      }
    }
    i += 1
  }
  if is_negative {
    -result
  } else {
    result
  }
}

///|
/// Checks if a string is a valid identifier.
fn is_identifier(s : String) -> Bool {
  if s.length() == 0 {
    return false
  }
  let arr = s.to_array()
  if not(is_ident_start(arr[0])) {
    return false
  }
  for i in 1..<arr.length() {
    if not(is_ident_char(arr[i])) {
      return false
    }
  }
  true
}

///|
/// Checks if a string has function call syntax starting at offset.
fn has_call_syntax(s : String, offset : Int) -> Bool {
  let arr = s.to_array()
  if offset >= arr.length() {
    return false
  }
  // Must start with identifier
  if not(is_ident_start(arr[offset])) {
    return false
  }
  // Find opening paren
  let mut i = offset + 1
  while i < arr.length() && is_ident_char(arr[i]) {
    i += 1
  }
  if i >= arr.length() || arr[i] != '(' {
    return false
  }
  // Check ends with closing paren
  arr[arr.length() - 1] == ')'
}

///|
/// Parses function call parts (name and args) starting at offset.
fn parse_call_parts(
  s : String,
  offset : Int,
) -> (String, Array[@types.SemExpr]) {
  let paren_pos = find_char(s, offset, '(')
  if paren_pos < 0 {
    return ("", [])
  }
  let name = substr(s, offset, paren_pos)
  let args_str = substr(s, paren_pos + 1, s.length() - 1)
  let args = split_args(args_str)
  let parsed_args : Array[@types.SemExpr] = []
  for arg in args {
    parsed_args.push(parse_expr(arg))
  }
  (name, parsed_args)
}

///|
/// Splits argument list by commas, respecting nested parens and strings.
fn split_args(arglist : String) -> Array[String] {
  let result : Array[String] = []
  let buf = StringBuilder::new()
  let mut depth = 0
  let mut in_str = false
  for c in arglist {
    if c == '"' {
      in_str = not(in_str)
      buf.write_char(c)
    } else if not(in_str) && (c == '(' || c == '{') {
      depth += 1
      buf.write_char(c)
    } else if not(in_str) && (c == ')' || c == '}') {
      depth -= 1
      buf.write_char(c)
    } else if not(in_str) && depth == 0 && c == ',' {
      let part = trim_str(buf.to_string())
      if part.length() > 0 {
        result.push(part)
      }
      buf.reset()
    } else {
      buf.write_char(c)
    }
  }
  let last = trim_str(buf.to_string())
  if last.length() > 0 {
    result.push(last)
  }
  result
}
