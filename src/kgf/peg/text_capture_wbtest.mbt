///|
/// Tests for multi-line text capture feature in PEG parser.
/// Verifies that _text accumulates across sequences and repetitions,
/// and that name_text labels are correctly set.

///|
/// KGF spec with multi-line doc comments for testing text capture.
fn multiline_doc_kgf() -> String {
  let text =
    #|language: testdoc
    #|
    #|=== lex
    #|SKIP /[ \t]+/
    #|TOKEN NL /\n/
    #|TOKEN DOC_START /\/\/\/\|/
    #|TOKEN DOC_LINE /\/\/\/[^\n]*/
    #|TOKEN FN /fn/
    #|TOKEN IDENT /[a-zA-Z_][a-zA-Z0-9_]*/
    #|TOKEN LPAREN /\(/
    #|TOKEN RPAREN /\)/
    #|TOKEN LBRACE /\{/
    #|TOKEN RBRACE /\}/
    #|
    #|=== grammar
    #|Program -> Item*
    #|Item -> FnDecl | NL
    #|FnDecl -> doc:DocBlock? NL* FN fn_id:IDENT LPAREN RPAREN LBRACE RBRACE
    #|DocBlock -> DOC_START (NL DOC_LINE)*
    #|
  text
}

///|
/// Helper to parse with the multiline doc spec and get events.
fn parse_with_doc_spec(source : String) -> Array[(String, Map[String, Json])] {
  let spec = @parser.parse_kgf(multiline_doc_kgf()).unwrap()
  let peg = build_peg(spec) catch { _ => panic() }
  let lexer = @lexer.Lexer::new(spec.get_tokens())
  let tokens = lexer.tokenize(source)
  let result = run_parse(peg, spec, "Program", tokens)
  match result {
    Some(r) => r.events
    None => []
  }
}

///|
test "text capture: single line doc comment" {
  let source =
    #|///|
    #|fn foo() {}
  let events = parse_with_doc_spec(source)

  // Find DocBlock event
  let doc_event = events.iter().find_first(fn(e) { e.0 == "DocBlock" })
  assert_true(doc_event is Some(_))

  let labels = doc_event.unwrap().1
  // _text should contain the doc start
  match labels.get("_text") {
    Some(String(text)) => assert_true(text.contains("///|"))
    _ => fail("Expected _text to be set")
  }
}

///|
test "text capture: multi-line doc comment accumulates text" {
  let source =
    #|///|
    #|/// First line
    #|/// Second line
    #|/// Third line
    #|fn foo() {}
  let events = parse_with_doc_spec(source)

  // Find DocBlock event
  let doc_event = events.iter().find_first(fn(e) { e.0 == "DocBlock" })
  assert_true(doc_event is Some(_))

  let labels = doc_event.unwrap().1
  // _text should contain ALL lines accumulated
  match labels.get("_text") {
    Some(String(text)) => {
      assert_true(text.contains("///|"))
      assert_true(text.contains("First line"))
      assert_true(text.contains("Second line"))
      assert_true(text.contains("Third line"))
    }
    _ => fail("Expected _text to contain accumulated text")
  }
}

///|
test "text capture: labeled capture gets _text as name_text" {
  let source = "///|\n/// Documentation here\nfn myFunc() {}"
  let events = parse_with_doc_spec(source)

  // Find FnDecl event (has doc:DocBlock label)
  let fn_event = events.iter().find_first(fn(e) { e.0 == "FnDecl" })
  assert_true(fn_event is Some(_))

  let labels = fn_event.unwrap().1
  // doc_text should contain the accumulated text
  match labels.get("doc_text") {
    Some(String(text)) => {
      assert_true(text.contains("///|"))
      assert_true(text.contains("Documentation here"))
    }
    _ => fail("Expected doc_text label to be set with accumulated text")
  }
}

///|
test "text capture: fn_id label still works (single token)" {
  let source =
    #|fn myFunction() {}
  let events = parse_with_doc_spec(source)

  // Find FnDecl event
  let fn_event = events.iter().find_first(fn(e) { e.0 == "FnDecl" })
  assert_true(fn_event is Some(_))

  let labels = fn_event.unwrap().1
  // fn_id should be the identifier value
  match labels.get("fn_id") {
    Some(String(id)) => assert_eq(id, "myFunction")
    _ => fail("Expected fn_id label")
  }
  // fn_id_text should also be set
  match labels.get("fn_id_text") {
    Some(String(text)) => assert_eq(text, "myFunction")
    _ => fail("Expected fn_id_text label")
  }
}

///|
test "text capture: empty optional doc" {
  let source =
    #|fn noDoc() {}
  let events = parse_with_doc_spec(source)

  // Find FnDecl event
  let fn_event = events.iter().find_first(fn(e) { e.0 == "FnDecl" })
  assert_true(fn_event is Some(_))

  let labels = fn_event.unwrap().1
  // doc should be null (optional not matched)
  match labels.get("doc") {
    Some(Null) => ()
    None => ()
    _ => fail("Expected doc to be null or absent for function without doc")
  }
}

///|
test "text capture: multiple functions with docs" {
  let source =
    #|///|
    #|/// First function
    #|fn first() {}
    #|
    #|///|
    #|/// Second function
    #|fn second() {}
  let events = parse_with_doc_spec(source)

  // Count FnDecl events
  let fn_events : Array[(String, Map[String, Json])] = []
  for event in events {
    if event.0 == "FnDecl" {
      fn_events.push(event)
    }
  }
  assert_eq(fn_events.length(), 2)

  // First function
  match fn_events[0].1.get("fn_id") {
    Some(String(id)) => assert_eq(id, "first")
    _ => fail("Expected first fn_id")
  }
  match fn_events[0].1.get("doc_text") {
    Some(String(text)) => assert_true(text.contains("First function"))
    _ => fail("Expected first doc_text")
  }

  // Second function
  match fn_events[1].1.get("fn_id") {
    Some(String(id)) => assert_eq(id, "second")
    _ => fail("Expected second fn_id")
  }
  match fn_events[1].1.get("doc_text") {
    Some(String(text)) => assert_true(text.contains("Second function"))
    _ => fail("Expected second doc_text")
  }
}

///|
/// KGF spec for testing Star repetition text accumulation.
fn repeated_tokens_kgf() -> String {
  let text =
    #|language: testrep
    #|
    #|=== lex
    #|SKIP /[ \t]+/
    #|TOKEN NL /\n/
    #|TOKEN WORD /[a-zA-Z]+/
    #|TOKEN COMMA /,/
    #|
    #|=== grammar
    #|Program -> words:WordList
    #|WordList -> WORD (COMMA WORD)*
    #|
  text
}

///|
test "text capture: star repetition accumulates all tokens" {
  let spec = @parser.parse_kgf(repeated_tokens_kgf()).unwrap()
  let peg = build_peg(spec) catch { _ => panic() }
  let lexer = @lexer.Lexer::new(spec.get_tokens())
  let source = "apple, banana, cherry"
  let tokens = lexer.tokenize(source)

  let result = run_parse(peg, spec, "Program", tokens)
  assert_true(result is Some(_))

  let labels = result.unwrap().labels
  // words_text should contain all tokens
  match labels.get("words_text") {
    Some(String(text)) => {
      assert_true(text.contains("apple"))
      assert_true(text.contains("banana"))
      assert_true(text.contains("cherry"))
      assert_true(text.contains(","))
    }
    _ => fail("Expected words_text to contain all accumulated text")
  }
}

///|
test "text capture: _last still contains last token only" {
  let spec = @parser.parse_kgf(repeated_tokens_kgf()).unwrap()
  let peg = build_peg(spec) catch { _ => panic() }
  let lexer = @lexer.Lexer::new(spec.get_tokens())
  let source = "first, second, third"
  let tokens = lexer.tokenize(source)

  let result = run_parse(peg, spec, "WordList", tokens)
  assert_true(result is Some(_))

  let labels = result.unwrap().labels
  // _last should be the last token value only
  match labels.get("_last") {
    Some(String(last)) => assert_eq(last, "third")
    _ => fail("Expected _last to be 'third'")
  }
}
