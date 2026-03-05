///|
/// Evaluates attribute actions for a matched rule.
/// Attrs are simple annotations like: on VarItem: def id kind=Variable ns=value
/// This function converts them into graph operations (symbols, edges).
pub fn eval_attrs(
  actions : Array[@types.AttrAction],
  labels : Map[String, Json],
  ctx : SemEvalCtx,
) -> Unit {
  for action in actions {
    eval_single_attr(action, labels, ctx)
  }
}

///|
/// Evaluates a single attribute action.
fn eval_single_attr(
  action : @types.AttrAction,
  labels : Map[String, Json],
  ctx : SemEvalCtx,
) -> Unit {
  match action.get_kind() {
    "def" => eval_attr_def(action, labels, ctx)
    "ref" => eval_attr_ref(action, labels, ctx)
    "call" => eval_attr_call(action, labels, ctx)
    "argref" => eval_attr_argref(action, labels, ctx)
    "import" => eval_attr_import(action, labels, ctx)
    "reexport" => eval_attr_reexport(action, labels, ctx)
    "scope" => eval_attr_scope(action, labels, ctx)
    _ => ()
  }
}

///|
/// Clean doc text by removing ///| and /// prefixes from each line.
fn clean_doc_text(text : String) -> String {
  let result : Array[String] = []
  let mut i = 0
  let chars = text.to_array()
  let len = chars.length()
  while i < len {
    // Skip leading whitespace
    while i < len && (chars[i] == ' ' || chars[i] == '\t') {
      i = i + 1
    }
    // Check for ///| or ///
    if i + 4 <= len &&
      chars[i] == '/' &&
      chars[i + 1] == '/' &&
      chars[i + 2] == '/' &&
      chars[i + 3] == '|' {
      i = i + 4 // Skip ///|
      // Skip rest of line
      while i < len && chars[i] != '\n' {
        i = i + 1
      }
    } else if i + 3 <= len &&
      chars[i] == '/' &&
      chars[i + 1] == '/' &&
      chars[i + 2] == '/' {
      i = i + 3 // Skip ///
      // Skip optional space after ///
      if i < len && chars[i] == ' ' {
        i = i + 1
      }
      // Collect text until newline
      let line_chars : Array[Char] = []
      while i < len && chars[i] != '\n' {
        line_chars.push(chars[i])
        i = i + 1
      }
      if line_chars.length() > 0 {
        result.push(String::from_array(line_chars))
      }
    } else {
      // Skip to next line
      while i < len && chars[i] != '\n' {
        i = i + 1
      }
    }
    // Skip newline
    if i < len && chars[i] == '\n' {
      i = i + 1
    }
  }
  result.join(" ")
}

///|
/// Evaluates a 'def' attribute: defines a symbol.
/// Syntax: def id kind=Variable ns=value
/// - First positional param or 'id' param: the label to get symbol name from
/// - 'kind': symbol kind (Function, Variable, TypeAlias, etc.)
/// - 'ns': namespace (value or type)
fn eval_attr_def(
  action : @types.AttrAction,
  labels : Map[String, Json],
  ctx : SemEvalCtx,
) -> Unit {
  let params = action.get_params()
  // Get the label name for the symbol name
  let label_name = match params.get("id") {
    Some(id) => id
    None => {
      // Find the first param that's not kind/ns (implicit id)
      let mut found = ""
      for entry in params {
        if entry.0 != "kind" && entry.0 != "ns" && entry.0 != "doc" {
          found = entry.1
          break
        }
      }
      if found.length() > 0 {
        found
      } else {
        "id"
      }
    }
  }
  // Get the symbol name from labels
  let name = match labels.get(label_name) {
    Some(String(s)) => s
    Some(json) => json_to_string(json)
    None => return // No name found, skip
  }
  if name.length() == 0 {
    return
  }
  // Get kind and namespace
  let kind = params.get("kind").unwrap_or("Unknown")
  let ns = params.get("ns").unwrap_or("value")
  // Get doc text if specified (look for label_name_text for accumulated text)
  let doc : String? = match params.get("doc") {
    Some(doc_label) => {
      let text_label = doc_label + "_text"
      match labels.get(text_label) {
        Some(String(s)) => {
          // Clean up the doc text: remove ///| and /// prefixes
          let cleaned = clean_doc_text(s)
          if cleaned.length() > 0 {
            Some(cleaned)
          } else {
            None
          }
        }
        Some(json) => {
          let text = json_to_string(json)
          let cleaned = clean_doc_text(text)
          if cleaned.length() > 0 {
            Some(cleaned)
          } else {
            None
          }
        }
        None => None
      }
    }
    None => None
  }
  // Generate symbol ID
  let sym_id = ctx.file + "::" + ns + ":" + name
  // Add symbol to graph
  let _ = ctx.graph.get_or_add_symbol(
    sym_id,
    name~,
    kind~,
    ns~,
    module_id=ctx.file,
    doc~,
  )
  // Register in current scope for later reference resolution
  let scope = ctx.current_scope()
  if ns == "type" {
    scope.set_type(name, sym_id)
  } else {
    scope.set_value(name, sym_id)
  }
  // Add declares edge from module to symbol
  ctx.graph.add_edge(
    @graph.EdgeKind::from_string("declares"),
    ctx.file,
    sym_id,
    attrs={},
  )
}

///|
/// Evaluates a 'ref' attribute: creates a reference edge.
/// Syntax: ref name ns=value
fn eval_attr_ref(
  action : @types.AttrAction,
  labels : Map[String, Json],
  ctx : SemEvalCtx,
) -> Unit {
  let params = action.get_params()
  // Get the label name for the reference name
  let label_name = match params.get("name") {
    Some(n) => n
    None => {
      // Find first param that's not ns
      let mut found = ""
      for entry in params {
        if entry.0 != "ns" {
          found = entry.1
          break
        }
      }
      if found.length() > 0 {
        found
      } else {
        "name"
      }
    }
  }
  // Get the reference name from labels
  let name = match labels.get(label_name) {
    Some(String(s)) => s
    Some(json) => json_to_string(json)
    None => return
  }
  if name.length() == 0 {
    return
  }
  let ns = params.get("ns").unwrap_or("value")
  // Try to resolve the reference in scope
  let resolved = ctx.lookup_scope(ns, name)
  let target = match resolved {
    Some(sym_id) => sym_id
    None => ctx.file + "::" + ns + ":" + name + "?unresolved"
  }
  // Add references edge
  ctx.graph.add_edge(
    @graph.EdgeKind::from_string("references"),
    ctx.file,
    target,
    attrs={},
  )
}

///|
/// Evaluates a 'call' attribute: creates a call edge.
/// Syntax: call callee=callee
fn eval_attr_call(
  action : @types.AttrAction,
  labels : Map[String, Json],
  ctx : SemEvalCtx,
) -> Unit {
  let params = action.get_params()
  // Get callee label name
  let callee_label = params.get("callee").unwrap_or("callee")
  // Get callee name from labels
  let callee_name = match labels.get(callee_label) {
    Some(String(s)) => s
    Some(json) => json_to_string(json)
    None => return
  }
  if callee_name.length() == 0 {
    return
  }
  // Generate call ID
  let call_id = ctx.file + "::call@" + ctx.next_call_id()
  // Push call to stack
  ctx.call_stack.push(call_id)
  // Try to resolve callee
  let resolved = ctx.lookup_scope("value", callee_name)
  let target = match resolved {
    Some(sym_id) => sym_id
    None => ctx.file + "::value:" + callee_name + "?unresolved"
  }
  // Add calls edge with call_id attr
  let attrs : Map[String, String] = {}
  attrs.set("call_id", call_id)
  ctx.graph.add_edge(
    @graph.EdgeKind::from_string("calls"),
    ctx.file,
    target,
    attrs~,
  )
  // Pop call from stack (call is complete after this action)
  if ctx.call_stack.length() > 0 {
    let _ = ctx.call_stack.pop()
  }
}

///|
/// Evaluates an 'argref' attribute: argument reference in a call.
fn eval_attr_argref(
  _action : @types.AttrAction,
  _labels : Map[String, Json],
  _ctx : SemEvalCtx,
) -> Unit {
  // argref tracks argument references within a call
  // For now, this is handled implicitly through the call stack
  ()
}

///|
/// Evaluates an 'import' attribute: creates a module dependency edge.
/// Syntax: import module=path
fn eval_attr_import(
  action : @types.AttrAction,
  labels : Map[String, Json],
  ctx : SemEvalCtx,
) -> Unit {
  let params = action.get_params()
  // Get module path label
  let module_label = params.get("module").unwrap_or("module")
  // Get module path from labels
  let module_path = match labels.get(module_label) {
    Some(String(s)) => strip_quotes(s)
    Some(json) => strip_quotes(json_to_string(json))
    None => return
  }
  if module_path.length() == 0 {
    return
  }
  // Resolve the module path
  let resolved = resolve_import_path(ctx, module_path)
  // Ensure target module exists in graph
  let _ = ctx.graph.get_or_add_module(resolved, file=None)
  // Add moduleDependsOn edge
  let attrs : Map[String, String] = {}
  attrs.set("via", module_path)
  attrs.set("dep_kind", "value")
  ctx.graph.add_edge(
    @graph.EdgeKind::from_string("moduleDependsOn"),
    ctx.file,
    resolved,
    attrs~,
  )
}

///|
/// Evaluates a 'reexport' attribute: re-export from another module.
fn eval_attr_reexport(
  action : @types.AttrAction,
  labels : Map[String, Json],
  ctx : SemEvalCtx,
) -> Unit {
  // Similar to import but for re-exports
  eval_attr_import(action, labels, ctx)
}

///|
/// Evaluates a 'scope' attribute: manages scope stack.
/// Syntax: scope push=function or scope pop
fn eval_attr_scope(
  action : @types.AttrAction,
  _labels : Map[String, Json],
  ctx : SemEvalCtx,
) -> Unit {
  let params = action.get_params()
  match params.get("push") {
    Some(_) => ctx.push_scope()
    None => ()
  }
  match params.get("pop") {
    Some(_) => ctx.pop_scope()
    None => ()
  }
  // Also check for simple "pop" as a kind
  if action.get_kind() == "scope" && params.length() == 0 {
    // Implicit pop
    ()
  }
}

///|
/// Resolves an import path to a module ID.
fn resolve_import_path(ctx : SemEvalCtx, path : String) -> String {
  // Use resolver if available (check both exts and resolve_chain)
  let resolver_spec = ctx.spec.get_resolver()
  if resolver_spec.get_exts().length() > 0 || resolver_spec.has_resolve_chain() {
    // Use cached resolver for consistency with $resolve()
    let result = @resolver.resolve_module_cached(
      ctx.resolution_cache,
      resolver_spec,
      ctx.language,
      ctx.file,
      path,
      ctx.root,
      ctx.file_exists,
    )
    result.to_string()
  } else {
    // No resolver, return path with bare prefix if needed
    let bare_prefix = resolver_spec.get_bare_prefix()
    if bare_prefix.length() > 0 && not(is_relative_path(path)) {
      bare_prefix + path
    } else {
      path
    }
  }
}

///|
/// Checks if a path is relative (starts with ./ or ../ or /).
fn is_relative_path(path : String) -> Bool {
  path.has_prefix("./") || path.has_prefix("../") || path.has_prefix("/")
}

///|
/// Strips quotes from a string.
fn strip_quotes(s : String) -> String {
  let chars = s.to_array()
  if chars.length() < 2 {
    return s
  }
  let first = chars[0]
  let last = chars[chars.length() - 1]
  if (first == '"' && last == '"') || (first == '\'' && last == '\'') {
    let result = StringBuilder::new()
    for i = 1; i < chars.length() - 1; i = i + 1 {
      result.write_char(chars[i])
    }
    result.to_string()
  } else {
    s
  }
}

///|
/// Evaluates attrs for a rule by name.
/// Looks up the attrs for the rule in the spec and evaluates them.
pub fn eval_rule_attrs(
  rule_name : String,
  labels : Map[String, Json],
  ctx : SemEvalCtx,
) -> Unit {
  match ctx.spec.get_attr(rule_name) {
    Some(actions) => eval_attrs(actions, labels, ctx)
    None => ()
  }
}
