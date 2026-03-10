///|
/// Programming language fixtures tests.
/// Validates KGF parsing for TypeScript, JavaScript, Python, Go, Rust.

///|
test "programming: tokenize all languages" {
  let registry = @registry.KGFRegistry::load_from_dir(get_kgfs_dir())
  let fixtures = get_fixtures_dir()

  // TypeScript
  let ts_spec = registry.get_spec("typescript").unwrap()
  let ts_lexer = @lexer.Lexer::new(ts_spec.get_tokens())
  let ts_source = @fs.read_file_to_string(
    fixtures + "/programming/typescript/src/main.ts",
  ) catch {
    _ => ""
  }
  if ts_source.length() > 0 {
    let tokens = ts_lexer.tokenize(ts_source)
    assert_true(tokens.length() > 0)
    assert_true(tokens.iter().any(fn(t) { t.kind == "KW_import" }))
  }

  // JavaScript
  let js_spec = registry.get_spec("javascript").unwrap()
  let js_lexer = @lexer.Lexer::new(js_spec.get_tokens())
  let js_source = @fs.read_file_to_string(
    fixtures + "/programming/javascript/src/app.js",
  ) catch {
    _ => ""
  }
  if js_source.length() > 0 {
    let tokens = js_lexer.tokenize(js_source)
    assert_true(tokens.length() > 0)
  }

  // Python
  let py_spec = registry.get_spec("python").unwrap()
  let py_lexer = @lexer.Lexer::new(py_spec.get_tokens())
  let py_source = @fs.read_file_to_string(
    fixtures + "/programming/python/main.py",
  ) catch {
    _ => ""
  }
  if py_source.length() > 0 {
    let tokens = py_lexer.tokenize(py_source)
    assert_true(tokens.length() > 0)
    assert_true(tokens.iter().any(fn(t) { t.kind == "KW_def" }))
    assert_true(tokens.iter().any(fn(t) { t.kind == "KW_import" }))
  }

  // Go
  let go_spec = registry.get_spec("go").unwrap()
  let go_lexer = @lexer.Lexer::new(go_spec.get_tokens())
  let go_source = @fs.read_file_to_string(fixtures + "/programming/go/main.go") catch {
    _ => ""
  }
  if go_source.length() > 0 {
    let tokens = go_lexer.tokenize(go_source)
    assert_true(tokens.length() > 0)
    assert_true(tokens.iter().any(fn(t) { t.kind == "KW_package" }))
    assert_true(tokens.iter().any(fn(t) { t.kind == "KW_func" }))
  }

  // Rust
  let rs_spec = registry.get_spec("rust").unwrap()
  let rs_lexer = @lexer.Lexer::new(rs_spec.get_tokens())
  let rs_source = @fs.read_file_to_string(
    fixtures + "/programming/rust/main.rs",
  ) catch {
    _ => ""
  }
  if rs_source.length() > 0 {
    let tokens = rs_lexer.tokenize(rs_source)
    assert_true(tokens.length() > 0)
    assert_true(tokens.iter().any(fn(t) { t.kind == "KW_fn" }))
  }
}
