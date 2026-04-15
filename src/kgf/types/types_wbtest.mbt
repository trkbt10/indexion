///|
test "TokenDef::new creates token with defaults" {
  let token = TokenDef::new("IDENT", "[a-zA-Z_][a-zA-Z0-9_]*")
  assert_eq(token.get_name(), "IDENT")
  assert_eq(token.get_pattern(), "[a-zA-Z_][a-zA-Z0-9_]*")
  assert_eq(token.is_skip(), false)
  assert_eq(token.get_flags(), None)
}

///|
test "TokenDef::new creates token with skip flag" {
  let token = TokenDef::new("WS", "\\s+", skip=true)
  assert_eq(token.get_name(), "WS")
  assert_eq(token.is_skip(), true)
}

///|
test "TokenDef::new creates token with flags" {
  let token = TokenDef::new("COMMENT", "//.*", flags=Some("m"))
  assert_eq(token.get_flags(), Some("m"))
}

///|
test "Tok::new creates token with position" {
  let tok = Tok::new("IDENT", "foo", 10)
  assert_eq(tok.get_kind(), "IDENT")
  assert_eq(tok.get_text(), "foo")
  assert_eq(tok.get_pos(), 10)
  assert_eq(tok.get_value(), "foo") // defaults to text
}

///|
test "Tok::get_value returns value when set" {
  let tok = Tok::new("STRING", "\"hello\"", 0, value=Some("hello"))
  assert_eq(tok.get_value(), "hello")
}

///|
test "RuleDef::new creates rule" {
  let rule = RuleDef::new("expr", "term (('+' | '-') term)*")
  assert_eq(rule.get_name(), "expr")
  assert_eq(rule.get_expr(), "term (('+' | '-') term)*")
}

///|
test "AttrAction::new creates action with defaults" {
  let action = AttrAction::new("def")
  assert_eq(action.get_kind(), "def")
}

///|
test "AttrAction::new creates action with params" {
  let params : Map[String, String] = Map::new()
  params.set("scope", "local")
  let action = AttrAction::new("def", params~)
  assert_eq(action.get_param("scope"), Some("local"))
  assert_eq(action.get_param("nonexistent"), None)
}

///|
test "ModulePathStyle conversion" {
  assert_eq(ModulePathStyle::from_string("slash"), Some(Slash))
  assert_eq(ModulePathStyle::from_string("dot"), Some(Dot))
  assert_eq(ModulePathStyle::from_string("coloncol"), Some(ColonColon))
  assert_eq(ModulePathStyle::from_string("invalid"), None)
  assert_eq(Slash.as_string(), "slash")
  assert_eq(Dot.as_string(), "dot")
  assert_eq(ColonColon.as_string(), "coloncol")
}

///|
test "ResolverAlias::new creates alias" {
  let resolver_alias = ResolverAlias::new("@/*", "src/*")
  assert_eq(resolver_alias.get_pattern(), "@/*")
  assert_eq(resolver_alias.get_replace(), "src/*")
}

///|
test "ResolverSpec::new creates spec with defaults" {
  let spec = ResolverSpec::new()
  assert_eq(spec.get_sources().length(), 0)
  assert_eq(spec.get_bare_prefix(), "")
  assert_eq(spec.get_ns_segments(), 0)
}

///|
test "ResolverSpec::new creates spec with values" {
  let spec = ResolverSpec::new(
    sources=["src"],
    exts=[".ts", ".tsx"],
    module_path_style=Dot,
    ns_prefix=Some("@"),
    ns_segments=2,
  )
  assert_eq(spec.get_sources(), ["src"])
  assert_eq(spec.get_exts(), [".ts", ".tsx"])
  assert_eq(spec.get_module_path_style().as_string(), "dot")
  assert_eq(spec.get_ns_prefix(), Some("@"))
  assert_eq(spec.get_ns_segments(), 2)
}

///|
test "SemExpr constructors" {
  let str_expr = SemExpr::str("hello")
  let num_expr = SemExpr::num(42.0)
  let bool_expr = SemExpr::bool(true)
  let null_expr = SemExpr::null()
  let var_expr = SemExpr::variable("x")
  let call_expr = SemExpr::call("concat", [SemExpr::str("a"), SemExpr::str("b")])
  let func_expr = SemExpr::func("map", [SemExpr::variable("items")])
  match str_expr {
    Str(s) => assert_eq(s, "hello")
    _ => fail("Expected Str")
  }
  match num_expr {
    Num(n) => assert_true(n == 42.0)
    _ => fail("Expected Num")
  }
  match bool_expr {
    Bool(b) => assert_true(b)
    _ => fail("Expected Bool")
  }
  match null_expr {
    Null => ()
    _ => fail("Expected Null")
  }
  match var_expr {
    Var(name) => assert_eq(name, "x")
    _ => fail("Expected Var")
  }
  match call_expr {
    Call(name, args) => {
      assert_eq(name, "concat")
      assert_eq(args.length(), 2)
    }
    _ => fail("Expected Call")
  }
  match func_expr {
    Func(name, args) => {
      assert_eq(name, "map")
      assert_eq(args.length(), 1)
    }
    _ => fail("Expected Func")
  }
}

///|
test "SemStmt::edge creates edge statement" {
  let from = SemExpr::variable("a")
  let to = SemExpr::variable("b")
  let stmt = SemStmt::edge("imports", from, to)
  match stmt {
    Edge(edge_kind~, from~, to~, attrs~) => {
      assert_eq(edge_kind, "imports")
      assert_true(attrs is None)
      match from {
        Var(name) => assert_eq(name, "a")
        _ => fail("Expected Var")
      }
      match to {
        Var(name) => assert_eq(name, "b")
        _ => fail("Expected Var")
      }
    }
    _ => fail("Expected Edge")
  }
}

///|
test "SemStmt::bind creates bind statement" {
  let stmt = SemStmt::bind(
    SemExpr::str("ns"),
    SemExpr::str("name"),
    SemExpr::variable("x"),
  )
  match stmt {
    Bind(ns~, name~, to~) => {
      match ns {
        Str(s) => assert_eq(s, "ns")
        _ => fail("Expected Str")
      }
      match name {
        Str(s) => assert_eq(s, "name")
        _ => fail("Expected Str")
      }
      match to {
        Var(n) => assert_eq(n, "x")
        _ => fail("Expected Var")
      }
    }
    _ => fail("Expected Bind")
  }
}

///|
test "SemStmt::let_ creates let statement" {
  let stmt = SemStmt::let_("x", SemExpr::num(10.0))
  match stmt {
    Let(id~, value~) => {
      assert_eq(id, "x")
      match value {
        Num(n) => assert_true(n == 10.0)
        _ => fail("Expected Num")
      }
    }
    _ => fail("Expected Let")
  }
}

///|
test "SemStmt::for_ creates for statement" {
  let body = [SemStmt::note("item")]
  let stmt = SemStmt::for_("item", SemExpr::variable("items"), body)
  match stmt {
    For(id~, iter~, body~) => {
      assert_eq(id, "item")
      match iter {
        Var(name) => assert_eq(name, "items")
        _ => fail("Expected Var")
      }
      assert_eq(body.length(), 1)
    }
    _ => fail("Expected For")
  }
}

///|
test "SemStmt::mod_ creates module statement" {
  let stmt = SemStmt::mod_(SemExpr::str("mod"), file=Some(SemExpr::str("path")))
  match stmt {
    Module(id~, file~) => {
      match id {
        Str(s) => assert_eq(s, "mod")
        _ => fail("Expected Str")
      }
      match file {
        Some(Str(s)) => assert_eq(s, "path")
        _ => fail("Expected Some(Str)")
      }
    }
    _ => fail("Expected Module")
  }
}

///|
test "SemOnBlock::new creates on-block" {
  let then_stmts = [SemStmt::note("matched")]
  let block = SemOnBlock::new("identifier", then_stmts)
  assert_eq(block.get_rule(), "identifier")
  assert_true(block.get_when_cond() is None)
  assert_eq(block.get_then_stmts().length(), 1)
  assert_true(block.get_else_stmts() is None)
}

///|
test "SemOnBlock::new creates on-block with when/else" {
  let when_cond = SemExpr::bool(true)
  let then_stmts = [SemStmt::note("then")]
  let else_stmts = [SemStmt::note("else")]
  let block = SemOnBlock::new(
    "identifier",
    then_stmts,
    when_cond=Some(when_cond),
    else_stmts=Some(else_stmts),
  )
  assert_true(block.get_when_cond() is Some(_))
  assert_true(block.get_else_stmts() is Some(_))
}

///|
test "KGFSpec::new creates spec with defaults" {
  let spec = KGFSpec::new("typescript")
  assert_eq(spec.get_language(), "typescript")
  assert_eq(spec.get_tokens().length(), 0)
}

///|
test "KGFSpec::new creates spec with values" {
  let tokens = [TokenDef::new("IDENT", "[a-z]+")]
  let rules : Map[String, RuleDef] = Map::new()
  rules.set("prog", RuleDef::new("prog", "stmt*"))
  let features : Map[String, Array[String]] = {}
  features.set("reference_token_kinds", ["INLINE_CODE"])
  let spec = KGFSpec::new(
    "typescript",
    tokens~,
    rules~,
    features=Some(features),
  )
  assert_eq(spec.get_tokens().length(), 1)
  assert_true(spec.get_rule("prog") is Some(_))
  assert_true(spec.get_rule("nonexistent") is None)
  assert_true(spec.get_features() is Some(_))
  assert_eq(spec.get_feature("reference_token_kinds").unwrap(), ["INLINE_CODE"])
  assert_true(spec.get_feature("missing") is None)
}

///|
test "KGFSpec::get_semantic returns semantic blocks" {
  let semantics : Map[String, Array[SemOnBlock]] = Map::new()
  let blocks = [SemOnBlock::new("ident", [SemStmt::note("found")])]
  semantics.set("ident", blocks)
  let spec = KGFSpec::new("typescript", semantics=Some(semantics))
  match spec.get_semantic("ident") {
    Some(blks) => assert_eq(blks.length(), 1)
    None => fail("Expected Some")
  }
  assert_true(spec.get_semantic("nonexistent") is None)
}

///|
test "FstAction constructors" {
  let emit_input = FstAction::emit_input()
  assert_true(emit_input is EmitInput)
  let emit = FstAction::emit("test")
  assert_true(emit is Emit(_))
  let buf = FstAction::buf()
  assert_true(buf is Buf)
  let flush = FstAction::flush(2)
  assert_true(flush is Flush(_))
}

///|
test "FstTransition creation and getters" {
  let actions = [FstAction::emit_input(), FstAction::emit("X")]
  let tr = FstTransition::new("alpha", "next_state", actions)
  assert_eq(tr.get_on(), "alpha")
  assert_eq(tr.get_to(), "next_state")
  assert_eq(tr.get_actions().length(), 2)
}

///|
test "PreprocessFstSpec creation and getters" {
  let classes : Map[String, String] = {}
  classes.set("alpha", "[A-Za-z]")
  classes.set("digit", "[0-9]")
  let states : Map[String, Array[FstTransition]] = {}
  states.set("start", [
    FstTransition::new("alpha", "start", [FstAction::emit_input()]),
  ])
  states.set("end", [])
  let spec = PreprocessFstSpec::new("test_fst", classes, "start", states)
  assert_eq(spec.get_name(), "test_fst")
  assert_eq(spec.get_initial(), "start")
  assert_eq(spec.get_classes().get("alpha").unwrap(), "[A-Za-z]")
  assert_eq(spec.get_states().get("start").unwrap().length(), 1)
}

///|
test "ClassifyModel: empty model" {
  let model = ClassifyModel::new({}, {})
  assert_true(model.is_empty())
  assert_eq(model.get_class_names().length(), 0)
  assert_true(model.get_class("x") is None)
  assert_true(model.predict([]) is None)
}

///|
test "ClassifyModel: predict with trained model" {
  // Positive weights = evidence for this class
  // Model: normative class has evidence words "shall", "must"
  //        meta class has evidence words "introduction", "scope"
  let norm_vocab : Map[String, Double] = {}
  norm_vocab.set("shall", 2.0)
  norm_vocab.set("must", 1.5)
  let meta_vocab : Map[String, Double] = {}
  meta_vocab.set("introduction", 2.0)
  meta_vocab.set("scope", 1.5)
  let classes : Map[String, ClassifyClass] = {}
  classes.set("normative", ClassifyClass::new(0.0, norm_vocab))
  classes.set("meta", ClassifyClass::new(0.0, meta_vocab))
  let model = ClassifyModel::new({}, classes)
  assert_false(model.is_empty())
  assert_eq(model.get_class_names().length(), 2)
  // "shall must" → normative: 0 + 2.0 + 1.5 = 3.5, meta: 0 + 0 + 0 = 0
  let result = model.predict(["shall", "must"])
  assert_eq(result, Some("normative"))
  // "introduction scope" → normative: 0, meta: 0 + 2.0 + 1.5 = 3.5
  let result2 = model.predict(["introduction", "scope"])
  assert_eq(result2, Some("meta"))
}

///|
test "ClassifyModel: classify returns sorted scores" {
  let vocab_a : Map[String, Double] = {}
  vocab_a.set("x", -1.0)
  let vocab_b : Map[String, Double] = {}
  vocab_b.set("x", -0.1)
  let classes : Map[String, ClassifyClass] = {}
  classes.set("a", ClassifyClass::new(0.0, vocab_a))
  classes.set("b", ClassifyClass::new(0.0, vocab_b))
  let model = ClassifyModel::new({}, classes)
  let scores = model.classify(["x"])
  // b has higher score (-0.1 > -1.0), so b should be first
  assert_eq(scores[0].0, "b")
  assert_eq(scores[1].0, "a")
}

///|
test "ClassifyClass: term_weight" {
  let vocab : Map[String, Double] = {}
  vocab.set("shall", -0.105)
  let class_def = ClassifyClass::new(-0.693, vocab)
  assert_eq(class_def.get_prior(), -0.693)
  assert_eq(class_def.term_weight("shall"), -0.105)
  assert_eq(class_def.term_weight("unknown"), 0.0)
}

///|
test "ClassifyModel: metadata access" {
  let meta : Map[String, String] = {}
  meta.set("model_type", "naive_bayes")
  meta.set("corpus_size", "150")
  let model = ClassifyModel::new(meta, {})
  assert_eq(model.get_meta("model_type"), Some("naive_bayes"))
  assert_eq(model.get_meta("corpus_size"), Some("150"))
  assert_eq(model.get_meta("missing"), None)
}

///|
test "KGFSpec with preprocess_fst" {
  let classes : Map[String, String] = {}
  classes.set("any", "[.]")
  let states : Map[String, Array[FstTransition]] = {}
  states.set("s", [])
  let fst = PreprocessFstSpec::new("my_fst", classes, "s", states)
  let spec = KGFSpec::new(
    "test_lang",
    preprocess=Some(["fst:my_fst"]),
    preprocess_fst=Some([fst]),
  )
  assert_true(spec.get_preprocess() is Some(_))
  assert_eq(spec.get_preprocess().unwrap()[0], "fst:my_fst")
  assert_true(spec.get_preprocess_fst() is Some(_))
  assert_eq(spec.get_preprocess_fst().unwrap()[0].get_name(), "my_fst")
}
