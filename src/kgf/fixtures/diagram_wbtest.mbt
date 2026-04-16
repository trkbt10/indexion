///|
/// Diagram fixtures tests.
/// Validates KGF parsing for diagram description languages (Mermaid, etc.).

///|
test "diagram: tokenize mermaid flowchart" {
  let registry = @registry.KGFRegistry::load_from_dir(get_kgfs_dir())
  let spec = registry.get_spec("mermaid").unwrap()
  let lexer = @lexer.Lexer::new(spec.get_tokens())
  let fixtures = get_fixtures_dir()
  let src = @fs.read_file_to_string(
    fixtures + "/diagram/mermaid/flowchart.mmd",
  ) catch {
    _ => ""
  }
  if src.length() > 0 {
    let tokens = lexer.tokenize(src)
    assert_true(tokens.length() > 0)
    assert_true(tokens.iter().any(fn(t) { t.kind == "KW_flowchart" }))
    assert_true(tokens.iter().any(fn(t) { t.kind == "KW_subgraph" }))
    assert_true(tokens.iter().any(fn(t) { t.kind == "KW_end" }))
    assert_true(tokens.iter().any(fn(t) { t.kind == "Ident" }))
    assert_true(tokens.iter().any(fn(t) { t.kind == "Arrow" }))
  }
}

///|
test "diagram: tokenize mermaid sequence diagram" {
  let registry = @registry.KGFRegistry::load_from_dir(get_kgfs_dir())
  let spec = registry.get_spec("mermaid").unwrap()
  let lexer = @lexer.Lexer::new(spec.get_tokens())
  let fixtures = get_fixtures_dir()
  let src = @fs.read_file_to_string(
    fixtures + "/diagram/mermaid/sequence.mmd",
  ) catch {
    _ => ""
  }
  if src.length() > 0 {
    let tokens = lexer.tokenize(src)
    assert_true(tokens.length() > 0)
    assert_true(tokens.iter().any(fn(t) { t.kind == "KW_sequenceDiagram" }))
    assert_true(tokens.iter().any(fn(t) { t.kind == "KW_participant" }))
    assert_true(tokens.iter().any(fn(t) { t.kind == "KW_loop" }))
  }
}

///|
test "diagram: tokenize mermaid class diagram" {
  let registry = @registry.KGFRegistry::load_from_dir(get_kgfs_dir())
  let spec = registry.get_spec("mermaid").unwrap()
  let lexer = @lexer.Lexer::new(spec.get_tokens())
  let fixtures = get_fixtures_dir()
  let src = @fs.read_file_to_string(
    fixtures + "/diagram/mermaid/class.mmd",
  ) catch {
    _ => ""
  }
  if src.length() > 0 {
    let tokens = lexer.tokenize(src)
    assert_true(tokens.length() > 0)
    assert_true(tokens.iter().any(fn(t) { t.kind == "KW_classDiagram" }))
    assert_true(tokens.iter().any(fn(t) { t.kind == "KW_class" }))
    assert_true(
      tokens.iter().any(fn(t) { t.kind == "Ident" && t.text == "Animal" }),
    )
    assert_true(
      tokens.iter().any(fn(t) { t.kind == "Ident" && t.text == "Duck" }),
    )
  }
}

///|
test "diagram: tokenize mermaid er diagram" {
  let registry = @registry.KGFRegistry::load_from_dir(get_kgfs_dir())
  let spec = registry.get_spec("mermaid").unwrap()
  let lexer = @lexer.Lexer::new(spec.get_tokens())
  let fixtures = get_fixtures_dir()
  let src = @fs.read_file_to_string(fixtures + "/diagram/mermaid/er.mmd") catch {
    _ => ""
  }
  if src.length() > 0 {
    let tokens = lexer.tokenize(src)
    assert_true(tokens.length() > 0)
    assert_true(tokens.iter().any(fn(t) { t.kind == "KW_erDiagram" }))
    assert_true(
      tokens.iter().any(fn(t) { t.kind == "Ident" && t.text == "CUSTOMER" }),
    )
    assert_true(
      tokens.iter().any(fn(t) { t.kind == "Ident" && t.text == "ORDER" }),
    )
  }
}

///|
test "diagram: tokenize mermaid gantt chart" {
  let registry = @registry.KGFRegistry::load_from_dir(get_kgfs_dir())
  let spec = registry.get_spec("mermaid").unwrap()
  let lexer = @lexer.Lexer::new(spec.get_tokens())
  let fixtures = get_fixtures_dir()
  let src = @fs.read_file_to_string(
    fixtures + "/diagram/mermaid/gantt.mmd",
  ) catch {
    _ => ""
  }
  if src.length() > 0 {
    let tokens = lexer.tokenize(src)
    assert_true(tokens.length() > 0)
    assert_true(tokens.iter().any(fn(t) { t.kind == "KW_gantt" }))
    assert_true(tokens.iter().any(fn(t) { t.kind == "KW_title" }))
    assert_true(tokens.iter().any(fn(t) { t.kind == "KW_dateFormat" }))
    assert_true(tokens.iter().any(fn(t) { t.kind == "KW_section" }))
  }
}

///|
test "diagram: tokenize mermaid state diagram" {
  let registry = @registry.KGFRegistry::load_from_dir(get_kgfs_dir())
  let spec = registry.get_spec("mermaid").unwrap()
  let lexer = @lexer.Lexer::new(spec.get_tokens())
  let fixtures = get_fixtures_dir()
  let src = @fs.read_file_to_string(
    fixtures + "/diagram/mermaid/state.mmd",
  ) catch {
    _ => ""
  }
  if src.length() > 0 {
    let tokens = lexer.tokenize(src)
    assert_true(tokens.length() > 0)
    assert_true(tokens.iter().any(fn(t) { t.kind == "KW_stateDiagram" }))
    assert_true(tokens.iter().any(fn(t) { t.kind == "KW_state" }))
    assert_true(
      tokens.iter().any(fn(t) { t.kind == "Ident" && t.text == "Idle" }),
    )
    assert_true(
      tokens.iter().any(fn(t) { t.kind == "Ident" && t.text == "Processing" }),
    )
  }
}

///|
test "diagram: mermaid spec registry lookup by extension" {
  let registry = @registry.KGFRegistry::load_from_dir(get_kgfs_dir())
  let lang_mmd = registry.detect_from_path("diagram.mmd")
  assert_true(lang_mmd is Some(_))
  assert_eq(lang_mmd.unwrap(), "mermaid")
  let lang_mermaid = registry.detect_from_path("diagram.mermaid")
  assert_true(lang_mermaid is Some(_))
  assert_eq(lang_mermaid.unwrap(), "mermaid")
}
