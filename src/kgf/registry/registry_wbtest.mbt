///|
/// Registry tests - validates that all KGF files in kgfs/ parse correctly.
/// Tests are consolidated to minimize registry loading overhead.

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
/// Main registry test - loads registry once and runs all validations.
test "registry: comprehensive validation" {
  let dir = @kgf_fixtures.get_kgfs_dir()
  let registry = KGFRegistry::load_from_dir(dir)

  // Test 1: Should have loaded multiple specs
  assert_true(registry.spec_count() > 0)

  // Test 2: Programming languages should exist and have correct structure
  let expected_langs = [
    "typescript", "javascript", "python", "go", "rust", "java", "ruby", "php", "swift",
    "kotlin", "dart", "scala", "elixir", "haskell", "ocaml", "zig", "julia", "lua",
    "clojure", "c", "cpp", "csharp", "moonbit",
  ]
  for lang in expected_langs {
    match registry.get_spec(lang) {
      Some(s) => {
        assert_eq(s.get_language(), lang)
        assert_true(s.get_tokens().length() > 0)
        assert_true(s.get_resolver().has_resolve_chain())
      }
      None => {
        println("Missing spec for: " + lang)
        assert_true(false)
      }
    }
  }

  // Test 3: Extension to language mapping
  let ext_mappings = [
    (".ts", "typescript"),
    (".tsx", "typescript-jsx"),
    (".js", "javascript"),
    (".jsx", "javascript-jsx"),
    (".py", "python"),
    (".go", "go"),
    (".rs", "rust"),
    (".java", "java"),
    (".rb", "ruby"),
    (".php", "php"),
    (".swift", "swift"),
    (".kt", "kotlin"),
    (".dart", "dart"),
    (".scala", "scala"),
    (".ex", "elixir"),
    (".hs", "haskell"),
    (".ml", "ocaml"),
    (".zig", "zig"),
    (".jl", "julia"),
    (".lua", "lua"),
    (".clj", "clojure"),
    (".c", "c"),
    (".cpp", "cpp"),
    (".cs", "csharp"),
    (".mbt", "moonbit"),
  ]
  for mapping in ext_mappings {
    let (ext, expected_lang) = mapping
    match registry.get_lang_from_ext(ext) {
      Some(lang) => assert_eq(lang, expected_lang)
      None => {
        println("No mapping for: " + ext)
        assert_true(false)
      }
    }
  }

  // Test 4: TypeScript resolve chain validation
  match registry.get_spec("typescript") {
    Some(spec) => {
      let chain = spec.get_resolver().get_resolve_chain()
      assert_true(chain.length() >= 4)
      assert_eq(chain[0].get_step_type().as_string(), "exact")
      assert_eq(chain[1].get_step_type().as_string(), "manifest")
      assert_eq(chain[1].get_file(), "package.json")
    }
    None => assert_true(false)
  }

  // Test 5: Python resolve chain validation
  match registry.get_spec("python") {
    Some(spec) => {
      let chain = spec.get_resolver().get_resolve_chain()
      assert_true(chain.length() >= 4)
      assert_eq(chain[0].get_step_type().as_string(), "manifest")
      let has_marker = chain
        .iter()
        .any(fn(step) { step.get_step_type().as_string() == "marker" })
      assert_true(has_marker)
    }
    None => assert_true(false)
  }

  // Test 6: Rust resolve chain validation
  match registry.get_spec("rust") {
    Some(spec) => {
      let chain = spec.get_resolver().get_resolve_chain()
      let has_sibling = chain
        .iter()
        .any(fn(step) { step.get_step_type().as_string() == "sibling" })
      assert_true(has_sibling)
    }
    None => assert_true(false)
  }

  // Test 7: is_file_supported
  assert_true(registry.is_file_supported("src/core/moon.pkg"))
  assert_true(registry.is_file_supported("moon.pkg"))
  assert_true(registry.is_file_supported("src/main.ts"))
  assert_true(registry.is_file_supported("main.py"))
  assert_true(registry.is_file_supported("main.go"))
  assert_false(registry.is_file_supported("moon.pkg.bak"))
  assert_false(registry.is_file_supported("file.xyz"))

  // Test 8: .md extension should map to markdown (not wiki specs)
  // Wiki specs (gitlab-wiki, github-wiki) also claim .md but are domain-specific
  // (have special_files feature) and should not override the general markdown spec.
  assert_eq(registry.get_lang_from_ext(".md"), Some("markdown"))
  assert_eq(registry.detect_from_path("docs/spec.md"), Some("markdown"))
  assert_eq(registry.detect_from_path("README.md"), Some("markdown"))

  // Test 9: project marker patterns come from KGF, not hardcoded caller lists
  let project_markers = registry.get_project_markers()
  assert_true(
    project_markers.iter().any(fn(marker) { marker == "package.json" }),
  )
  assert_true(project_markers.iter().any(fn(marker) { marker == "go.mod" }))
  assert_true(project_markers.iter().any(fn(marker) { marker == "Cargo.toml" }))
  assert_true(project_markers.iter().any(fn(marker) { marker == "moon.pkg" }))
  assert_true(project_markers.iter().any(fn(marker) { marker == "*.csproj" }))
}

///|
/// Tokenization and parsing tests - loads registry once for all language tests.
test "registry: tokenize and parse examples" {
  let dir = @kgf_fixtures.get_kgfs_dir()
  let registry = KGFRegistry::load_from_dir(dir)
  let fixtures_dir = @kgf_fixtures.get_fixtures_dir()

  // TypeScript tokenization
  let ts_spec = registry.get_spec("typescript").unwrap()
  let ts_lexer = @lexer.Lexer::new(ts_spec.get_tokens())
  let ts_source = @fs.read_file_to_string(
    fixtures_dir + "/programming/typescript/src/main.ts",
  ) catch {
    _ => ""
  }
  if ts_source.length() > 0 {
    let ts_tokens = ts_lexer.tokenize(ts_source)
    assert_true(ts_tokens.length() > 0)
    assert_true(has_token_kind(ts_tokens, "KW_import"))
    // Parse TypeScript
    let ts_peg = @peg.build_peg(ts_spec)
    let ts_result = @peg.run_parse(ts_peg, ts_spec, "Module", ts_tokens)
    assert_true(ts_result is Some(_))
    assert_true(ts_result.unwrap().ok)
  }

  // JavaScript tokenization and parsing
  let js_spec = registry.get_spec("javascript").unwrap()
  let js_lexer = @lexer.Lexer::new(js_spec.get_tokens())
  let js_source = @fs.read_file_to_string(
    fixtures_dir + "/programming/javascript/src/app.js",
  ) catch {
    _ => ""
  }
  if js_source.length() > 0 {
    let js_tokens = js_lexer.tokenize(js_source)
    assert_true(js_tokens.length() > 0)
    let js_peg = @peg.build_peg(js_spec)
    let js_result = @peg.run_parse(js_peg, js_spec, "Module", js_tokens)
    assert_true(js_result is Some(_))
    assert_true(js_result.unwrap().ok)
  }

  // Python tokenization and parsing
  let py_spec = registry.get_spec("python").unwrap()
  let py_lexer = @lexer.Lexer::new(py_spec.get_tokens())
  let py_source = @fs.read_file_to_string(
    fixtures_dir + "/programming/python/main.py",
  ) catch {
    _ => ""
  }
  if py_source.length() > 0 {
    let py_tokens = py_lexer.tokenize(py_source)
    assert_true(py_tokens.length() > 0)
    assert_true(has_token_kind(py_tokens, "KW_import"))
    assert_true(has_token_kind(py_tokens, "KW_def"))
    let py_peg = @peg.build_peg(py_spec)
    let py_result = @peg.run_parse(py_peg, py_spec, "Module", py_tokens)
    assert_true(py_result is Some(_))
    assert_true(py_result.unwrap().ok)
  }

  // Go tokenization and parsing
  let go_spec = registry.get_spec("go").unwrap()
  let go_lexer = @lexer.Lexer::new(go_spec.get_tokens())
  let go_source = @fs.read_file_to_string(
    fixtures_dir + "/programming/go/main.go",
  ) catch {
    _ => ""
  }
  if go_source.length() > 0 {
    let go_tokens = go_lexer.tokenize(go_source)
    assert_true(go_tokens.length() > 0)
    assert_true(has_token_kind(go_tokens, "KW_package"))
    assert_true(has_token_kind(go_tokens, "KW_func"))
    let go_peg = @peg.build_peg(go_spec)
    let go_result = @peg.run_parse(go_peg, go_spec, "Module", go_tokens)
    assert_true(go_result is Some(_))
    assert_true(go_result.unwrap().ok)
  }

  // Rust tokenization and parsing
  let rs_spec = registry.get_spec("rust").unwrap()
  let rs_lexer = @lexer.Lexer::new(rs_spec.get_tokens())
  let rs_source = @fs.read_file_to_string(
    fixtures_dir + "/programming/rust/main.rs",
  ) catch {
    _ => ""
  }
  if rs_source.length() > 0 {
    let rs_tokens = rs_lexer.tokenize(rs_source)
    assert_true(rs_tokens.length() > 0)
    assert_true(has_token_kind(rs_tokens, "KW_fn"))
    let rs_peg = @peg.build_peg(rs_spec)
    let rs_result = @peg.run_parse(rs_peg, rs_spec, "Module", rs_tokens)
    assert_true(rs_result is Some(_))
    assert_true(rs_result.unwrap().ok)
  }
}

///|
/// Markup and DSL parsing tests.
test "registry: parse markup and dsl" {
  let dir = @kgf_fixtures.get_kgfs_dir()
  let registry = KGFRegistry::load_from_dir(dir)
  let fixtures_dir = @kgf_fixtures.get_fixtures_dir()

  // HTML
  let html_spec = registry.get_spec("html").unwrap()
  let html_peg = @peg.build_peg(html_spec)
  let html_lexer = @lexer.Lexer::new(html_spec.get_tokens())
  let html_source = @fs.read_file_to_string(
    fixtures_dir + "/dsl/html/index.html",
  ) catch {
    _ => ""
  }
  if html_source.length() > 0 {
    let html_tokens = html_lexer.tokenize(html_source)
    let html_result = @peg.run_parse(html_peg, html_spec, "Doc", html_tokens)
    assert_true(html_result is Some(_))
    assert_true(html_result.unwrap().ok)
  }

  // Markdown
  let md_spec = registry.get_spec("markdown").unwrap()
  let md_peg = @peg.build_peg(md_spec)
  let md_lexer = @lexer.Lexer::new(md_spec.get_tokens())
  let md_source = @fs.read_file_to_string(
    fixtures_dir + "/dsl/markdown/README.md",
  ) catch {
    _ => ""
  }
  if md_source.length() > 0 {
    let md_tokens = md_lexer.tokenize(md_source)
    let md_result = @peg.run_parse(md_peg, md_spec, "Doc", md_tokens)
    assert_true(md_result is Some(_))
    assert_true(md_result.unwrap().ok)
  }

  // SQL DDL
  let sql_spec = registry.get_spec("sql-ddl").unwrap()
  let sql_peg = @peg.build_peg(sql_spec)
  let sql_lexer = @lexer.Lexer::new(sql_spec.get_tokens())
  let sql_source = @fs.read_file_to_string(
    fixtures_dir + "/dsl/sql-ddl/schema.sql",
  ) catch {
    _ => ""
  }
  if sql_source.length() > 0 {
    let sql_tokens = sql_lexer.tokenize(sql_source)
    let sql_result = @peg.run_parse(sql_peg, sql_spec, "Doc", sql_tokens)
    assert_true(sql_result is Some(_))
    assert_true(sql_result.unwrap().ok)
  }
}

///|
/// Natural language tokenization tests.
test "registry: tokenize natural languages" {
  let dir = @kgf_fixtures.get_kgfs_dir()
  let registry = KGFRegistry::load_from_dir(dir)
  let fixtures_dir = @kgf_fixtures.get_fixtures_dir()

  let natural_tests = [
    ("japanese", "/natural/japanese/simple.txt"),
    ("english", "/natural/english/sample.txt"),
    ("korean", "/natural/korean/sample.txt"),
    ("chinese", "/natural/chinese/sample.txt"),
  ]

  for test_case in natural_tests {
    let (lang, path) = test_case
    let spec = registry.get_spec(lang).unwrap()
    let lexer = @lexer.Lexer::new(spec.get_tokens())
    let source = @fs.read_file_to_string(fixtures_dir + path) catch { _ => "" }
    if source.length() > 0 {
      let tokens = lexer.tokenize(source)
      assert_true(tokens.length() > 0)
    }
  }
}

///|
/// KGF version validation.
test "registry: all kgfs are version 0.6" {
  let dir = @kgf_fixtures.get_kgfs_dir()
  let is_dir = @fs.is_dir(dir) catch { _ => false }
  if !is_dir {
    return
  }
  let entries = @fs.read_dir(dir)
  for entry in entries {
    if entry.has_suffix(".kgf") {
      let path = dir + "/" + entry
      let content = @fs.read_file_to_string(path)
      assert_true(
        content.has_prefix("kgf 0.6") || content.has_prefix("\nkgf 0.6"),
      )
    }
  }
}
