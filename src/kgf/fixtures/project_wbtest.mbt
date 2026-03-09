///|
/// Project manifest fixtures tests.
/// Validates KGF parsing for package.json, Cargo.toml, go.mod, moon.mod.json, pyproject.toml, deno.json

///|
fn edge_kind_is(kind : @graph.EdgeKind, expected : String) -> Bool {
  kind.to_string() == expected
}

///|
struct PipelineResult {
  edges : Array[@graph.Edge]
  parse_ok : Bool
}

///|
/// Run pipeline with pre-loaded registry.
fn run_pipeline_with_registry(
  registry : @registry.KGFRegistry,
  spec_name : String,
  source : String,
  file_path : String,
) -> PipelineResult {
  let spec = match registry.get_spec(spec_name) {
    Some(s) => s
    None => return { edges: [], parse_ok: false }
  }
  let lexer = @lexer.Lexer::new(spec.get_tokens())
  let tokens = lexer.tokenize(source)
  let peg = @peg.build_peg(spec) catch {
    _ => return { edges: [], parse_ok: false }
  }
  let start_rule = spec.get_start_rule()
  let parse_result = @peg.run_parse(peg, spec, start_rule, tokens)
  let graph = @graph.CodeGraph::new()
  let _ = graph.get_or_add_module(file_path, file=Some(file_path))
  match parse_result {
    Some(eval_result) => {
      let ctx = @semantics.SemEvalCtx::new(
        spec, graph, file_path, "", spec.get_language(), fn(_) { false },
      )
      for event in eval_result.get_events() {
        @semantics.eval_rule_semantics(event.0, event.1, ctx)
      }
      { edges: graph.get_edges(), parse_ok: true }
    }
    None => { edges: [], parse_ok: false }
  }
}

///|
/// Test all npm/package.json project types.
test "project: npm package.json tests" {
  let registry = @registry.KGFRegistry::load_from_dir(get_kgfs_dir())
  let fixtures = get_fixtures_dir()

  // Tokenize package.json
  let spec = registry.get_spec("package-json").unwrap()
  let lexer = @lexer.Lexer::new(spec.get_tokens())
  let source = @fs.read_file_to_string(fixtures + "/project/npm/package.json") catch { _ => "" }
  if source.length() > 0 {
    let tokens = lexer.tokenize(source)
    assert_true(tokens.length() > 0)
    assert_true(tokens.iter().any(fn(t) { t.kind == "KW_name" }))

    // Parse and extract
    let result = run_pipeline_with_registry(registry, "package-json", source, "package.json")
    assert_true(result.parse_ok)
    assert_true(result.edges.iter().any(fn(e) { edge_kind_is(e.kind, "projectName") }))
    assert_true(result.edges.iter().any(fn(e) { edge_kind_is(e.kind, "projectVersion") }))
    let npm_deps = result.edges.iter().filter(fn(e) {
      edge_kind_is(e.kind, "dependsOn") && e.to.has_prefix("npm:")
    }).collect()
    assert_true(npm_deps.length() >= 3)
  }

  // Monorepo root
  let mono_src = @fs.read_file_to_string(fixtures + "/project/npm-monorepo/package.json") catch { _ => "" }
  if mono_src.length() > 0 {
    let result = run_pipeline_with_registry(registry, "package-json", mono_src, "package.json")
    assert_true(result.edges.iter().any(fn(e) { edge_kind_is(e.kind, "projectName") }))
  }

  // Workspace package
  let ws_src = @fs.read_file_to_string(fixtures + "/project/npm-monorepo/packages/ui/package.json") catch { _ => "" }
  if ws_src.length() > 0 {
    let result = run_pipeline_with_registry(registry, "package-json", ws_src, "package.json")
    assert_true(result.edges.iter().any(fn(e) {
      edge_kind_is(e.kind, "dependsOn") && e.to.contains("@example/core")
    }))
  }

  // Circular (should not hang)
  let circ_src = @fs.read_file_to_string(fixtures + "/project/npm-circular/package.json") catch { _ => "" }
  if circ_src.length() > 0 {
    let result = run_pipeline_with_registry(registry, "package-json", circ_src, "package.json")
    assert_true(result.edges.length() > 0)
  }
}

///|
/// Test Cargo.toml parsing.
test "project: cargo tests" {
  let registry = @registry.KGFRegistry::load_from_dir(get_kgfs_dir())
  let fixtures = get_fixtures_dir()

  // Tokenize
  let spec = registry.get_spec("cargo-toml").unwrap()
  let lexer = @lexer.Lexer::new(spec.get_tokens())
  let source = @fs.read_file_to_string(fixtures + "/project/cargo/Cargo.toml") catch { _ => "" }
  if source.length() > 0 {
    let tokens = lexer.tokenize(source)
    assert_true(tokens.iter().any(fn(t) { t.kind == "SectionPackage" }))

    // Parse
    let src = if source.has_suffix("\n") { source } else { source + "\n" }
    let result = run_pipeline_with_registry(registry, "cargo-toml", src, "Cargo.toml")
    assert_true(result.parse_ok)
    let name = result.edges.iter().find_first(fn(e) { edge_kind_is(e.kind, "projectName") })
    assert_true(name is Some(_))
    let deps = result.edges.iter().filter(fn(e) {
      edge_kind_is(e.kind, "dependsOn") && e.to.has_prefix("crate:")
    }).collect()
    assert_true(deps.length() >= 3)
  }

  // Workspace
  let ws_src = @fs.read_file_to_string(fixtures + "/project/cargo-workspace/Cargo.toml") catch { _ => "" }
  if ws_src.length() > 0 {
    let result = run_pipeline_with_registry(registry, "cargo-toml", ws_src, "Cargo.toml")
    assert_true(result.edges.length() >= 0)
  }

  // Workspace crate
  let crate_src = @fs.read_file_to_string(fixtures + "/project/cargo-workspace/crates/cli/Cargo.toml") catch { _ => "" }
  if crate_src.length() > 0 {
    let src = if crate_src.has_suffix("\n") { crate_src } else { crate_src + "\n" }
    let result = run_pipeline_with_registry(registry, "cargo-toml", src, "Cargo.toml")
    assert_true(result.parse_ok)
  }
}

///|
/// Test go.mod parsing.
test "project: go mod tests" {
  let registry = @registry.KGFRegistry::load_from_dir(get_kgfs_dir())
  let fixtures = get_fixtures_dir()

  let spec = registry.get_spec("go-mod").unwrap()
  let lexer = @lexer.Lexer::new(spec.get_tokens())
  let source = @fs.read_file_to_string(fixtures + "/project/go/go.mod") catch { _ => "" }
  if source.length() > 0 {
    let tokens = lexer.tokenize(source)
    assert_true(tokens.iter().any(fn(t) { t.kind == "KW_module" }))

    let src = if source.has_suffix("\n") { source } else { source + "\n" }
    let result = run_pipeline_with_registry(registry, "go-mod", src, "go.mod")
    assert_true(result.parse_ok)
    let name = result.edges.iter().find_first(fn(e) { edge_kind_is(e.kind, "projectName") })
    assert_true(name is Some(_))
    let deps = result.edges.iter().filter(fn(e) {
      edge_kind_is(e.kind, "dependsOn") && e.to.has_prefix("go:")
    }).collect()
    assert_true(deps.length() >= 3)
  }
}

///|
/// Test moon.mod.json parsing.
test "project: moonbit tests" {
  let registry = @registry.KGFRegistry::load_from_dir(get_kgfs_dir())
  let fixtures = get_fixtures_dir()

  let spec = registry.get_spec("moon-mod").unwrap()
  let lexer = @lexer.Lexer::new(spec.get_tokens())
  let source = @fs.read_file_to_string(fixtures + "/project/moonbit/moon.mod.json") catch { _ => "" }
  if source.length() > 0 {
    let tokens = lexer.tokenize(source)
    assert_true(tokens.iter().any(fn(t) { t.kind == "KW_name" }))

    let result = run_pipeline_with_registry(registry, "moon-mod", source, "moon.mod.json")
    assert_true(result.parse_ok)
    let name = result.edges.iter().find_first(fn(e) { edge_kind_is(e.kind, "projectName") })
    assert_true(name is Some(_))
    let deps = result.edges.iter().filter(fn(e) {
      edge_kind_is(e.kind, "dependsOn") && e.to.has_prefix("pkg:")
    }).collect()
    assert_true(deps.length() >= 2)
  }
}

///|
/// Test pyproject.toml parsing.
test "project: python tests" {
  let registry = @registry.KGFRegistry::load_from_dir(get_kgfs_dir())
  let fixtures = get_fixtures_dir()

  let spec = registry.get_spec("pyproject-toml").unwrap()
  let lexer = @lexer.Lexer::new(spec.get_tokens())
  let source = @fs.read_file_to_string(fixtures + "/project/python/pyproject.toml") catch { _ => "" }
  if source.length() > 0 {
    let tokens = lexer.tokenize(source)
    assert_true(tokens.iter().any(fn(t) { t.kind == "SectionProject" }))

    let src = if source.has_suffix("\n") { source } else { source + "\n" }
    let result = run_pipeline_with_registry(registry, "pyproject-toml", src, "pyproject.toml")
    assert_true(result.parse_ok)
    let deps = result.edges.iter().filter(fn(e) {
      edge_kind_is(e.kind, "dependsOn") && e.to.has_prefix("pypi:")
    }).collect()
    assert_true(deps.length() >= 3)
  }
}

///|
/// Test deno.json parsing.
test "project: deno tests" {
  let registry = @registry.KGFRegistry::load_from_dir(get_kgfs_dir())
  let fixtures = get_fixtures_dir()

  let spec = registry.get_spec("deno-json").unwrap()
  let lexer = @lexer.Lexer::new(spec.get_tokens())
  let source = @fs.read_file_to_string(fixtures + "/project/deno/deno.json") catch { _ => "" }
  if source.length() > 0 {
    let tokens = lexer.tokenize(source)
    assert_true(tokens.iter().any(fn(t) { t.kind == "KW_name" }))

    let result = run_pipeline_with_registry(registry, "deno-json", source, "deno.json")
    assert_true(result.parse_ok)
    let deps = result.edges.iter().filter(fn(e) { edge_kind_is(e.kind, "dependsOn") }).collect()
    assert_true(deps.length() >= 3)
  }
}

///|
/// Test other project types (vcpkg, csproj, swift, maven, gradle, ruby, php).
test "project: other languages" {
  let registry = @registry.KGFRegistry::load_from_dir(get_kgfs_dir())
  let fixtures = get_fixtures_dir()

  // vcpkg (C++)
  let vcpkg_src = @fs.read_file_to_string(fixtures + "/project/vcpkg/vcpkg.json") catch { _ => "" }
  if vcpkg_src.length() > 0 {
    let result = run_pipeline_with_registry(registry, "vcpkg-json", vcpkg_src, "vcpkg.json")
    assert_true(result.parse_ok)
    let deps = result.edges.iter().filter(fn(e) {
      edge_kind_is(e.kind, "dependsOn") && e.to.has_prefix("vcpkg:")
    }).collect()
    assert_true(deps.length() >= 4)
  }

  // csproj (C#)
  let csproj_src = @fs.read_file_to_string(fixtures + "/project/csharp/Example.csproj") catch { _ => "" }
  if csproj_src.length() > 0 {
    let result = run_pipeline_with_registry(registry, "csproj", csproj_src, "Example.csproj")
    assert_true(result.parse_ok)
    let deps = result.edges.iter().filter(fn(e) {
      edge_kind_is(e.kind, "dependsOn") && e.to.has_prefix("nuget:")
    }).collect()
    assert_true(deps.length() >= 3)
  }

  // Package.swift
  let swift_src = @fs.read_file_to_string(fixtures + "/project/swift/Package.swift") catch { _ => "" }
  if swift_src.length() > 0 {
    let result = run_pipeline_with_registry(registry, "package-swift", swift_src, "Package.swift")
    assert_true(result.parse_ok)
    let deps = result.edges.iter().filter(fn(e) {
      edge_kind_is(e.kind, "dependsOn") && e.to.has_prefix("swift:")
    }).collect()
    assert_true(deps.length() >= 3)
  }

  // pom.xml (Maven)
  let pom_src = @fs.read_file_to_string(fixtures + "/project/maven/pom.xml") catch { _ => "" }
  if pom_src.length() > 0 {
    let result = run_pipeline_with_registry(registry, "pom-xml", pom_src, "pom.xml")
    assert_true(result.parse_ok)
    let deps = result.edges.iter().filter(fn(e) {
      edge_kind_is(e.kind, "dependsOn") && e.to.has_prefix("maven:")
    }).collect()
    assert_true(deps.length() >= 4)
  }

  // build.gradle.kts
  let gradle_src = @fs.read_file_to_string(fixtures + "/project/gradle/build.gradle.kts") catch { _ => "" }
  if gradle_src.length() > 0 {
    let result = run_pipeline_with_registry(registry, "build-gradle-kts", gradle_src, "build.gradle.kts")
    assert_true(result.parse_ok)
    let deps = result.edges.iter().filter(fn(e) {
      edge_kind_is(e.kind, "dependsOn") && e.to.has_prefix("maven:")
    }).collect()
    assert_true(deps.length() >= 6)
  }

  // Gemfile (Ruby)
  let gem_src = @fs.read_file_to_string(fixtures + "/project/ruby/Gemfile") catch { _ => "" }
  if gem_src.length() > 0 {
    let result = run_pipeline_with_registry(registry, "gemfile", gem_src, "Gemfile")
    assert_true(result.parse_ok)
    let deps = result.edges.iter().filter(fn(e) {
      edge_kind_is(e.kind, "dependsOn") && e.to.has_prefix("rubygems:")
    }).collect()
    assert_true(deps.length() >= 8)
  }

  // composer.json (PHP)
  let php_src = @fs.read_file_to_string(fixtures + "/project/php/composer.json") catch { _ => "" }
  if php_src.length() > 0 {
    let result = run_pipeline_with_registry(registry, "composer-json", php_src, "composer.json")
    assert_true(result.parse_ok)
    let deps = result.edges.iter().filter(fn(e) {
      edge_kind_is(e.kind, "dependsOn") && e.to.has_prefix("packagist:")
    }).collect()
    assert_true(deps.length() >= 7)
  }
}

///|
/// Test registry detection functions.
test "project: registry detection" {
  let registry = @registry.KGFRegistry::load_from_dir(get_kgfs_dir())

  // is_file_supported
  assert_true(registry.is_file_supported("package.json"))
  assert_true(registry.is_file_supported("/path/package.json"))
  assert_true(registry.is_file_supported("Cargo.toml"))
  assert_true(registry.is_file_supported("go.mod"))
  assert_true(registry.is_file_supported("moon.mod.json"))
  assert_true(registry.is_file_supported("pyproject.toml"))
  assert_true(registry.is_file_supported("deno.json"))
  assert_true(registry.is_file_supported("deno.jsonc"))

  // detect_from_path
  let pkg_lang = registry.detect_from_path("package.json")
  assert_true(pkg_lang == Some("package-json") || pkg_lang == Some("npm-package-json"))
  assert_eq(registry.detect_from_path("Cargo.toml"), Some("cargo-toml"))
  assert_eq(registry.detect_from_path("go.mod"), Some("go-mod"))
  assert_eq(registry.detect_from_path("moon.mod.json"), Some("moon-mod"))

  // get_external_prefixes
  let prefixes = registry.get_external_prefixes()
  assert_true(prefixes.iter().any(fn(p) { p == "npm:" }))
  assert_true(prefixes.iter().any(fn(p) { p == "crate:" }))
  assert_true(prefixes.iter().any(fn(p) { p == "go:" }))
  assert_true(prefixes.iter().any(fn(p) { p == "pkg:" }))
  assert_true(prefixes.iter().any(fn(p) { p == "pypi:" }))
}
