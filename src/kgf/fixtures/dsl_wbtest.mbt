///|
/// DSL fixtures tests.
/// Validates KGF parsing for SQL, HTML, Markdown.

///|
test "dsl: tokenize sql, html, markdown" {
  let registry = @registry.KGFRegistry::load_from_dir(get_kgfs_dir())
  let fixtures = get_fixtures_dir()

  // SQL DDL
  let sql_spec = registry.get_spec("sql-ddl").unwrap()
  let sql_lexer = @lexer.Lexer::new(sql_spec.get_tokens())
  let sql_src = @fs.read_file_to_string(fixtures + "/dsl/sql-ddl/schema.sql") catch {
    _ => ""
  }
  if sql_src.length() > 0 {
    let tokens = sql_lexer.tokenize(sql_src)
    assert_true(tokens.length() > 0)
    assert_true(tokens.iter().any(fn(t) { t.kind == "KW_CREATE" }))
  }

  // HTML
  let html_spec = registry.get_spec("html").unwrap()
  let html_lexer = @lexer.Lexer::new(html_spec.get_tokens())
  let html_src = @fs.read_file_to_string(fixtures + "/dsl/html/index.html") catch {
    _ => ""
  }
  if html_src.length() > 0 {
    let tokens = html_lexer.tokenize(html_src)
    assert_true(tokens.length() > 0)
  }

  // Markdown
  let md_spec = registry.get_spec("markdown").unwrap()
  let md_lexer = @lexer.Lexer::new(md_spec.get_tokens())
  let md_src = @fs.read_file_to_string(fixtures + "/dsl/markdown/README.md") catch {
    _ => ""
  }
  if md_src.length() > 0 {
    let tokens = md_lexer.tokenize(md_src)
    assert_true(tokens.length() > 0)
    assert_true(tokens.iter().any(fn(t) { t.kind == "LBRACK" }))
  }
}
