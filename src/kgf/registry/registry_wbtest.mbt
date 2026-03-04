///|
/// Registry tests - validates that all KGF files in kgfs/ parse correctly.

///|
/// Helper to get the kgfs directory path.
fn get_kgfs_dir() -> String {
  // Project root relative paths - adjust based on test execution context
  let paths = [
    "kgfs", "../kgfs", "../../kgfs", "../../../kgfs", "../../../../kgfs",
  ]
  for path in paths {
    try {
      if @fs.is_dir(path) {
        return path
      }
    } catch {
      _ => continue
    }
  }
  "kgfs"
}

///|
test "registry loads all kgf files from directory" {
  let dir = get_kgfs_dir()
  let registry = KGFRegistry::load_from_dir(dir)
  // Should have loaded multiple specs
  assert_true(registry.spec_count() > 0)
}

///|
test "registry: programming language kgfs parse correctly" {
  let dir = get_kgfs_dir()
  let registry = KGFRegistry::load_from_dir(dir)

  // Core programming languages
  let expected_langs = [
    "typescript", "javascript", "python", "go", "rust", "java", "ruby", "php", "swift",
    "kotlin", "dart", "scala", "elixir", "haskell", "ocaml", "zig", "julia", "lua",
    "clojure", "c", "cpp", "csharp", "moonbit",
  ]

  for lang in expected_langs {
    let spec = registry.get_spec(lang)
    match spec {
      Some(s) => {
        // Verify basic structure
        assert_eq(s.get_language(), lang)
        // Should have tokens defined
        assert_true(s.get_tokens().length() > 0)
        // Should have resolve chain (kgf 0.6 format)
        let resolver = s.get_resolver()
        assert_true(resolver.has_resolve_chain())
      }
      None => {
        // Print which language is missing for debugging
        println("Missing spec for: " + lang)
        assert_true(false)
      }
    }
  }
}

///|
test "registry: extension to language mapping" {
  let dir = get_kgfs_dir()
  let registry = KGFRegistry::load_from_dir(dir)

  // Test common extensions
  fn check_ext(
    r : KGFRegistry,
    ext : String,
    expected_lang : String,
  ) -> Unit raise {
    match r.get_lang_from_ext(ext) {
      Some(lang) => assert_eq(lang, expected_lang)
      None => {
        println("No mapping for extension: " + ext)
        assert_true(false)
      }
    }
  }

  check_ext(registry, ".ts", "typescript")
  check_ext(registry, ".tsx", "typescript")
  check_ext(registry, ".js", "javascript")
  check_ext(registry, ".py", "python")
  check_ext(registry, ".go", "go")
  check_ext(registry, ".rs", "rust")
  check_ext(registry, ".java", "java")
  check_ext(registry, ".rb", "ruby")
  check_ext(registry, ".php", "php")
  check_ext(registry, ".swift", "swift")
  check_ext(registry, ".kt", "kotlin")
  check_ext(registry, ".dart", "dart")
  check_ext(registry, ".scala", "scala")
  check_ext(registry, ".ex", "elixir")
  check_ext(registry, ".hs", "haskell")
  check_ext(registry, ".ml", "ocaml")
  check_ext(registry, ".zig", "zig")
  check_ext(registry, ".jl", "julia")
  check_ext(registry, ".lua", "lua")
  check_ext(registry, ".clj", "clojure")
  check_ext(registry, ".c", "c")
  check_ext(registry, ".cpp", "cpp")
  check_ext(registry, ".cs", "csharp")
  check_ext(registry, ".mbt", "moonbit")
}

///|
test "registry: resolve chain format validation" {
  let dir = get_kgfs_dir()
  let registry = KGFRegistry::load_from_dir(dir)

  // Validate specific resolve chain configurations

  // TypeScript should have manifest step for package.json
  match registry.get_spec("typescript") {
    Some(spec) => {
      let chain = spec.get_resolver().get_resolve_chain()
      assert_true(chain.length() >= 3)
      // First step should be manifest
      assert_eq(chain[0].get_step_type().as_string(), "manifest")
      assert_eq(chain[0].get_file(), "package.json")
    }
    None => assert_true(false)
  }

  // Python should have manifest step for pyproject.toml
  match registry.get_spec("python") {
    Some(spec) => {
      let chain = spec.get_resolver().get_resolve_chain()
      assert_true(chain.length() >= 4)
      // First step should be manifest (pyproject.toml)
      assert_eq(chain[0].get_step_type().as_string(), "manifest")
      // Should also have marker step
      let has_marker = chain
        .iter()
        .any(fn(step) { step.get_step_type().as_string() == "marker" })
      assert_true(has_marker)
    }
    None => assert_true(false)
  }

  // Rust should have sibling step for mod.rs pattern
  match registry.get_spec("rust") {
    Some(spec) => {
      let chain = spec.get_resolver().get_resolve_chain()
      // Should have index, sibling, ext, fallback
      let has_sibling = chain
        .iter()
        .any(fn(step) { step.get_step_type().as_string() == "sibling" })
      assert_true(has_sibling)
    }
    None => assert_true(false)
  }
}

///|
/// Helper to get the examples directory path.
fn get_examples_dir() -> String {
  let kgfs_dir = get_kgfs_dir()
  kgfs_dir + "/examples"
}

///|
/// Helper to check if tokens contain a specific kind.
fn has_token_kind(tokens : Array[@types.Tok], kind : String) -> Bool {
  for token in tokens {
    if token.kind == kind {
      return true
    }
  }
  false
}

///|
/// Test that example source files can be tokenized by their corresponding KGF specs.
test "registry: tokenize example source files" {
  let dir = get_kgfs_dir()
  let registry = KGFRegistry::load_from_dir(dir)
  let examples_dir = get_examples_dir()

  // Test TypeScript example - verify keyword tokenization with word boundary
  let ts_spec = registry.get_spec("typescript").unwrap()
  let ts_lexer = @lexer.Lexer::new(ts_spec.get_tokens())
  let ts_source = @fs.read_file_to_string(
    examples_dir + "/typescript/src/main.ts",
  ) catch {
    _ => ""
  }
  if ts_source.length() > 0 {
    let ts_tokens = ts_lexer.tokenize(ts_source)
    assert_true(ts_tokens.length() > 0)
    // With word boundary support, import keyword should be properly recognized
    assert_true(has_token_kind(ts_tokens, "KW_import"))
  }

  // Test Python example - verify keyword tokenization
  let py_spec = registry.get_spec("python").unwrap()
  let py_lexer = @lexer.Lexer::new(py_spec.get_tokens())
  let py_source = @fs.read_file_to_string(examples_dir + "/python/main.py") catch {
    _ => ""
  }
  if py_source.length() > 0 {
    let py_tokens = py_lexer.tokenize(py_source)
    assert_true(py_tokens.length() > 0)
    // Should have import and def tokens
    assert_true(has_token_kind(py_tokens, "KW_import"))
    assert_true(has_token_kind(py_tokens, "KW_def"))
  }

  // Test Go example - verify keyword tokenization
  let go_spec = registry.get_spec("go").unwrap()
  let go_lexer = @lexer.Lexer::new(go_spec.get_tokens())
  let go_source = @fs.read_file_to_string(examples_dir + "/go/main.go") catch {
    _ => ""
  }
  if go_source.length() > 0 {
    let go_tokens = go_lexer.tokenize(go_source)
    assert_true(go_tokens.length() > 0)
    // Should have package and func tokens
    assert_true(has_token_kind(go_tokens, "KW_package"))
    assert_true(has_token_kind(go_tokens, "KW_func"))
  }

  // Test Rust example - verify keyword tokenization
  let rs_spec = registry.get_spec("rust").unwrap()
  let rs_lexer = @lexer.Lexer::new(rs_spec.get_tokens())
  let rs_source = @fs.read_file_to_string(examples_dir + "/rust/main.rs") catch {
    _ => ""
  }
  if rs_source.length() > 0 {
    let rs_tokens = rs_lexer.tokenize(rs_source)
    assert_true(rs_tokens.length() > 0)
    // Should have use, fn, pub tokens
    assert_true(has_token_kind(rs_tokens, "KW_use"))
    assert_true(has_token_kind(rs_tokens, "KW_fn"))
    assert_true(has_token_kind(rs_tokens, "KW_pub"))
  }
}

///|
/// Test that example source files can be parsed by their corresponding KGF specs.
test "registry: parse example source files" {
  let dir = get_kgfs_dir()
  let registry = KGFRegistry::load_from_dir(dir)
  let examples_dir = get_examples_dir()

  // Test JavaScript example
  let js_spec = registry.get_spec("javascript").unwrap()
  let js_peg = @peg.build_peg(js_spec)
  let js_lexer = @lexer.Lexer::new(js_spec.get_tokens())
  let js_source = @fs.read_file_to_string(
    examples_dir + "/javascript/src/app.js",
  ) catch {
    _ => ""
  }
  if js_source.length() > 0 {
    let js_tokens = js_lexer.tokenize(js_source)
    let js_result = @peg.run_parse(js_peg, js_spec, "Module", js_tokens)
    assert_true(js_result is Some(_))
    assert_true(js_result.unwrap().ok)
  }

  // Test TypeScript example
  let ts_spec = registry.get_spec("typescript").unwrap()
  let ts_peg = @peg.build_peg(ts_spec)
  let ts_lexer = @lexer.Lexer::new(ts_spec.get_tokens())
  let ts_source = @fs.read_file_to_string(
    examples_dir + "/typescript/src/main.ts",
  ) catch {
    _ => ""
  }
  if ts_source.length() > 0 {
    let ts_tokens = ts_lexer.tokenize(ts_source)
    let ts_result = @peg.run_parse(ts_peg, ts_spec, "Module", ts_tokens)
    assert_true(ts_result is Some(_))
    assert_true(ts_result.unwrap().ok)
  }

  // Test Python example
  let py_spec = registry.get_spec("python").unwrap()
  let py_peg = @peg.build_peg(py_spec)
  let py_lexer = @lexer.Lexer::new(py_spec.get_tokens())
  let py_source = @fs.read_file_to_string(examples_dir + "/python/main.py") catch {
    _ => ""
  }
  if py_source.length() > 0 {
    let py_tokens = py_lexer.tokenize(py_source)
    let py_result = @peg.run_parse(py_peg, py_spec, "Module", py_tokens)
    assert_true(py_result is Some(_))
    assert_true(py_result.unwrap().ok)
  }

  // Test Go example
  let go_spec = registry.get_spec("go").unwrap()
  let go_peg = @peg.build_peg(go_spec)
  let go_lexer = @lexer.Lexer::new(go_spec.get_tokens())
  let go_source = @fs.read_file_to_string(examples_dir + "/go/main.go") catch {
    _ => ""
  }
  if go_source.length() > 0 {
    let go_tokens = go_lexer.tokenize(go_source)
    let go_result = @peg.run_parse(go_peg, go_spec, "Module", go_tokens)
    assert_true(go_result is Some(_))
    assert_true(go_result.unwrap().ok)
  }

  // Test Rust example
  let rs_spec = registry.get_spec("rust").unwrap()
  let rs_peg = @peg.build_peg(rs_spec)
  let rs_lexer = @lexer.Lexer::new(rs_spec.get_tokens())
  let rs_source = @fs.read_file_to_string(examples_dir + "/rust/main.rs") catch {
    _ => ""
  }
  if rs_source.length() > 0 {
    let rs_tokens = rs_lexer.tokenize(rs_source)
    let rs_result = @peg.run_parse(rs_peg, rs_spec, "Module", rs_tokens)
    assert_true(rs_result is Some(_))
    assert_true(rs_result.unwrap().ok)
  }
}

///|
/// Test that HTML and Markdown examples can be parsed.
test "registry: parse markup example files" {
  let dir = get_kgfs_dir()
  let registry = KGFRegistry::load_from_dir(dir)
  let examples_dir = get_examples_dir()

  // Test HTML example
  let html_spec = registry.get_spec("html").unwrap()
  let html_peg = @peg.build_peg(html_spec)
  let html_lexer = @lexer.Lexer::new(html_spec.get_tokens())
  let html_source = @fs.read_file_to_string(examples_dir + "/html/index.html") catch {
    _ => ""
  }
  if html_source.length() > 0 {
    let html_tokens = html_lexer.tokenize(html_source)
    let html_result = @peg.run_parse(html_peg, html_spec, "Doc", html_tokens)
    assert_true(html_result is Some(_))
    assert_true(html_result.unwrap().ok)
  }

  // Test Markdown example
  let md_spec = registry.get_spec("markdown").unwrap()
  let md_peg = @peg.build_peg(md_spec)
  let md_lexer = @lexer.Lexer::new(md_spec.get_tokens())
  let md_source = @fs.read_file_to_string(examples_dir + "/markdown/README.md") catch {
    _ => ""
  }
  if md_source.length() > 0 {
    let md_tokens = md_lexer.tokenize(md_source)
    let md_result = @peg.run_parse(md_peg, md_spec, "Doc", md_tokens)
    assert_true(md_result is Some(_))
    assert_true(md_result.unwrap().ok)
  }
}

///|
/// Test natural language examples can be tokenized.
test "registry: tokenize natural language examples" {
  let dir = get_kgfs_dir()
  let registry = KGFRegistry::load_from_dir(dir)
  let examples_dir = get_examples_dir()

  // Test Japanese example
  let ja_spec = registry.get_spec("japanese").unwrap()
  let ja_lexer = @lexer.Lexer::new(ja_spec.get_tokens())
  let ja_source = @fs.read_file_to_string(examples_dir + "/japanese/simple.txt") catch {
    _ => ""
  }
  if ja_source.length() > 0 {
    let ja_tokens = ja_lexer.tokenize(ja_source)
    assert_true(ja_tokens.length() > 0)
  }

  // Test English example
  let en_spec = registry.get_spec("english").unwrap()
  let en_lexer = @lexer.Lexer::new(en_spec.get_tokens())
  let en_source = @fs.read_file_to_string(examples_dir + "/english/sample.txt") catch {
    _ => ""
  }
  if en_source.length() > 0 {
    let en_tokens = en_lexer.tokenize(en_source)
    assert_true(en_tokens.length() > 0)
  }

  // Test Korean example
  let ko_spec = registry.get_spec("korean").unwrap()
  let ko_lexer = @lexer.Lexer::new(ko_spec.get_tokens())
  let ko_source = @fs.read_file_to_string(examples_dir + "/korean/sample.txt") catch {
    _ => ""
  }
  if ko_source.length() > 0 {
    let ko_tokens = ko_lexer.tokenize(ko_source)
    assert_true(ko_tokens.length() > 0)
  }

  // Test Chinese example
  let zh_spec = registry.get_spec("chinese").unwrap()
  let zh_lexer = @lexer.Lexer::new(zh_spec.get_tokens())
  let zh_source = @fs.read_file_to_string(examples_dir + "/chinese/sample.txt") catch {
    _ => ""
  }
  if zh_source.length() > 0 {
    let zh_tokens = zh_lexer.tokenize(zh_source)
    assert_true(zh_tokens.length() > 0)
  }
}

///|
/// Test SQL examples can be parsed.
test "registry: parse sql examples" {
  let dir = get_kgfs_dir()
  let registry = KGFRegistry::load_from_dir(dir)
  let examples_dir = get_examples_dir()

  // Test SQL DDL example
  let sql_spec = registry.get_spec("sql-ddl").unwrap()
  let sql_peg = @peg.build_peg(sql_spec)
  let sql_lexer = @lexer.Lexer::new(sql_spec.get_tokens())
  let sql_source = @fs.read_file_to_string(examples_dir + "/sql-ddl/schema.sql") catch {
    _ => ""
  }
  if sql_source.length() > 0 {
    let sql_tokens = sql_lexer.tokenize(sql_source)
    assert_true(sql_tokens.length() > 0)
    let sql_result = @peg.run_parse(sql_peg, sql_spec, "Doc", sql_tokens)
    assert_true(sql_result is Some(_))
    assert_true(sql_result.unwrap().ok)
  }
}

///|
test "registry: all kgfs are version 0.6" {
  let dir = get_kgfs_dir()
  let is_dir = @fs.is_dir(dir) catch { _ => false }
  if not(is_dir) {
    return // Skip if directory not found
  }

  let entries = @fs.read_dir(dir)
  for entry in entries {
    if entry.has_suffix(".kgf") {
      let path = dir + "/" + entry
      let content = @fs.read_file_to_string(path)
      // All files should start with "kgf 0.6"
      assert_true(
        content.has_prefix("kgf 0.6") || content.has_prefix("\nkgf 0.6"),
      )
    }
  }
}
