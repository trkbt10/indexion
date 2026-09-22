///|
using @test {assert_eq}

/// Project manifest fixtures tests.
/// Validates KGF parsing for package.json, Cargo.toml, go.mod, moon.mod.json, pyproject.toml, deno.json

///|
fn edge_kind_is(kind : @graph.EdgeKind, expected : String) -> Bool {
  kind.to_string() == expected
}

///|
/// Outcome of running a source file through its spec's lexer, PEG and
/// semantics.
///
/// `parse_ok` only says the start rule produced a result — it is true even
/// when the rule matched a mere prefix of the file and everything after the
/// stopping point was dropped. `tokens_total` / `tokens_consumed` are what
/// distinguish a whole parse from a truncated one, and `lex_errors` counts
/// the characters the lexer could not turn into a token at all. Manifest
/// specs must reach `parse_complete` with `lex_errors == 0`; asserting only
/// `parse_ok` is how a spec that silently dropped two thirds of a real
/// manifest kept passing its tests.
struct PipelineResult {
  edges : Array[@graph.Edge]
  parse_ok : Bool
  tokens_total : Int
  tokens_consumed : Int
  lex_errors : Int
}

///|
/// True when the start rule consumed every token the lexer produced.
fn PipelineResult::parse_complete(self : PipelineResult) -> Bool {
  self.parse_ok && self.tokens_consumed == self.tokens_total
}

///|
/// Run pipeline with pre-loaded registry.
fn run_pipeline_with_registry(
  registry : @registry.KGFRegistry,
  spec_name : String,
  source : String,
  file_path : String,
) -> PipelineResult {
  let empty = {
    edges: [],
    parse_ok: false,
    tokens_total: 0,
    tokens_consumed: 0,
    lex_errors: 0,
  }
  let spec = match registry.get_spec(spec_name) {
    Some(s) => s
    None => return empty
  }
  let lexer = @lexer.Lexer::for_spec(spec)
  let (tokens, lex_diags) = lexer.tokenize_with_diagnostics(source)
  let lex_errors = lex_diags.length()
  let total = tokens.length()
  let peg = @peg.build_peg(spec) catch {
    _ => return { ..empty, tokens_total: total, lex_errors, }
  }
  let start_rule = spec.get_start_rule()
  let parse_result = @peg.run_parse(peg, spec, start_rule, tokens)
  let graph = @graph.CodeGraph::new()
  let _ = graph.get_or_add_module(file_path, file=Some(file_path))
  match parse_result {
    Some(eval_result) => {
      let ctx = @semantics.SemEvalCtx::new(
        spec,
        graph,
        file_path,
        "",
        spec.get_language(),
        fn(_) { false },
      )
      for event in eval_result.get_events() {
        @semantics.eval_rule_semantics(event.0, event.1, ctx)
      }
      {
        edges: graph.get_edges(),
        parse_ok: true,
        tokens_total: total,
        tokens_consumed: eval_result.get_pos(),
        lex_errors,
      }
    }
    None => { ..empty, tokens_total: total, lex_errors, }
  }
}

///|
/// Test all npm/package.json project types.
test "project: npm package.json tests" {
  let registry = get_fixture_registry()
  let fixtures = get_fixtures_dir()

  // Tokenize package.json
  let spec = registry.get_spec("package-json").unwrap()
  let lexer = @lexer.Lexer::for_spec(spec)
  let source = @fs.read_file_to_string(fixtures + "/project/npm/package.json") catch {
    _ => ""
  }
  if source.length() > 0 {
    let tokens = lexer.tokenize(source)
    assert_true(tokens.length() > 0)
    assert_true(tokens.iter().any(fn(t) { t.kind == "KW_name" }))

    // Parse and extract
    let result = run_pipeline_with_registry(
      registry, "package-json", source, "package.json",
    )
    assert_true(result.parse_ok)
    assert_true(
      result.edges.iter().any(fn(e) { edge_kind_is(e.kind, "projectName") }),
    )
    assert_true(
      result.edges.iter().any(fn(e) { edge_kind_is(e.kind, "projectVersion") }),
    )
    let npm_deps = result.edges
      .iter()
      .filter(fn(e) {
        edge_kind_is(e.kind, "dependsOn") && e.to.has_prefix("npm:")
      })
      .collect()
    assert_true(npm_deps.length() >= 3)
  }

  // Monorepo root
  let mono_src = @fs.read_file_to_string(
    fixtures + "/project/npm-monorepo/package.json",
  ) catch {
    _ => ""
  }
  if mono_src.length() > 0 {
    let result = run_pipeline_with_registry(
      registry, "package-json", mono_src, "package.json",
    )
    assert_true(
      result.edges.iter().any(fn(e) { edge_kind_is(e.kind, "projectName") }),
    )
  }

  // Workspace package
  let ws_src = @fs.read_file_to_string(
    fixtures + "/project/npm-monorepo/packages/ui/package.json",
  ) catch {
    _ => ""
  }
  if ws_src.length() > 0 {
    let result = run_pipeline_with_registry(
      registry, "package-json", ws_src, "package.json",
    )
    assert_true(
      result.edges
      .iter()
      .any(fn(e) {
        edge_kind_is(e.kind, "dependsOn") && e.to.contains("@example/core")
      }),
    )
  }

  // Circular (should not hang)
  let circ_src = @fs.read_file_to_string(
    fixtures + "/project/npm-circular/package.json",
  ) catch {
    _ => ""
  }
  if circ_src.length() > 0 {
    let result = run_pipeline_with_registry(
      registry, "package-json", circ_src, "package.json",
    )
    assert_true(result.edges.length() > 0)
  }
}

///|
/// Test Cargo.toml parsing.
test "project: cargo tests" {
  let registry = get_fixture_registry()
  let fixtures = get_fixtures_dir()

  // Tokenize
  let spec = registry.get_spec("cargo-toml").unwrap()
  let lexer = @lexer.Lexer::for_spec(spec)
  let source = @fs.read_file_to_string(fixtures + "/project/cargo/Cargo.toml") catch {
    _ => ""
  }
  if source.length() > 0 {
    let tokens = lexer.tokenize(source)
    // Cargo.toml is lexed as generic TOML: one TableHeader token for every
    // `[table]`, rather than a dedicated token per table name. A token per
    // known table cannot describe `[lib]`, `[[bin]]` or
    // `[target.'cfg(unix)'.dependencies]`, so the header text is what
    // identifies a table, and the semantics classify it.
    assert_true(tokens.iter().any(fn(t) { t.kind == "TableHeader" }))
    assert_true(tokens.iter().any(fn(t) { t.kind == "ArrayTableHeader" }))

    // Parse
    let src = if source.has_suffix("\n") { source } else { source + "\n" }
    let result = run_pipeline_with_registry(
      registry, "cargo-toml", src, "Cargo.toml",
    )
    assert_true(result.parse_ok)
    let name = result.edges
      .iter()
      .find_first(fn(e) { edge_kind_is(e.kind, "projectName") })
    assert_true(name is Some(_))
    let deps = result.edges
      .iter()
      .filter(fn(e) {
        edge_kind_is(e.kind, "dependsOn") && e.to.has_prefix("crate:")
      })
      .collect()
    assert_true(deps.length() >= 3)
  }

  // Workspace
  let ws_src = @fs.read_file_to_string(
    fixtures + "/project/cargo-workspace/Cargo.toml",
  ) catch {
    _ => ""
  }
  if ws_src.length() > 0 {
    let result = run_pipeline_with_registry(
      registry, "cargo-toml", ws_src, "Cargo.toml",
    )
    assert_true(result.edges.length() >= 0)
  }

  // Workspace crate
  let crate_src = @fs.read_file_to_string(
    fixtures + "/project/cargo-workspace/crates/cli/Cargo.toml",
  ) catch {
    _ => ""
  }
  if crate_src.length() > 0 {
    let src = if crate_src.has_suffix("\n") {
      crate_src
    } else {
      crate_src + "\n"
    }
    let result = run_pipeline_with_registry(
      registry, "cargo-toml", src, "Cargo.toml",
    )
    assert_true(result.parse_ok)
  }
}

///|
/// Test go.mod parsing.
test "project: go mod tests" {
  let registry = get_fixture_registry()
  let fixtures = get_fixtures_dir()

  let spec = registry.get_spec("go-mod").unwrap()
  let lexer = @lexer.Lexer::for_spec(spec)
  let source = @fs.read_file_to_string(fixtures + "/project/go/go.mod") catch {
    _ => ""
  }
  if source.length() > 0 {
    let tokens = lexer.tokenize(source)
    assert_true(tokens.iter().any(fn(t) { t.kind == "KW_module" }))

    let src = if source.has_suffix("\n") { source } else { source + "\n" }
    let result = run_pipeline_with_registry(registry, "go-mod", src, "go.mod")
    assert_true(result.parse_ok)
    let name = result.edges
      .iter()
      .find_first(fn(e) { edge_kind_is(e.kind, "projectName") })
    assert_true(name is Some(_))
    let deps = result.edges
      .iter()
      .filter(fn(e) {
        edge_kind_is(e.kind, "dependsOn") && e.to.has_prefix("go:")
      })
      .collect()
    assert_true(deps.length() >= 3)
  }
}

///|
/// Test moon.mod.json parsing.
test "project: moonbit tests" {
  let registry = get_fixture_registry()
  let fixtures = get_fixtures_dir()

  let spec = registry.get_spec("moon-mod").unwrap()
  let lexer = @lexer.Lexer::for_spec(spec)
  let source = @fs.read_file_to_string(
    fixtures + "/project/moonbit/moon.mod.json",
  ) catch {
    _ => ""
  }
  if source.length() > 0 {
    let tokens = lexer.tokenize(source)
    assert_true(tokens.iter().any(fn(t) { t.kind == "KW_name" }))

    let result = run_pipeline_with_registry(
      registry, "moon-mod", source, "moon.mod.json",
    )
    assert_true(result.parse_ok)
    let name = result.edges
      .iter()
      .find_first(fn(e) { edge_kind_is(e.kind, "projectName") })
    assert_true(name is Some(_))
    let deps = result.edges
      .iter()
      .filter(fn(e) {
        edge_kind_is(e.kind, "dependsOn") && e.to.has_prefix("pkg:")
      })
      .collect()
    assert_true(deps.length() >= 2)
  }
}

///|
/// Test moon.mod parsing (current MoonBit TOML manifest format).
test "project: moonbit moon.mod TOML tests" {
  let registry = get_fixture_registry()
  let fixtures = get_fixtures_dir()

  let spec = registry.get_spec("moon-mod-toml").unwrap()
  let lexer = @lexer.Lexer::for_spec(spec)
  let source = @fs.read_file_to_string(
    fixtures + "/project/moonbit-toml/moon.mod",
  ) catch {
    _ => ""
  }
  if source.length() > 0 {
    let tokens = lexer.tokenize(source)
    assert_true(tokens.iter().any(fn(t) { t.kind == "KW_name" }))
    assert_true(tokens.iter().any(fn(t) { t.kind == "KW_import" }))

    let result = run_pipeline_with_registry(
      registry, "moon-mod-toml", source, "moon.mod",
    )
    assert_true(result.parse_ok)

    // name / version strings
    let name = result.edges
      .iter()
      .find_first(fn(e) { edge_kind_is(e.kind, "projectName") })
      .map(fn(e) { e.to })
    assert_eq(name, Some("example/widget"))
    let version = result.edges
      .iter()
      .find_first(fn(e) { edge_kind_is(e.kind, "projectVersion") })
      .map(fn(e) { e.to })
    assert_eq(version, Some("0.3.0"))

    // keywords array spanning multiple lines
    let keywords = result.edges
      .iter()
      .filter(fn(e) { edge_kind_is(e.kind, "projectKeyword") })
      .collect()
    assert_eq(keywords.length(), 3)

    // import { } deps: @version pin stripped, pkg: prefix (matches moon-mod.kgf)
    let deps = result.edges
      .iter()
      .filter(fn(e) {
        edge_kind_is(e.kind, "dependsOn") && e.to.has_prefix("pkg:")
      })
      .collect()
    assert_eq(deps.length(), 3)
    assert_true(deps.iter().any(fn(e) { e.to == "pkg:moonbitlang/x" }))
    assert_true(deps.iter().any(fn(e) { e.to == "pkg:example/core" }))

    // license / repository / description
    assert_true(
      result.edges
      .iter()
      .any(fn(e) {
        edge_kind_is(e.kind, "projectLicense") && e.to == "Apache-2.0"
      }),
    )
    assert_true(
      result.edges
      .iter()
      .any(fn(e) { edge_kind_is(e.kind, "projectRepository") }),
    )
    assert_true(
      result.edges
      .iter()
      .any(fn(e) { edge_kind_is(e.kind, "projectDescription") }),
    )
  }
}

///|
/// Test pyproject.toml parsing.
test "project: python tests" {
  let registry = get_fixture_registry()
  let fixtures = get_fixtures_dir()

  let spec = registry.get_spec("pyproject-toml").unwrap()
  let lexer = @lexer.Lexer::for_spec(spec)
  let source = @fs.read_file_to_string(
    fixtures + "/project/python/pyproject.toml",
  ) catch {
    _ => ""
  }
  if source.length() > 0 {
    let tokens = lexer.tokenize(source)
    // The `[project]` table is an ordinary table header; which table a key
    // belongs to is decided in the semantics, not by a dedicated token.
    assert_true(
      tokens
      .iter()
      .any(fn(t) { t.kind == "TableHeader" && t.text == "[project]" }),
    )

    let src = if source.has_suffix("\n") { source } else { source + "\n" }
    let result = run_pipeline_with_registry(
      registry, "pyproject-toml", src, "pyproject.toml",
    )
    assert_true(result.parse_ok)
    let deps = result.edges
      .iter()
      .filter(fn(e) {
        edge_kind_is(e.kind, "dependsOn") && e.to.has_prefix("pypi:")
      })
      .collect()
    assert_true(deps.length() >= 3)
  }
}

///|
/// Test deno.json parsing.
test "project: deno tests" {
  let registry = get_fixture_registry()
  let fixtures = get_fixtures_dir()

  let spec = registry.get_spec("deno-json").unwrap()
  let lexer = @lexer.Lexer::for_spec(spec)
  let source = @fs.read_file_to_string(fixtures + "/project/deno/deno.json") catch {
    _ => ""
  }
  if source.length() > 0 {
    let tokens = lexer.tokenize(source)
    assert_true(tokens.iter().any(fn(t) { t.kind == "KW_name" }))

    let result = run_pipeline_with_registry(
      registry, "deno-json", source, "deno.json",
    )
    assert_true(result.parse_ok)
    let deps = result.edges
      .iter()
      .filter(fn(e) { edge_kind_is(e.kind, "dependsOn") })
      .collect()
    assert_true(deps.length() >= 3)
  }
}

///|
/// Test other project types (vcpkg, csproj, swift, maven, gradle, ruby, php).
test "project: other languages" {
  let registry = get_fixture_registry()
  let fixtures = get_fixtures_dir()

  // vcpkg (C++)
  let vcpkg_src = @fs.read_file_to_string(
    fixtures + "/project/vcpkg/vcpkg.json",
  ) catch {
    _ => ""
  }
  if vcpkg_src.length() > 0 {
    let result = run_pipeline_with_registry(
      registry, "vcpkg-json", vcpkg_src, "vcpkg.json",
    )
    assert_true(result.parse_ok)
    let deps = result.edges
      .iter()
      .filter(fn(e) {
        edge_kind_is(e.kind, "dependsOn") && e.to.has_prefix("vcpkg:")
      })
      .collect()
    assert_true(deps.length() >= 4)
  }

  // csproj (C#)
  let csproj_src = @fs.read_file_to_string(
    fixtures + "/project/csharp/Example.csproj",
  ) catch {
    _ => ""
  }
  if csproj_src.length() > 0 {
    let result = run_pipeline_with_registry(
      registry, "csproj", csproj_src, "Example.csproj",
    )
    assert_true(result.parse_ok)
    let deps = result.edges
      .iter()
      .filter(fn(e) {
        edge_kind_is(e.kind, "dependsOn") && e.to.has_prefix("nuget:")
      })
      .collect()
    assert_true(deps.length() >= 3)
  }

  // Package.swift
  let swift_src = @fs.read_file_to_string(
    fixtures + "/project/swift/Package.swift",
  ) catch {
    _ => ""
  }
  if swift_src.length() > 0 {
    let result = run_pipeline_with_registry(
      registry, "package-swift", swift_src, "Package.swift",
    )
    assert_true(result.parse_ok)
    let deps = result.edges
      .iter()
      .filter(fn(e) {
        edge_kind_is(e.kind, "dependsOn") && e.to.has_prefix("swift:")
      })
      .collect()
    assert_true(deps.length() >= 3)
  }

  // pom.xml (Maven)
  let pom_src = @fs.read_file_to_string(fixtures + "/project/maven/pom.xml") catch {
    _ => ""
  }
  if pom_src.length() > 0 {
    let result = run_pipeline_with_registry(
      registry, "pom-xml", pom_src, "pom.xml",
    )
    assert_true(result.parse_ok)
    let deps = result.edges
      .iter()
      .filter(fn(e) {
        edge_kind_is(e.kind, "dependsOn") && e.to.has_prefix("maven:")
      })
      .collect()
    assert_true(deps.length() >= 4)
  }

  // build.gradle.kts
  let gradle_src = @fs.read_file_to_string(
    fixtures + "/project/gradle/build.gradle.kts",
  ) catch {
    _ => ""
  }
  if gradle_src.length() > 0 {
    let result = run_pipeline_with_registry(
      registry, "build-gradle-kts", gradle_src, "build.gradle.kts",
    )
    assert_true(result.parse_ok)
    let deps = result.edges
      .iter()
      .filter(fn(e) {
        edge_kind_is(e.kind, "dependsOn") && e.to.has_prefix("maven:")
      })
      .collect()
    assert_true(deps.length() >= 6)
  }

  // Gemfile (Ruby)
  let gem_src = @fs.read_file_to_string(fixtures + "/project/ruby/Gemfile") catch {
    _ => ""
  }
  if gem_src.length() > 0 {
    let result = run_pipeline_with_registry(
      registry, "gemfile", gem_src, "Gemfile",
    )
    assert_true(result.parse_ok)
    let deps = result.edges
      .iter()
      .filter(fn(e) {
        edge_kind_is(e.kind, "dependsOn") && e.to.has_prefix("rubygems:")
      })
      .collect()
    assert_true(deps.length() >= 8)
  }

  // composer.json (PHP)
  let php_src = @fs.read_file_to_string(fixtures + "/project/php/composer.json") catch {
    _ => ""
  }
  if php_src.length() > 0 {
    let result = run_pipeline_with_registry(
      registry, "composer-json", php_src, "composer.json",
    )
    assert_true(result.parse_ok)
    let deps = result.edges
      .iter()
      .filter(fn(e) {
        edge_kind_is(e.kind, "dependsOn") && e.to.has_prefix("packagist:")
      })
      .collect()
    assert_true(deps.length() >= 7)
  }
}

///|
/// Test registry detection functions.
test "project: registry detection" {
  let registry = get_fixture_registry()

  // is_file_supported
  assert_true(registry.is_file_supported("package.json"))
  assert_true(registry.is_file_supported("/path/package.json"))
  assert_true(registry.is_file_supported("Cargo.toml"))
  assert_true(registry.is_file_supported("go.mod"))
  assert_true(registry.is_file_supported("moon.mod.json"))
  assert_true(registry.is_file_supported("moon.mod"))
  assert_true(registry.is_file_supported("pyproject.toml"))
  assert_true(registry.is_file_supported("deno.json"))
  assert_true(registry.is_file_supported("deno.jsonc"))

  // detect_from_path
  let pkg_lang = registry.detect_from_path("package.json")
  assert_true(
    pkg_lang == Some("package-json") || pkg_lang == Some("npm-package-json"),
  )
  assert_eq(registry.detect_from_path("Cargo.toml"), Some("cargo-toml"))
  assert_eq(registry.detect_from_path("go.mod"), Some("go-mod"))
  assert_eq(registry.detect_from_path("moon.mod.json"), Some("moon-mod"))
  // The TOML manifest must not be mis-detected as the JSON one, nor as go.mod
  // (both moon.mod and go.mod share the `.mod` extension — exact filename wins).
  assert_eq(registry.detect_from_path("moon.mod"), Some("moon-mod-toml"))

  // get_external_prefixes
  let prefixes = registry.get_external_prefixes()
  assert_true(prefixes.iter().any(fn(p) { p == "npm:" }))
  assert_true(prefixes.iter().any(fn(p) { p == "crate:" }))
  assert_true(prefixes.iter().any(fn(p) { p == "go:" }))
  assert_true(prefixes.iter().any(fn(p) { p == "pkg:" }))
  assert_true(prefixes.iter().any(fn(p) { p == "pypi:" }))
}

///|
/// Manifest specs must parse real-world files WHOLE.
///
/// Every case below is a construct that a real manifest contains and that the
/// spec used to stop on. A PEG start rule that matches only a prefix reports
/// no error — it simply returns early, and every indexion feature silently
/// loses the rest of the file — so these assertions check the consumed token
/// count and the lexer diagnostic count, not just `parse_ok`.
test "project: manifests parse real-world files completely" {
  let registry = get_fixture_registry()
  let fixtures = get_fixtures_dir()

  // --- Cargo.toml -------------------------------------------------------
  // `[lib]` and `[[bin]]` both contain `name = ...`. While `name` was a
  // KEYWORD token, that line could not match the generic table rule and the
  // parse stopped at the `[lib]` table, dropping it and `[[bin]]`.
  let cargo_src = @fs.read_file_to_string(
    fixtures + "/project/cargo/Cargo.toml",
  ) catch {
    _ => ""
  }
  if cargo_src.length() > 0 {
    let r = run_pipeline_with_registry(
      registry, "cargo-toml", cargo_src, "Cargo.toml",
    )
    assert_true(r.parse_complete())
    assert_eq(r.lex_errors, 0)
    // The crate name comes from [package], never from [lib] / [[bin]].
    let names = r.edges
      .iter()
      .filter(fn(e) { edge_kind_is(e.kind, "projectName") })
      .collect()
    assert_eq(names.length(), 1)
    assert_eq(names[0].to, "example-cli")
    // One dependency per entry, and no entry invented from the keys of an
    // inline table (`{ version = "4.0", features = [...] }`).
    let deps = r.edges
      .iter()
      .filter(fn(e) {
        edge_kind_is(e.kind, "dependsOn") && e.to.has_prefix("crate:")
      })
      .collect()
    assert_eq(deps.length(), 4)
    assert_true(deps.iter().any(fn(e) { e.to == "crate:clap" }))
    assert_true(deps.iter().any(fn(e) { e.to == "crate:pretty_assertions" }))
    assert_false(deps.iter().any(fn(e) { e.to == "crate:version" }))
    assert_false(deps.iter().any(fn(e) { e.to == "crate:features" }))
    // `keywords = [...]` is an array value, not a table header.
    let kws = r.edges
      .iter()
      .filter(fn(e) { edge_kind_is(e.kind, "projectKeyword") })
      .collect()
    assert_eq(kws.length(), 3)
  }

  // A workspace root: `resolver = "2"` followed by a MULTI-LINE `members`
  // array. The array spanning lines is what the old grammar could not do.
  let ws_src = @fs.read_file_to_string(
    fixtures + "/project/cargo-workspace/Cargo.toml",
  ) catch {
    _ => ""
  }
  if ws_src.length() > 0 {
    let r = run_pipeline_with_registry(
      registry, "cargo-toml", ws_src, "Cargo.toml",
    )
    assert_true(r.parse_complete())
    assert_eq(r.lex_errors, 0)
    let deps = r.edges
      .iter()
      .filter(fn(e) { edge_kind_is(e.kind, "dependsOn") })
      .collect()
    assert_eq(deps.length(), 3)
  }

  // A workspace member: `version.workspace = true` — a DOTTED key. The crate
  // name of `tracing.workspace = true` is `tracing`, not `tracing.workspace`.
  let member_src = @fs.read_file_to_string(
    fixtures + "/project/cargo-workspace/crates/cli/Cargo.toml",
  ) catch {
    _ => ""
  }
  if member_src.length() > 0 {
    let r = run_pipeline_with_registry(
      registry, "cargo-toml", member_src, "Cargo.toml",
    )
    assert_true(r.parse_complete())
    assert_eq(r.lex_errors, 0)
    let deps = r.edges
      .iter()
      .filter(fn(e) { edge_kind_is(e.kind, "dependsOn") })
      .collect()
    assert_true(deps.iter().any(fn(e) { e.to == "crate:tracing" }))
    assert_false(deps.iter().any(fn(e) { e.to == "crate:tracing.workspace" }))
  }

  // --- Gemfile ----------------------------------------------------------
  // `gem "rubocop", require: false` — `require` is an ordinary hash key. While
  // it was a KEYWORD token the parse stopped at the second `group` block and
  // the last four gems were lost.
  let gem_src = @fs.read_file_to_string(fixtures + "/project/ruby/Gemfile") catch {
    _ => ""
  }
  if gem_src.length() > 0 {
    let r = run_pipeline_with_registry(registry, "gemfile", gem_src, "Gemfile")
    assert_true(r.parse_complete())
    assert_eq(r.lex_errors, 0)
    let deps = r.edges
      .iter()
      .filter(fn(e) {
        edge_kind_is(e.kind, "dependsOn") && e.to.has_prefix("rubygems:")
      })
      .collect()
    assert_eq(deps.length(), 12)
    assert_true(deps.iter().any(fn(e) { e.to == "rubygems:rubocop" }))
    assert_true(deps.iter().any(fn(e) { e.to == "rubygems:capybara" }))
    assert_true(
      deps.iter().any(fn(e) { e.to == "rubygems:selenium-webdriver" }),
    )
  }

  // --- build.gradle.kts -------------------------------------------------
  // `tasks.withType<Test> { ... }`: the angle brackets had no token at all, so
  // they were unrecognized input AND the statement stopped the parse.
  let gradle_src = @fs.read_file_to_string(
    fixtures + "/project/gradle/build.gradle.kts",
  ) catch {
    _ => ""
  }
  if gradle_src.length() > 0 {
    let r = run_pipeline_with_registry(
      registry, "build-gradle-kts", gradle_src, "build.gradle.kts",
    )
    assert_true(r.parse_complete())
    assert_eq(r.lex_errors, 0)
    let deps = r.edges
      .iter()
      .filter(fn(e) {
        edge_kind_is(e.kind, "dependsOn") && e.to.has_prefix("maven:")
      })
      .collect()
    assert_eq(deps.length(), 6)
    // The configuration name is the dependency kind, so a test-only
    // dependency is distinguishable from a compile one.
    let test_deps = deps
      .iter()
      .filter(fn(e) { e.attrs.get("dep_kind") == Some("testImplementation") })
      .collect()
    assert_eq(test_deps.length(), 2)
    // Plugins are not dependencies of the built artifact: the plugins block
    // declares `id("org.springframework.boot")` and
    // `kotlin("plugin.spring")`, and neither may appear as a dependency.
    assert_false(
      deps.iter().any(fn(e) { e.to == "maven:org.springframework.boot" }),
    )
    assert_false(deps.iter().any(fn(e) { e.to == "maven:plugin.spring" }))
    assert_false(deps.iter().any(fn(e) { e.to == "maven:jvm" }))
  }

  // --- Package.swift ----------------------------------------------------
  // A Package.swift is a Swift program. `let package = Package(` stopped the
  // old grammar on its very first statement, so NOTHING was extracted.
  let swift_src = @fs.read_file_to_string(
    fixtures + "/project/swift/Package.swift",
  ) catch {
    _ => ""
  }
  if swift_src.length() > 0 {
    let r = run_pipeline_with_registry(
      registry, "package-swift", swift_src, "Package.swift",
    )
    assert_true(r.parse_complete())
    assert_eq(r.lex_errors, 0)
    // `name:` names the package only inside `Package(...)`; the `name:` of
    // each .library / .executable / .target must not be mistaken for it.
    let names = r.edges
      .iter()
      .filter(fn(e) { edge_kind_is(e.kind, "projectName") })
      .collect()
    assert_eq(names.length(), 1)
    assert_eq(names[0].to, "MySwiftPackage")
    // `url:` is a dependency only inside `.package(...)`.
    let deps = r.edges
      .iter()
      .filter(fn(e) {
        edge_kind_is(e.kind, "dependsOn") && e.to.has_prefix("swift:")
      })
      .collect()
    assert_eq(deps.length(), 3)
    assert_true(
      deps
      .iter()
      .any(fn(e) {
        e.to == "swift:https://github.com/apple/swift-argument-parser"
      }),
    )
  }

  // --- moon.pkg ---------------------------------------------------------
  // `options( ... )` and `supported_targets = "native"` had no tokens for
  // `(`, `)`, `[`, `]` or `=`, so a real moon.pkg produced lexer errors on
  // every one of those characters.
  let mp_src = @fs.read_file_to_string(
    fixtures + "/project/spec-verify-jsonrpc/moonbit/moon.pkg",
  ) catch {
    _ => ""
  }
  if mp_src.length() > 0 {
    let r = run_pipeline_with_registry(registry, "moonpkg", mp_src, "moon.pkg")
    assert_true(r.parse_complete())
    assert_eq(r.lex_errors, 0)
  }

  // An import block still yields one ModuleDependsOn edge per entry, with the
  // `for "wbtest"` suffix and a trailing settings block both tolerated.
  let mp2_src = @fs.read_file_to_string(
    fixtures + "/project/moonbit/src/moon.pkg",
  ) catch {
    _ => ""
  }
  if mp2_src.length() > 0 {
    let r = run_pipeline_with_registry(registry, "moonpkg", mp2_src, "moon.pkg")
    assert_true(r.parse_complete())
    assert_eq(r.lex_errors, 0)
    let deps = r.edges
      .iter()
      .filter(fn(e) { e.kind is @graph.ModuleDependsOn })
      .collect()
    assert_eq(deps.length(), 2)
  }
}

///|
/// A moon.pkg that uses every construct the real repository uses: two import
/// blocks (one scoped with `for "wbtest"`), a key/value setting and an
/// `options( ... )` call whose value nests a table, a list and strings.
test "project: moon.pkg full construct surface" {
  let registry = get_fixture_registry()
  let source =
    #|import {
    #|  "org/a/zip",
    #|  "org/a/kgf/types" @kgf_types,
    #|}
    #|
    #|import {
    #|  "org/core/test",
    #|} for "wbtest"
    #|
    #|supported_targets = "native"
    #|
    #|options(
    #|  targets: {
    #|    "docx_wbtest.mbt": [ "native" ],
    #|    "pptx_wbtest.mbt": [ "native" ],
    #|  },
    #|)
    #|
  let r = run_pipeline_with_registry(registry, "moonpkg", source, "moon.pkg")
  assert_true(r.parse_complete())
  assert_eq(r.lex_errors, 0)
  let deps = r.edges
    .iter()
    .filter(fn(e) { e.kind is @graph.ModuleDependsOn })
    .collect()
  assert_eq(deps.length(), 3)
  // The alias is preserved verbatim, including its `@`.
  assert_true(
    deps.iter().any(fn(e) { e.attrs.get("alias") == Some("@kgf_types") }),
  )
}

///|
/// `.gitmodules` entry values are reassembled in the grammar, because the
/// lexer cannot decide from context where a value begins. Previously the
/// `key = value` rule never matched at all and every entry line was dropped.
test "project: gitmodules entry values survive lexing" {
  let registry = get_fixture_registry()
  let source =
    #|[submodule "kgfs"]
    #|	path = kgfs
    #|	url = git@github.com:example/example-kgf.git
    #|	pushRecurseSubmodules = on-demand
    #|[submodule "skills"]
    #|	path = skills
    #|	url = https://github.com/example/example-skills.git
    #|
  let r = run_pipeline_with_registry(
    registry, "gitmodules", source, ".gitmodules",
  )
  assert_true(r.parse_complete())
  assert_eq(r.lex_errors, 0)
}

///|
/// A Cargo.toml table header is anchored to the start of a line. Without the
/// anchor a bracketed array VALUE lexes as a table header, which silently
/// turns `keywords = ["a", "b"]` into a new table and loses everything that
/// followed it in the real `[package]` table.
test "project: cargo array value is not a table header" {
  let registry = get_fixture_registry()
  let source =
    #|[package]
    #|name = "demo"
    #|keywords = ["cli", "tool"]
    #|version = "9.9.9"
    #|
    #|[dependencies]
    #|serde = { version = "1", features = ["derive"] }
    #|
  let r = run_pipeline_with_registry(
    registry, "cargo-toml", source, "Cargo.toml",
  )
  assert_true(r.parse_complete())
  assert_eq(r.lex_errors, 0)
  // `version` after the keywords array is still inside [package].
  let versions = r.edges
    .iter()
    .filter(fn(e) { edge_kind_is(e.kind, "projectVersion") })
    .collect()
  assert_eq(versions.length(), 1)
  assert_eq(versions[0].to, "9.9.9")
  let kws = r.edges
    .iter()
    .filter(fn(e) { edge_kind_is(e.kind, "projectKeyword") })
    .collect()
  assert_eq(kws.length(), 2)
  // The inline table's own keys are not dependencies.
  let deps = r.edges
    .iter()
    .filter(fn(e) { edge_kind_is(e.kind, "dependsOn") })
    .collect()
  assert_eq(deps.length(), 1)
  assert_eq(deps[0].to, "crate:serde")
}

///|
/// `pyproject.toml` declares its licence as an SPDX string under PEP 621.
/// The spec used to emit a fixed placeholder for it regardless of what the
/// file said, so a manifest that plainly stated its licence reported a value
/// that appears nowhere in the file.
test "project: pyproject license is the declared value" {
  let registry = get_fixture_registry()
  let source =
    #|[project]
    #|name = "demo"
    #|version = "1.0.0"
    #|license = "BSD-3-Clause"
    #|keywords = ["a", "b"]
    #|authors = [
    #|    { name = "Someone Else", email = "dev@example.com" }
    #|]
    #|dependencies = [
    #|    "httpx>=0.25.0",
    #|    "pydantic>=2.0.0",
    #|]
    #|
    #|[tool.ruff]
    #|line-length = 100
    #|
  let r = run_pipeline_with_registry(
    registry, "pyproject-toml", source, "pyproject.toml",
  )
  assert_true(r.parse_complete())
  assert_eq(r.lex_errors, 0)
  let lic = r.edges
    .iter()
    .filter(fn(e) { edge_kind_is(e.kind, "projectLicense") })
    .collect()
  assert_eq(lic.length(), 1)
  assert_eq(lic[0].to, "BSD-3-Clause")
  // The `name` inside the authors inline table is not the project's name.
  let names = r.edges
    .iter()
    .filter(fn(e) { edge_kind_is(e.kind, "projectName") })
    .collect()
  assert_eq(names.length(), 1)
  assert_eq(names[0].to, "demo")
  // `[tool.ruff] line-length` is a table key, not a dependency or keyword.
  let kws = r.edges
    .iter()
    .filter(fn(e) { edge_kind_is(e.kind, "projectKeyword") })
    .collect()
  assert_eq(kws.length(), 2)
  let deps = r.edges
    .iter()
    .filter(fn(e) { edge_kind_is(e.kind, "dependsOn") })
    .collect()
  assert_eq(deps.length(), 2)
}

///|
/// deno.json is JSONC and `deno.jsonc` is an explicit source of the spec.
/// Comments were lexed but consumed by no grammar rule, so the first comment
/// in a config file stopped the parse and everything after it was dropped.
test "project: deno jsonc comments do not stop the parse" {
  let registry = get_fixture_registry()
  let source =
    #|{
    #|  // the package identity
    #|  "name": "@example/thing",
    #|  "version": "2.0.0", // trailing comment
    #|  /* a block
    #|     comment */
    #|  "imports": {
    #|    "zod": "npm:zod@3.22.0"
    #|  }
    #|}
    #|
  let r = run_pipeline_with_registry(
    registry, "deno-json", source, "deno.jsonc",
  )
  assert_true(r.parse_complete())
  assert_eq(r.lex_errors, 0)
  // Everything after the first comment is still extracted.
  assert_true(
    r.edges
    .iter()
    .any(fn(e) { edge_kind_is(e.kind, "projectVersion") && e.to == "2.0.0" }),
  )
  assert_true(
    r.edges
    .iter()
    .any(fn(e) { edge_kind_is(e.kind, "dependsOn") && e.to == "npm:zod@3.22.0" }),
  )
}

///|
/// The generic TOML spec must consume ordinary values. Its grammar used to
/// treat the right-hand side of `=` as an opaque run of characters, so every
/// array, inline table, number and boolean stopped the parse.
test "project: generic toml consumes every value shape" {
  let registry = get_fixture_registry()
  let source =
    #|# a comment
    #|bare = "string"
    #|num = 42
    #|float = 3.14
    #|yes = true
    #|when = 1979-05-27
    #|arr = [ 1, 2, 3 ]
    #|multi = [
    #|  "a",   # trailing comment
    #|  "b",
    #|]
    #|inline = { x = 1, y = { z = "deep" } }
    #|dotted.key = "value"
    #|
    #|[table]
    #|k = "v"
    #|
    #|[[array.of.tables]]
    #|k = "v"
    #|
  let r = run_pipeline_with_registry(registry, "toml", source, "config.toml")
  assert_true(r.parse_complete())
  assert_eq(r.lex_errors, 0)
}
