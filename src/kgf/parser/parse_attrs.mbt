///|
/// # KGF Attrs Section Syntax
///
/// The `=== attrs` section defines attribute actions that annotate parse tree
/// nodes. These actions drive symbol extraction and semantic analysis.
///
/// ## EBNF Grammar
///
/// ```ebnf
/// AttrsSection ::= AttrRule*
/// AttrRule     ::= "on" RuleName ":" ActionList NL
/// RuleName     ::= UPPER_IDENT              (* Grammar rule name *)
/// ActionList   ::= Action ( ";" Action )*
/// Action       ::= ActionKind ImplicitArg? KeyValuePair*
///
/// ActionKind   ::= "def" | "ref" | "call" | "argref"
///                | "import" | "reexport" | "scope"
/// ImplicitArg  ::= LOWER_IDENT              (* First positional = implicit id *)
/// KeyValuePair ::= Key "=" Value
/// Key          ::= "id" | "kind" | "ns" | "callee" | "module" | "push" | "pop"
/// Value        ::= IDENTIFIER | STRING
/// ```
///
/// ## Action Types
///
/// | Action | Purpose | Implicit Param |
/// |--------|---------|----------------|
/// | `def` | Define a symbol | `id` |
/// | `ref` | Reference a symbol | `name` |
/// | `call` | Function call | `callee` |
/// | `argref` | Argument reference | - |
/// | `import` | Module import | `module` |
/// | `reexport` | Re-export symbol | `module` |
/// | `scope` | Scope management | - |
///
/// ## Symbol Kinds
///
/// Common `kind=` values: `Function`, `Variable`, `Struct`, `Enum`, `Type`,
/// `Trait`, `Param`, `Field`, `Variant`, `Method`, `TypeAlias`
///
/// ## Namespace (`ns=`)
///
/// - `value` - Value namespace (functions, variables)
/// - `type` - Type namespace (types, traits)
///
/// ## Examples
///
/// ```kgf
/// === attrs
/// # Define function with id from 'fn_id' label, in value namespace
/// on FnDecl: def fn_id kind=Function ns=value
///
/// # Define struct with scope push (for nested fields)
/// on StructDecl: def struct_id kind=Struct; scope push=struct
///
/// # Reference variable in value namespace
/// on Primary: ref name ns=value
///
/// # Function call tracking
/// on CallExpr: call callee=callee
/// on Arg: argref
///
/// # Import statement
/// on ImportDecl: import module=path
///
/// # Multiple actions on same rule
/// on VarDecl: def id kind=Variable ns=value; scope pop
/// ```

///|
/// Parses simple one-line attribute actions per rule into structured form.
///
/// Syntax:
///   on RuleName: kind1 key1=val1; kind2; ...
pub fn parse_attrs(text : String) -> Map[String, Array[@types.AttrAction]] {
  let result : Map[String, Array[@types.AttrAction]] = {}
  let lines = split_lines(text)
  for line in lines {
    let ln = trim_str(line)
    // Skip empty lines and comments
    if ln.length() == 0 || ln.has_prefix("#") {
      continue
    }
    // Look for "on RuleName: actions"
    if ln.has_prefix("on ") {
      match parse_attr_line(ln) {
        Some((rule, actions)) => result.set(rule, actions)
        None => ()
      }
    }
  }
  result
}

///|
/// Parses a single attribute line: on RuleName: kind1 key1=val1; kind2; ...
fn parse_attr_line(line : String) -> (String, Array[@types.AttrAction])? {
  // Skip "on "
  let after_on = skip_whitespace(line, 3)
  // Read rule name
  let (rule, after_rule) = read_identifier(line, after_on)
  guard rule.length() > 0 else { return None }
  // Skip whitespace and find colon
  let colon_pos = skip_whitespace(line, after_rule)
  guard colon_pos < line.length() && char_at(line, colon_pos) == ':' else {
    return None
  }
  // Get actions string after colon
  let actions_str = trim_str(substr_from(line, colon_pos + 1))
  // Parse actions separated by semicolon
  let actions = parse_action_list(actions_str)
  Some((rule, actions))
}

///|
/// Parses a list of actions separated by semicolons.
fn parse_action_list(text : String) -> Array[@types.AttrAction] {
  let result : Array[@types.AttrAction] = []
  let parts = split_by_char(text, ';')
  for part in parts {
    let trimmed = trim_str(part)
    // Skip empty parts and inline comments
    if trimmed.length() > 0 && !trimmed.has_prefix("#") {
      result.push(parse_single_action(trimmed))
    }
  }
  result
}

///|
/// Splits text by a character.
fn split_by_char(text : String, delim : Char) -> Array[String] {
  let result : Array[String] = []
  let buf = StringBuilder::new()
  for c in text {
    if c == delim {
      result.push(buf.to_string())
      buf.reset()
    } else {
      buf.write_char(c)
    }
  }
  result.push(buf.to_string())
  result
}

///|
/// Parses a single action: kind [implicit_id] key1=val1 key2=val2 ...
/// For example: def id kind=Variable ns=value
///   - kind = "def"
///   - implicit "id" param (first non-key=value token) = "id" (label name)
///   - kind = "Variable"
///   - ns = "value"
fn parse_single_action(text : String) -> @types.AttrAction {
  let parts = split_by_space(text)
  guard parts.length() > 0 else { return @types.AttrAction::new("") }
  let kind = parts[0]
  let params : Map[String, String] = {}
  let mut has_implicit_id = false
  for i in 1..<parts.length() {
    let part = parts[i]
    match parse_key_value(part) {
      Some((k, v)) => params.set(k, v)
      None =>
        // First non-key=value token is the implicit id/name parameter
        if !has_implicit_id {
          // For "def" action, implicit param is "id"
          // For "ref" action, implicit param is "name"
          // For "call" action, implicit param is "callee"
          let param_name = match kind {
            "def" => "id"
            "ref" => "name"
            "call" => "callee"
            "import" | "reexport" => "module"
            _ => "id"
          }
          params.set(param_name, part)
          has_implicit_id = true
        }
    }
  }
  @types.AttrAction::new(kind, params~)
}

///|
/// Splits text by whitespace.
fn split_by_space(text : String) -> Array[String] {
  let result : Array[String] = []
  let buf = StringBuilder::new()
  for c in text {
    if is_whitespace(c) {
      let part = buf.to_string()
      if part.length() > 0 {
        result.push(part)
      }
      buf.reset()
    } else {
      buf.write_char(c)
    }
  }
  let part = buf.to_string()
  if part.length() > 0 {
    result.push(part)
  }
  result
}

///|
/// Parses a key=value pair.
fn parse_key_value(text : String) -> (String, String)? {
  let eq_pos = find_char(text, 0, '=')
  guard eq_pos > 0 else { return None }
  let key = substr(text, 0, eq_pos)
  let value = substr_from(text, eq_pos + 1)
  Some((key, value))
}
