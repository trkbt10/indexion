///|
/// DSL fixtures tests.
/// Validates KGF parsing for SQL, HTML, Markdown.

///|
test "dsl: tokenize sql, html, markdown" {
  let registry = get_fixture_registry()
  let fixtures = get_fixtures_dir()

  // SQL DDL
  let sql_spec = registry.get_spec("sql-ddl").unwrap()
  let sql_lexer = @lexer.Lexer::for_spec(sql_spec)
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
  let html_lexer = @lexer.Lexer::for_spec(html_spec)
  let html_src = @fs.read_file_to_string(fixtures + "/dsl/html/index.html") catch {
    _ => ""
  }
  if html_src.length() > 0 {
    let tokens = html_lexer.tokenize(html_src)
    assert_true(tokens.length() > 0)
  }

  // Markdown
  let md_spec = registry.get_spec("markdown").unwrap()
  let md_lexer = @lexer.Lexer::for_spec(md_spec)
  let md_src = @fs.read_file_to_string(fixtures + "/dsl/markdown/README.md") catch {
    _ => ""
  }
  if md_src.length() > 0 {
    let tokens = md_lexer.tokenize(md_src)
    assert_true(tokens.length() > 0)
    assert_true(tokens.iter().any(fn(t) { t.kind == "LBRACK" }))
  }
}

///|
/// Read a fixture file, failing the test if it is missing or empty: a
/// silently skipped file is how a broken spec keeps passing.
///
/// `raise` because the assertion below raises on failure, and a function
/// that calls a raising one must say so in its own signature.
fn read_fixture(rel : String) -> String raise {
  let path = get_fixtures_dir() + rel
  let content = @fs.read_file_to_string(path) catch { _ => "" }
  assert_true(content.length() > 0)
  content
}

///|
/// Assert that a spec consumes a whole file: every token reaches the start
/// rule and the lexer recognized every character. A parse that stops at the
/// first construct the grammar does not model silently drops everything
/// after it, which is what these specs used to do.
fn assert_parses_whole_file(
  spec_name : String,
  rel_path : String,
  file_path : String,
) -> Unit raise {
  let source = read_fixture(rel_path)
  let result = run_pipeline_with_registry(
    get_fixture_registry(),
    spec_name,
    source,
    file_path,
  )
  assert_true(result.parse_ok)
  assert_eq(result.lex_errors, 0)
  assert_eq(result.tokens_consumed, result.tokens_total)
  assert_true(result.parse_complete())
}

///|
/// Markdown's `Doc` rule used to accept only TEXT/LT/GT/PIPE/HASH, so every
/// document stopped at its first heading, code fence or inline code span and
/// no link after that point was ever seen.
test "dsl: markdown parses whole documents, not just their first line" {
  assert_parses_whole_file(
    "markdown", "/dsl/markdown/README.md", "fixtures/dsl/markdown/README.md",
  )
  assert_parses_whole_file(
    "markdown", "/dsl/markdown/docs/faq.md", "fixtures/dsl/markdown/docs/faq.md",
  )
  assert_parses_whole_file(
    "markdown", "/story/dorian-gray/sources/references/characters.md", "fixtures/story/dorian-gray/sources/references/characters.md",
  )
  assert_parses_whole_file(
    "markdown", "/project/spec-verify-jsonrpc/spec/jsonrpc-2.0.md", "fixtures/project/spec-verify-jsonrpc/spec/jsonrpc-2.0.md",
  )
}

///|
/// All four markdown link forms must bind a path. `[x](p)` bound `path`
/// inside a nested `Target` rule, and labels do not propagate from a child
/// rule to its parent, so the import edge resolved an empty path. The
/// autolink `<https://…>` never matched at all because its closing `>` lexes
/// as TAG_CLOSE, not GT.
test "dsl: markdown extracts every link form" {
  let source =
    #|# Heading with `code`
    #|
    #|See [Guide](docs/guide.md) and <https://example.com>.
    #|![logo](./assets/logo.png)
    #|[[docs/faq#top|FAQ]]
  let result = run_pipeline_with_registry(
    get_fixture_registry(),
    "markdown",
    source,
    "doc.md",
  )
  assert_true(result.parse_complete())
  let mut guide = 0
  let mut autolink = 0
  let mut image = 0
  let mut wiki = 0
  for edge in result.edges {
    let via = edge.attrs.get("via").unwrap_or("")
    if via == "docs/guide.md" {
      guide += 1
    }
    if via == "https://example.com" {
      autolink += 1
    }
    if via == "./assets/logo.png" {
      image += 1
    }
    if via == "docs/faq#top" {
      wiki += 1
    }
  }
  assert_true(guide > 0)
  assert_true(autolink > 0)
  assert_true(image > 0)
  assert_true(wiki > 0)
}

///|
/// A fenced code block is not Markdown: a shell usage line such as
/// `todo add <title...>` inside one must not be extracted as a dependency.
test "dsl: markdown ignores links inside fenced code blocks" {
  let source =
    #|# Usage
    #|
    #|```
    #|todo add <title...>
    #|todo done <id>
    #|```
    #|
    #|Real link: <https://example.com>
  let result = run_pipeline_with_registry(
    get_fixture_registry(),
    "markdown",
    source,
    "usage.md",
  )
  assert_true(result.parse_complete())
  for edge in result.edges {
    let via = edge.attrs.get("via").unwrap_or("")
    assert_true(via != "title...")
    assert_true(via != "id")
  }
  let mut real = 0
  for edge in result.edges {
    if edge.attrs.get("via").unwrap_or("") == "https://example.com" {
      real += 1
    }
  }
  assert_true(real > 0)
}

///|
/// Raw HTML embedded in Markdown is a tag, not an autolink. TAG_OPEN could
/// never fire because its lookahead put an alternation inside `(?=...)`,
/// which this lexer never matches, so `<p align="center">…</p>` degraded to
/// LT + TEXT and `</p>` looked like a link to `/p`.
test "dsl: markdown treats embedded html as tags, not links" {
  let source =
    #|<p align="center">
    #|  <img src="logo.svg" alt="x" height="64">
    #|</p>
    #|
    #|# Title
  let registry = get_fixture_registry()
  let spec = registry.get_spec("markdown").unwrap()
  let lexer = @lexer.Lexer::for_spec(spec)
  let tokens = lexer.tokenize(source)
  assert_true(tokens.iter().any(fn(t) { t.kind == "TAG_OPEN" }))
  let result = run_pipeline_with_registry(registry, "markdown", source, "p.md")
  assert_true(result.parse_complete())
  for edge in result.edges {
    assert_true(edge.attrs.get("via").unwrap_or("") != "/p")
  }
}

///|
/// A minified stylesheet stopped at the first `:` because the rule body
/// accepted no COLON, and the body rule could swallow its own closing brace.
test "dsl: css parses declarations, at-rules and selectors" {
  assert_parses_whole_file(
    "css", "/dsl/html/styles/site.css", "fixtures/dsl/html/styles/site.css",
  )
  let source =
    #|@import url("reset.css");
    #|@import "theme.css";
    #|.btn, #main a:hover { color: #fff; margin: 0 auto !important; }
    #|@media (min-width: 600px) { .btn { padding: 1rem; } }
    #|a[href^="http"]::after { content: "x"; }
  let result = run_pipeline_with_registry(
    get_fixture_registry(),
    "css",
    source,
    "site.css",
  )
  assert_true(result.parse_complete())
  assert_eq(result.lex_errors, 0)
}

///|
/// `@import` bound its path inside a nested `Target` rule, so the import
/// edge always resolved an empty path.
test "dsl: css import edges carry the imported path" {
  let source =
    #|@import url("reset.css");
    #|@import "theme.css";
  let result = run_pipeline_with_registry(
    get_fixture_registry(),
    "css",
    source,
    "site.css",
  )
  assert_true(result.parse_complete())
  let mut reset = 0
  let mut theme = 0
  for edge in result.edges {
    let via = edge.attrs.get("via").unwrap_or("")
    if via == "reset.css" {
      reset += 1
    }
    if via == "theme.css" {
      theme += 1
    }
  }
  assert_true(reset > 0)
  assert_true(theme > 0)
}

///|
/// SQL qualifies names with a dot (`t.col`, `u.*`), but the DDL lexer had no
/// DOT token, so every `.` was dropped as unrecognized input and the parse
/// saw a different query than the one on disk.
test "dsl: sql-ddl lexes qualified names and unterminated statements" {
  assert_parses_whole_file(
    "sql-ddl", "/dsl/sql/queries.sql", "fixtures/dsl/sql/queries.sql",
  )
  assert_parses_whole_file(
    "sql-ddl", "/dsl/sql-ddl/schema.sql", "fixtures/dsl/sql-ddl/schema.sql",
  )
  let registry = get_fixture_registry()
  let spec = registry.get_spec("sql-ddl").unwrap()
  let lexer = @lexer.Lexer::for_spec(spec)
  let tokens = lexer.tokenize("SELECT u.id, u.* FROM users u")
  assert_true(tokens.iter().any(fn(t) { t.kind == "DOT" }))

  // The last statement of a script often has no trailing semicolon.
  let result = run_pipeline_with_registry(
    registry, "sql-ddl", "SELECT t.a FROM t", "q.sql",
  )
  assert_true(result.parse_complete())
  assert_eq(result.lex_errors, 0)
}

///|
/// A column's type and its constraints were bound inside child rules, so
/// every hasColumn edge carried none of them and a table-level FOREIGN KEY
/// produced no tableReferences edge at all.
test "dsl: sql-ddl reports column types and foreign keys" {
  let source =
    #|CREATE TABLE users (id INTEGER PRIMARY KEY, email VARCHAR NOT NULL UNIQUE);
    #|CREATE TABLE posts (id INTEGER PRIMARY KEY, author INTEGER, constraint posts_fk foreign key (author) references users (id));
  let result = run_pipeline_with_registry(
    get_fixture_registry(),
    "sql-ddl",
    source,
    "schema.sql",
  )
  assert_true(result.parse_complete())
  let mut typed = 0
  let mut pk = 0
  let mut not_null = 0
  let mut unique = 0
  let mut fk = 0
  for edge in result.edges {
    if edge_kind_is(edge.kind, "hasColumn") {
      if edge.attrs.get("type") is Some(_) {
        typed += 1
      }
      if edge.attrs.get("isPK") is Some(_) {
        pk += 1
      }
      if edge.attrs.get("isNotNull") is Some(_) {
        not_null += 1
      }
      if edge.attrs.get("isUnique") is Some(_) {
        unique += 1
      }
    }
    if edge_kind_is(edge.kind, "tableReferences") {
      if edge.attrs.get("fkColumn") == Some("author") &&
        edge.attrs.get("refColumn") == Some("id") {
        fk += 1
      }
    }
  }
  assert_true(typed >= 4)
  assert_true(pk >= 2)
  assert_true(not_null >= 1)
  assert_true(unique >= 1)
  assert_eq(fk, 1)
}

///|
/// The html spec had no token for the text between tags, so on a prose-heavy
/// page the lexer dropped thousands of characters and the parse stopped at
/// the first one.
test "dsl: html consumes text content and whole documents" {
  assert_parses_whole_file(
    "html", "/dsl/html/index.html", "fixtures/dsl/html/index.html",
  )
  assert_parses_whole_file(
    "html", "/project/spec-verify-jsonrpc/spec/rfc7396-merge-patch.html", "fixtures/project/spec-verify-jsonrpc/spec/rfc7396-merge-patch.html",
  )
}

///|
/// The html spec feeds link extraction: every attribute value becomes a
/// dependency, and adding a text token must not change that.
test "dsl: html still extracts attribute values as dependencies" {
  let source =
    #|<!DOCTYPE html>
    #|<html><head>
    #|  <link rel="stylesheet" href="styles/site.css">
    #|</head>
    #|<body>
    #|  Some prose with a &amp; entity and a 5 > 3 comparison.
    #|  <a href="./docs/index.html">Docs</a>
    #|</body></html>
  let result = run_pipeline_with_registry(
    get_fixture_registry(),
    "html",
    source,
    "index.html",
  )
  assert_true(result.parse_complete())
  assert_eq(result.lex_errors, 0)
  let mut css = 0
  let mut docs = 0
  for edge in result.edges {
    let via = edge.attrs.get("via").unwrap_or("")
    if via == "styles/site.css" {
      css += 1
    }
    if via == "./docs/index.html" {
      docs += 1
    }
  }
  assert_true(css > 0)
  assert_true(docs > 0)
}

///|
/// A workflow file stopped at the first `- name:` sequence entry, and flow
/// collections, block scalars and anchors were not lexed at all.
test "dsl: yaml parses sequences, flow collections and block scalars" {
  let source =
    #|---
    #|name: CI
    #|on:
    #|  push:
    #|    branches: [main]
    #|jobs:
    #|  build:
    #|    runs-on: ubuntu-latest
    #|    steps:
    #|      - name: Checkout
    #|        uses: actions/checkout@v4
    #|        with:
    #|          submodules: true
    #|      - name: Run
    #|        run: |
    #|          echo one
    #|          echo two
    #|flow: {a: 1, b: 2}
    #|anchor: &base
    #|  a: 1
    #|ref: *base
  let result = run_pipeline_with_registry(
    get_fixture_registry(),
    "yaml",
    source,
    "ci.yml",
  )
  assert_true(result.parse_complete())
  assert_eq(result.lex_errors, 0)
}

///|
/// A command line beginning with a bare word (`set -eu`) lexed that word as
/// Ident, but the only line rule that accepted a command required a Word, so
/// the script stopped at its second line.
test "dsl: shell parses command lines, blocks and quoting" {
  let source =
    #|#!/usr/bin/env sh
    #|set -eu
    #|
    #|repo_root=$(
    #|  CDPATH= cd -- "$(dirname "$0")/.." && pwd
    #|)
    #|
    #|if [ -n "$repo_root" ]; then
    #|  cd "$repo_root"
    #|  for f in a b c; do
    #|    echo "$f"
    #|  done
    #|fi
    #|export PATH="$PATH:/usr/local/bin"
  let result = run_pipeline_with_registry(
    get_fixture_registry(),
    "shell",
    source,
    "script.sh",
  )
  assert_true(result.parse_complete())
  assert_eq(result.lex_errors, 0)
}

///|
/// The two SDD document specs share markdown's lexer and grammar, so they
/// had the same truncating `Doc` rule and the same unbound link path.
test "dsl: sdd specs parse whole documents and bind link paths" {
  let source =
    #|## Requirement 1: Session Timeout
    #|
    #|The system SHALL expire sessions after 15 minutes.
    #|See [design](./design.md).
    #|
    #|```
    #|not: markdown
    #|```
  for spec_name in ["sdd-requirement", "sdd-user-story"] {
    let result = run_pipeline_with_registry(
      get_fixture_registry(),
      spec_name,
      source,
      "spec.md",
    )
    assert_true(result.parse_complete())
    let mut design = 0
    for edge in result.edges {
      if edge.attrs.get("via").unwrap_or("") == "./design.md" {
        design += 1
      }
    }
    assert_true(design > 0)
  }
}

///|
/// `def id kind=Metadata` named a label the grammar never bound, so an
/// indexion metadata comment declared nothing.
test "dsl: wiki specs bind the metadata comment payload" {
  let source =
    #|<!-- indexion:page=Home -->
    #|# Home
    #|
    #|See [[Other-Page|other]] and [x](./y.md).
  for spec_name in ["github-wiki", "gitlab-wiki"] {
    let registry = get_fixture_registry()
    let spec = registry.get_spec(spec_name).unwrap()
    let lexer = @lexer.Lexer::for_spec(spec)
    let tokens = lexer.tokenize(source)
    assert_true(tokens.iter().any(fn(t) { t.kind == "META_COMMENT" }))
    let result = run_pipeline_with_registry(
      registry, spec_name, source, "Home.md",
    )
    assert_true(result.parse_complete())
    let mut wiki = 0
    let mut md = 0
    for edge in result.edges {
      let via = edge.attrs.get("via").unwrap_or("")
      if via == "Other-Page" {
        wiki += 1
      }
      if via == "./y.md" {
        md += 1
      }
    }
    assert_true(wiki > 0)
    assert_true(md > 0)
  }
}
