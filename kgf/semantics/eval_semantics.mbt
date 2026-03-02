///|
/// Evaluates semantics on-blocks for a completed rule with captured labels.
/// Processes each block's when condition and executes then or else statements accordingly.
pub fn eval_semantics(
  blocks : Array[@types.SemOnBlock],
  labels : Map[String, Json],
  ctx : SemEvalCtx,
) -> Unit {
  if blocks.length() == 0 {
    return
  }
  let env = Env::new(labels)
  for block in blocks {
    let cond = match block.get_when_cond() {
      Some(when_expr) => is_truthy(eval_expr(when_expr, env, ctx))
      None => true
    }
    let stmts = if cond {
      block.get_then_stmts()
    } else {
      match block.get_else_stmts() {
        Some(else_stmts) => else_stmts
        None => []
      }
    }
    for stmt in stmts {
      eval_stmt(stmt, env, ctx)
    }
  }
}

///|
/// Evaluates semantics for a rule by name.
/// Looks up the semantic blocks for the rule in the spec and evaluates them.
pub fn eval_rule_semantics(
  rule_name : String,
  labels : Map[String, Json],
  ctx : SemEvalCtx,
) -> Unit {
  match ctx.spec.get_semantic(rule_name) {
    Some(blocks) => eval_semantics(blocks, labels, ctx)
    None => ()
  }
}
