///|
/// Evaluates a semantic statement.
pub fn eval_stmt(stmt : @types.SemStmt, env : Env, ctx : SemEvalCtx) -> Unit {
  match stmt {
    Edge(edge_kind~, from~, to~, attrs~) =>
      eval_stmt_edge(edge_kind, from, to, attrs, env, ctx)
    Bind(ns~, name~, to~) => eval_stmt_bind(ns, name, to, env, ctx)
    Note(note_type~, payload~) => eval_stmt_note(note_type, payload, env, ctx)
    Let(id~, value~) => eval_stmt_let(id, value, env, ctx)
    For(id~, iter~, body~) => eval_stmt_for(id, iter, body, env, ctx)
    Module(id~, file~) => eval_stmt_module(id, file, env, ctx)
  }
}

///|
/// Evaluates an edge statement.
fn eval_stmt_edge(
  edge_kind : String,
  from : @types.SemExpr,
  to : @types.SemExpr,
  attrs : @types.SemExpr?,
  env : Env,
  ctx : SemEvalCtx,
) -> Unit {
  let from_val = json_to_string(eval_expr(from, env, ctx))
  let to_val = json_to_string(eval_expr(to, env, ctx))
  let attrs_map : Map[String, String] = {}
  match attrs {
    Some(attrs_expr) => {
      let attrs_json = eval_expr(attrs_expr, env, ctx)
      match attrs_json {
        Object(obj) =>
          for entry in obj {
            attrs_map.set(entry.0, json_to_string(entry.1))
          }
        _ => ()
      }
    }
    None => ()
  }
  let kind = @graph.EdgeKind::from_string(edge_kind)
  ctx.graph.add_edge(kind, from_val, to_val, attrs=attrs_map)
}

///|
/// Evaluates a bind statement.
fn eval_stmt_bind(
  ns : @types.SemExpr,
  name : @types.SemExpr,
  to : @types.SemExpr,
  env : Env,
  ctx : SemEvalCtx,
) -> Unit {
  let ns_val = json_to_string(eval_expr(ns, env, ctx))
  let name_val = json_to_string(eval_expr(name, env, ctx))
  let to_val = json_to_string(eval_expr(to, env, ctx))
  let scope = ctx.current_scope()
  if ns_val == "type" {
    scope.set_type(name_val, to_val)
  } else {
    scope.set_value(name_val, to_val)
  }
}

///|
/// Evaluates a note statement.
fn eval_stmt_note(
  note_type : String,
  payload : @types.SemExpr?,
  env : Env,
  ctx : SemEvalCtx,
) -> Unit {
  let payload_map : Map[String, Json] = {}
  payload_map.set("type", note_type.to_json())
  match payload {
    Some(payload_expr) => {
      let payload_json = eval_expr(payload_expr, env, ctx)
      payload_map.set("payload", payload_json)
      // If this is a module_doc note, add it to the graph
      if note_type == "module_doc" {
        match payload_json {
          Object(obj) =>
            match obj.get("doc") {
              Some(String(doc_text)) =>
                ctx.get_graph().add_note("module_doc", doc_text, ctx.file)
              _ => ()
            }
          _ => ()
        }
      }
    }
    None => ()
  }
  ctx.add_event("Note", payload_map)
}

///|
/// Evaluates a let statement.
fn eval_stmt_let(
  id : String,
  value : @types.SemExpr,
  env : Env,
  ctx : SemEvalCtx,
) -> Unit {
  let v = eval_expr(value, env, ctx)
  env.set_local(id, v)
}

///|
/// Evaluates a for statement.
fn eval_stmt_for(
  id : String,
  iter : @types.SemExpr,
  body : Array[@types.SemStmt],
  env : Env,
  ctx : SemEvalCtx,
) -> Unit {
  let iter_val = eval_expr(iter, env, ctx)
  match iter_val {
    Array(arr) =>
      for item in arr {
        env.set_local(id, item)
        for stmt in body {
          eval_stmt(stmt, env, ctx)
        }
      }
    _ => ()
  }
}

///|
/// Evaluates a module statement.
fn eval_stmt_module(
  id : @types.SemExpr,
  file : @types.SemExpr?,
  env : Env,
  ctx : SemEvalCtx,
) -> Unit {
  let id_val = json_to_string(eval_expr(id, env, ctx))
  if id_val.length() == 0 {
    return
  }
  let file_val : String? = match file {
    Some(file_expr) => {
      let f = json_to_string(eval_expr(file_expr, env, ctx))
      if f.length() > 0 {
        Some(f)
      } else {
        None
      }
    }
    None => None
  }
  let _ = ctx.graph.get_or_add_module(id_val, file=file_val)
}
