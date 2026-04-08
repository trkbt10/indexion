///|
/// Creates a test context with minimal setup.
fn create_test_ctx() -> SemEvalCtx {
  let spec = @types.KGFSpec::new("test")
  let graph = @graph.CodeGraph::new()
  // Use a simple file_exists function that always returns false
  let file_exists = fn(_path : String) -> Bool { false }
  SemEvalCtx::new(
    spec, graph, "/project/src/test.ts", "/project", "typescript", file_exists,
  )
}

///|
test "is_truthy with various values" {
  assert_eq(is_truthy(Json::null()), false)
  assert_eq(is_truthy(true.to_json()), true)
  assert_eq(is_truthy(false.to_json()), false)
  assert_eq(is_truthy("".to_json()), false)
  assert_eq(is_truthy("hello".to_json()), true)
  assert_eq(is_truthy(Json::array([])), false)
  assert_eq(is_truthy(Json::array([1.0.to_json()])), true)
  assert_eq(is_truthy(0.0.to_json()), true)
  assert_eq(is_truthy(Json::object({})), true)
}

///|
test "eval_expr with literals" {
  let ctx = create_test_ctx()
  let env = Env::new({})
  // String literal
  let str_expr = @types.SemExpr::str("hello")
  let str_result = eval_expr(str_expr, env, ctx)
  assert_eq(str_result, "hello".to_json())
  // Number literal
  let num_expr = @types.SemExpr::num(42.0)
  let num_result = eval_expr(num_expr, env, ctx)
  assert_eq(num_result, 42.0.to_json())
  // Boolean literal
  let bool_expr = @types.SemExpr::bool(true)
  let bool_result = eval_expr(bool_expr, env, ctx)
  assert_eq(bool_result, true.to_json())
  // Null literal
  let null_expr = @types.SemExpr::null()
  let null_result = eval_expr(null_expr, env, ctx)
  assert_eq(null_result, Json::null())
}

///|
test "eval_expr with built-in variables" {
  let ctx = create_test_ctx()
  let env = Env::new({})
  // file variable
  let file_expr = @types.SemExpr::variable("file")
  let file_result = eval_expr(file_expr, env, ctx)
  assert_eq(file_result, "/project/src/test.ts".to_json())
  // root variable
  let root_expr = @types.SemExpr::variable("root")
  let root_result = eval_expr(root_expr, env, ctx)
  assert_eq(root_result, "/project".to_json())
  // language variable
  let lang_expr = @types.SemExpr::variable("language")
  let lang_result = eval_expr(lang_expr, env, ctx)
  assert_eq(lang_result, "typescript".to_json())
}

///|
test "eval_expr with labels and locals" {
  let ctx = create_test_ctx()
  let labels : Map[String, Json] = {}
  labels.set("Name", "myFunction".to_json())
  let env = Env::new(labels)
  // Label variable
  let label_expr = @types.SemExpr::variable("Name")
  let label_result = eval_expr(label_expr, env, ctx)
  assert_eq(label_result, "myFunction".to_json())
  // Set local and access it
  env.set_local("x", 10.0.to_json())
  let local_expr = @types.SemExpr::variable("x")
  let local_result = eval_expr(local_expr, env, ctx)
  assert_eq(local_result, 10.0.to_json())
}

///|
test "eval_expr with concat function" {
  let ctx = create_test_ctx()
  let env = Env::new({})
  let concat_expr = @types.SemExpr::func("concat", [
    @types.SemExpr::str("hello"),
    @types.SemExpr::str(" "),
    @types.SemExpr::str("world"),
  ])
  let result = eval_expr(concat_expr, env, ctx)
  assert_eq(result, "hello world".to_json())
}

///|
test "eval_expr with arithmetic functions" {
  let ctx = create_test_ctx()
  let env = Env::new({})
  // add
  let add_expr = @types.SemExpr::func("add", [
    @types.SemExpr::num(10.0),
    @types.SemExpr::num(5.0),
  ])
  let add_result = eval_expr(add_expr, env, ctx)
  assert_eq(add_result, 15.0.to_json())
  // sub
  let sub_expr = @types.SemExpr::func("sub", [
    @types.SemExpr::num(10.0),
    @types.SemExpr::num(3.0),
  ])
  let sub_result = eval_expr(sub_expr, env, ctx)
  assert_eq(sub_result, 7.0.to_json())
  // mul
  let mul_expr = @types.SemExpr::func("mul", [
    @types.SemExpr::num(4.0),
    @types.SemExpr::num(3.0),
  ])
  let mul_result = eval_expr(mul_expr, env, ctx)
  assert_eq(mul_result, 12.0.to_json())
  // div
  let div_expr = @types.SemExpr::func("div", [
    @types.SemExpr::num(20.0),
    @types.SemExpr::num(4.0),
  ])
  let div_result = eval_expr(div_expr, env, ctx)
  assert_eq(div_result, 5.0.to_json())
  // div by zero
  let div_zero_expr = @types.SemExpr::func("div", [
    @types.SemExpr::num(10.0),
    @types.SemExpr::num(0.0),
  ])
  let div_zero_result = eval_expr(div_zero_expr, env, ctx)
  assert_eq(div_zero_result, Json::null())
  // floor
  let floor_expr = @types.SemExpr::func("floor", [@types.SemExpr::num(3.7)])
  let floor_result = eval_expr(floor_expr, env, ctx)
  assert_eq(floor_result, 3.0.to_json())
}

///|
test "eval_expr with eq function" {
  let ctx = create_test_ctx()
  let env = Env::new({})
  // Equal strings
  let eq_true = @types.SemExpr::func("eq", [
    @types.SemExpr::str("a"),
    @types.SemExpr::str("a"),
  ])
  assert_eq(eval_expr(eq_true, env, ctx), true.to_json())
  // Unequal strings
  let eq_false = @types.SemExpr::func("eq", [
    @types.SemExpr::str("a"),
    @types.SemExpr::str("b"),
  ])
  assert_eq(eval_expr(eq_false, env, ctx), false.to_json())
}

///|
test "eval_expr with coalesce function" {
  let ctx = create_test_ctx()
  let env = Env::new({})
  // First non-null
  let coalesce1 = @types.SemExpr::func("coalesce", [
    @types.SemExpr::str("value"),
    @types.SemExpr::str("default"),
  ])
  assert_eq(eval_expr(coalesce1, env, ctx), "value".to_json())
  // First is null
  let coalesce2 = @types.SemExpr::func("coalesce", [
    @types.SemExpr::null(),
    @types.SemExpr::str("default"),
  ])
  assert_eq(eval_expr(coalesce2, env, ctx), "default".to_json())
}

///|
test "eval_expr with slice function" {
  let ctx = create_test_ctx()
  let env = Env::new({})
  let slice_expr = @types.SemExpr::func("slice", [
    @types.SemExpr::str("hello world"),
    @types.SemExpr::num(0.0),
    @types.SemExpr::num(5.0),
  ])
  let result = eval_expr(slice_expr, env, ctx)
  assert_eq(result, "hello".to_json())
}

///|
test "eval_expr with stripQuotes function" {
  let ctx = create_test_ctx()
  let env = Env::new({})
  // Double quotes
  let strip1 = @types.SemExpr::func("stripQuotes", [
    @types.SemExpr::str("\"hello\""),
  ])
  assert_eq(eval_expr(strip1, env, ctx), "hello".to_json())
  // Single quotes
  let strip2 = @types.SemExpr::func("stripQuotes", [
    @types.SemExpr::str("'world'"),
  ])
  assert_eq(eval_expr(strip2, env, ctx), "world".to_json())
  // No quotes
  let strip3 = @types.SemExpr::func("stripQuotes", [@types.SemExpr::str("test")])
  assert_eq(eval_expr(strip3, env, ctx), "test".to_json())
}

///|
test "eval_expr with first and last functions" {
  let ctx = create_test_ctx()
  let labels : Map[String, Json] = {}
  labels.set(
    "items",
    Json::array(["a".to_json(), "b".to_json(), "c".to_json()]),
  )
  let env = Env::new(labels)
  // first
  let first_expr = @types.SemExpr::func("first", [
    @types.SemExpr::variable("items"),
  ])
  assert_eq(eval_expr(first_expr, env, ctx), "a".to_json())
  // last
  let last_expr = @types.SemExpr::func("last", [
    @types.SemExpr::variable("items"),
  ])
  assert_eq(eval_expr(last_expr, env, ctx), "c".to_json())
  // Empty array
  labels.set("empty", Json::array([]))
  let first_empty = @types.SemExpr::func("first", [
    @types.SemExpr::variable("empty"),
  ])
  assert_eq(eval_expr(first_empty, env, ctx), Json::null())
}

///|
test "eval_expr with obj function" {
  let ctx = create_test_ctx()
  let env = Env::new({})
  let obj_expr = @types.SemExpr::func("obj", [
    @types.SemExpr::str("name"),
    @types.SemExpr::str("test"),
    @types.SemExpr::str("value"),
    @types.SemExpr::num(42.0),
  ])
  let result = eval_expr(obj_expr, env, ctx)
  match result {
    Object(obj) => {
      assert_eq(obj.get("name"), Some("test".to_json()))
      assert_eq(obj.get("value"), Some(42.0.to_json()))
    }
    _ => fail("Expected object")
  }
}

///|
test "eval_expr with autoSym call" {
  let ctx = create_test_ctx()
  let env = Env::new({})
  let sym1_expr = @types.SemExpr::call("autoSym", [])
  let sym1 = eval_expr(sym1_expr, env, ctx)
  assert_eq(sym1, "1".to_json())
  let sym2_expr = @types.SemExpr::call("autoSym", [])
  let sym2 = eval_expr(sym2_expr, env, ctx)
  assert_eq(sym2, "2".to_json())
}

///|
test "eval_expr with scope call" {
  let ctx = create_test_ctx()
  let env = Env::new({})
  // Add a binding to scope
  ctx.current_scope().set_value("myVar", "var_123")
  // Lookup via scope call
  let scope_expr = @types.SemExpr::call("scope", [
    @types.SemExpr::str("value"),
    @types.SemExpr::str("myVar"),
  ])
  let result = eval_expr(scope_expr, env, ctx)
  assert_eq(result, "var_123".to_json())
  // Lookup non-existent
  let not_found_expr = @types.SemExpr::call("scope", [
    @types.SemExpr::str("value"),
    @types.SemExpr::str("notFound"),
  ])
  assert_eq(eval_expr(not_found_expr, env, ctx), Json::null())
}

///|
test "eval_stmt edge" {
  let ctx = create_test_ctx()
  let env = Env::new({})
  // Create edge statement
  let stmt = @types.SemStmt::edge(
    "declares",
    @types.SemExpr::str("mod:main"),
    @types.SemExpr::str("sym:func1"),
  )
  eval_stmt(stmt, env, ctx)
  // Verify edge was added
  let edges = ctx.graph.get_edges()
  assert_eq(edges.length(), 1)
  assert_eq(edges[0].from, "mod:main")
  assert_eq(edges[0].to, "sym:func1")
}

///|
test "eval_stmt bind" {
  let ctx = create_test_ctx()
  let env = Env::new({})
  // Create bind statement
  let stmt = @types.SemStmt::bind(
    @types.SemExpr::str("value"),
    @types.SemExpr::str("myFunc"),
    @types.SemExpr::str("sym:123"),
  )
  eval_stmt(stmt, env, ctx)
  // Verify binding was added
  let result = ctx.lookup_scope("value", "myFunc")
  assert_eq(result, Some("sym:123"))
}

///|
test "eval_stmt let" {
  let ctx = create_test_ctx()
  let env = Env::new({})
  // Create let statement
  let stmt = @types.SemStmt::let_("x", @types.SemExpr::num(100.0))
  eval_stmt(stmt, env, ctx)
  // Verify local was set
  assert_eq(env.get("x"), Some(100.0.to_json()))
}

///|
test "eval_stmt for" {
  let ctx = create_test_ctx()
  let labels : Map[String, Json] = {}
  labels.set(
    "items",
    Json::array(["a".to_json(), "b".to_json(), "c".to_json()]),
  )
  let env = Env::new(labels)
  // Create a let statement to accumulate results
  env.set_local("count", 0.0.to_json())
  // Create for statement that increments count
  let body = [
    @types.SemStmt::let_(
      "count",
      @types.SemExpr::func("add", [
        @types.SemExpr::variable("count"),
        @types.SemExpr::num(1.0),
      ]),
    ),
  ]
  let stmt = @types.SemStmt::for_(
    "item",
    @types.SemExpr::variable("items"),
    body,
  )
  eval_stmt(stmt, env, ctx)
  // Verify count was incremented 3 times
  assert_eq(env.get("count"), Some(3.0.to_json()))
}

///|
test "eval_stmt module" {
  let ctx = create_test_ctx()
  let env = Env::new({})
  // Create module statement
  let stmt = @types.SemStmt::mod_(
    @types.SemExpr::str("my-module"),
    file=Some(@types.SemExpr::str("/project/src/my-module.ts")),
  )
  eval_stmt(stmt, env, ctx)
  // Verify module was added
  let modules = ctx.graph.get_modules()
  assert_eq(modules.contains("my-module"), true)
  match modules.get("my-module") {
    Some(m) => assert_eq(m.file, Some("/project/src/my-module.ts"))
    None => fail("Module not found")
  }
}

///|
test "eval_stmt note" {
  let ctx = create_test_ctx()
  let env = Env::new({})
  // Create note statement
  let stmt = @types.SemStmt::note(
    "Warning",
    payload=Some(@types.SemExpr::str("Something happened")),
  )
  eval_stmt(stmt, env, ctx)
  // Verify event was added
  assert_eq(ctx.events.length(), 1)
  assert_eq(ctx.events[0].0, "Note")
  assert_eq(ctx.events[0].1.get("type"), Some("Warning".to_json()))
}

///|
test "eval_semantics with when condition" {
  let ctx = create_test_ctx()
  let labels : Map[String, Json] = {}
  labels.set("Name", "testFunc".to_json())
  // Create block with when condition that is true
  let block = @types.SemOnBlock::new(
    "FunctionDecl",
    [
      @types.SemStmt::edge(
        "declares",
        @types.SemExpr::str("mod"),
        @types.SemExpr::variable("Name"),
      ),
    ],
    when_cond=Some(@types.SemExpr::variable("Name")),
  )
  eval_semantics([block], labels, ctx)
  // Verify edge was added
  assert_eq(ctx.graph.get_edges().length(), 1)
}

///|
test "eval_semantics with else branch" {
  let ctx = create_test_ctx()
  let labels : Map[String, Json] = {}
  labels.set("Name", Json::null())
  // Create block with when condition that is false
  let block = @types.SemOnBlock::new(
    "FunctionDecl",
    [
      @types.SemStmt::edge(
        "declares",
        @types.SemExpr::str("mod"),
        @types.SemExpr::str("then-branch"),
      ),
    ],
    when_cond=Some(@types.SemExpr::variable("Name")),
    else_stmts=Some([
      @types.SemStmt::edge(
        "declares",
        @types.SemExpr::str("mod"),
        @types.SemExpr::str("else-branch"),
      ),
    ]),
  )
  eval_semantics([block], labels, ctx)
  // Verify else edge was added (not then edge)
  let edges = ctx.graph.get_edges()
  assert_eq(edges.length(), 1)
  assert_eq(edges[0].to, "else-branch")
}

///|
test "scope stack operations" {
  let ctx = create_test_ctx()
  // Set value in initial scope
  ctx.current_scope().set_value("outer", "outer_val")
  // Push new scope
  ctx.push_scope()
  ctx.current_scope().set_value("inner", "inner_val")
  // Can see both values
  assert_eq(ctx.lookup_scope("value", "outer"), Some("outer_val"))
  assert_eq(ctx.lookup_scope("value", "inner"), Some("inner_val"))
  // Pop scope
  ctx.pop_scope()
  // Can still see outer, but not inner
  assert_eq(ctx.lookup_scope("value", "outer"), Some("outer_val"))
  assert_eq(ctx.lookup_scope("value", "inner"), None)
}

///|
test "collect_refs" {
  let ctx = create_test_ctx()
  // Add some events
  let ref_payload1 : Map[String, Json] = {}
  ref_payload1.set("target", "sym1".to_json())
  ctx.add_event("Ref", ref_payload1)
  let note_payload : Map[String, Json] = {}
  note_payload.set("type", "Info".to_json())
  ctx.add_event("Note", note_payload)
  let ref_payload2 : Map[String, Json] = {}
  ref_payload2.set("target", "sym2".to_json())
  ctx.add_event("Ref", ref_payload2)
  // Collect refs
  let refs = ctx.collect_refs()
  assert_eq(refs.length(), 2)
  // Only Note event should remain
  assert_eq(ctx.events.length(), 1)
  assert_eq(ctx.events[0].0, "Note")
}

///|
test "eval_expr with generic regex capture functions" {
  let env = Env::new({})
  let ctx = create_test_ctx()
  let literals_expr = @types.SemExpr::func("regexCaptures", [
    @types.SemExpr::str(
      "## Timeout\nThe value MUST be `36`.\nFor example, `99` is shown.\nThe response SHALL return `200`.\n",
    ),
    @types.SemExpr::str(
      "^(?![^\\n]*(?:for example|e\\.g\\.|suppose|consider ))[^\\n]*(?:\\bmust\\b|\\bshall\\b|\\bshould\\b|\\brequired\\b|=|\\|)[^\\n]*\\b([0-9]{1,})\\b",
    ),
    @types.SemExpr::num(1.0),
    @types.SemExpr::bool(true),
  ])
  let refs_expr = @types.SemExpr::func("regexCaptures", [
    @types.SemExpr::str("See sections 6.1 and 6.2.\n"),
    @types.SemExpr::str("\\bsections?\\s+((?:[A-Z]|\\d+(?:\\.\\d+)*))\\.?\\b"),
    @types.SemExpr::num(1.0),
    @types.SemExpr::bool(true),
  ])
  let pairs_expr = @types.SemExpr::func("regexPairs", [
    @types.SemExpr::str("| 7 | REQUEST_STOP |\n"),
    @types.SemExpr::str(
      "\\|\\s*([0-9]+(?:\\.[0-9]+)*)\\s*\\|\\s*([A-Za-z][A-Za-z0-9 /'_-]*[A-Za-z0-9/_-])\\s*\\|",
    ),
    @types.SemExpr::num(2.0),
    @types.SemExpr::num(1.0),
  ])
  assert_eq(
    eval_expr(literals_expr, env, ctx),
    Json::array(["36".to_json(), "200".to_json()]),
  )
  assert_eq(eval_expr(refs_expr, env, ctx), Json::array(["6.1".to_json()]))
  match eval_expr(pairs_expr, env, ctx) {
    Array(values) => {
      assert_eq(values.length(), 1)
      match values[0] {
        Object(obj) => {
          assert_eq(obj.get("label").unwrap(), "REQUEST_STOP".to_json())
          assert_eq(obj.get("literal").unwrap(), "7".to_json())
        }
        _ => fail("expected object")
      }
    }
    _ => fail("expected array")
  }
}
