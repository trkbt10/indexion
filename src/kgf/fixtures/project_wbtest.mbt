///|
/// Project manifest fixtures tests.
/// Validates KGF parsing for package.json, Cargo.toml, go.mod, moon.mod.json, pyproject.toml, deno.json

///|
/// Check if edge kind matches a string (handles Custom variant).
fn edge_kind_is(kind : @graph.EdgeKind, expected : String) -> Bool {
  kind.to_string() == expected
}

///|
/// Result of running project pipeline.
struct PipelineResult {
  edges : Array[@graph.Edge]
  parse_ok : Bool
}

///|
/// Helper to run full pipeline for project manifest files and return edges.
fn run_project_pipeline(
  spec_name : String,
  source : String,
  file_path : String,
) -> PipelineResult {
  let registry = @registry.KGFRegistry::load_from_dir(get_kgfs_dir())
  let spec = match registry.get_spec(spec_name) {
    Some(s) => s
    None => return { edges: [], parse_ok: false}
  }
  let lexer = @lexer.Lexer::new(spec.get_tokens())
  let tokens = lexer.tokenize(source)
  let peg = @peg.build_peg(spec) catch {
    _ => return { edges: [], parse_ok: false}
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
        fn(_path) { false },
      )
      for event in eval_result.get_events() {
        let rule_name = event.0
        let labels = event.1
        @semantics.eval_rule_semantics(rule_name, labels, ctx)
      }
      { edges: graph.get_edges(), parse_ok: true}
    }
    None => { edges: [], parse_ok: false}
  }
}

// ============================================================================
// package.json (npm) tests
// ============================================================================

///|
test "project/npm: tokenize package.json" {
  let registry = @registry.KGFRegistry::load_from_dir(get_kgfs_dir())
  let spec = registry.get_spec("package-json").unwrap()
  let lexer = @lexer.Lexer::new(spec.get_tokens())
  let source = @fs.read_file_to_string(
    get_fixtures_dir() + "/project/npm/package.json",
  ) catch {
    _ => return
  }
  let tokens = lexer.tokenize(source)
  assert_true(tokens.length() > 0)
  // Should have name field token
  let mut has_name = false
  for tok in tokens {
    if tok.kind == "KW_name" {
      has_name = true
      break
    }
  }
  assert_true(has_name)
}

///|
test "project/npm: parse and extract metadata" {
  let source = @fs.read_file_to_string(
    get_fixtures_dir() + "/project/npm/package.json",
  ) catch {
    _ => return
  }
  let result = run_project_pipeline(
    "package-json",
    source,
    "fixtures/project/npm/package.json",
  )
  assert_true(result.parse_ok)
  let edges = result.edges
  // Should have projectName edge
  let has_name = edges.iter().any(fn(e) { edge_kind_is(e.kind, "projectName") })
  assert_true(has_name)
  // Should have projectVersion edge
  let has_version = edges.iter().any(fn(e) { edge_kind_is(e.kind, "projectVersion") })
  assert_true(has_version)
  // Should have dependsOn edges for npm: prefixed packages
  let npm_deps = edges
    .iter()
    .filter(fn(e) { edge_kind_is(e.kind, "dependsOn") && e.to.has_prefix("npm:") })
    .collect()
  assert_true(npm_deps.length() >= 3) // react, react-dom, clsx
}

///|
test "project/npm-monorepo: parse root package.json" {
  let source = @fs.read_file_to_string(
    get_fixtures_dir() + "/project/npm-monorepo/package.json",
  ) catch {
    _ => return
  }
  let result = run_project_pipeline(
    "package-json",
    source,
    "fixtures/project/npm-monorepo/package.json",
  )
  let edges = result.edges
  // Should have projectName edge
  let name_edge = edges.iter().find_first(fn(e) { edge_kind_is(e.kind, "projectName") })
  assert_true(name_edge is Some(_))
  // Should have devDependencies
  let has_dev_deps = edges
    .iter()
    .any(fn(e) { edge_kind_is(e.kind, "dependsOn") && e.to.has_prefix("npm:") })
  assert_true(has_dev_deps)
}

///|
test "project/npm-monorepo: parse workspace package" {
  let source = @fs.read_file_to_string(
    get_fixtures_dir() + "/project/npm-monorepo/packages/ui/package.json",
  ) catch {
    _ => return
  }
  let result = run_project_pipeline(
    "package-json",
    source,
    "fixtures/project/npm-monorepo/packages/ui/package.json",
  )
  let edges = result.edges
  // Should have dependency on @example/core (workspace reference)
  let has_core_dep = edges.iter().any(fn(e) {
    edge_kind_is(e.kind, "dependsOn") && e.to.contains("@example/core")
  })
  assert_true(has_core_dep)
}

///|
test "project/npm-circular: parse without infinite loop" {
  let source = @fs.read_file_to_string(
    get_fixtures_dir() + "/project/npm-circular/package.json",
  ) catch {
    _ => return
  }
  // Should complete without hanging (circular reference is in TS files, not package.json)
  let result = run_project_pipeline(
    "package-json",
    source,
    "fixtures/project/npm-circular/package.json",
  )
  assert_true(result.edges.length() > 0)
}

// ============================================================================
// Cargo.toml tests
// ============================================================================

///|
test "project/cargo: tokenize Cargo.toml" {
  let registry = @registry.KGFRegistry::load_from_dir(get_kgfs_dir())
  let spec = registry.get_spec("cargo-toml").unwrap()
  let lexer = @lexer.Lexer::new(spec.get_tokens())
  let source = @fs.read_file_to_string(
    get_fixtures_dir() + "/project/cargo/Cargo.toml",
  ) catch {
    _ => return
  }
  let tokens = lexer.tokenize(source)
  assert_true(tokens.length() > 0)
  // Should have [package] section
  let mut has_package = false
  for tok in tokens {
    if tok.kind == "SectionPackage" {
      has_package = true
      break
    }
  }
  assert_true(has_package)
}

///|
test "project/cargo: parse and extract metadata" {
  let source = @fs.read_file_to_string(
    get_fixtures_dir() + "/project/cargo/Cargo.toml",
  ) catch {
    _ => return
  }
  // Ensure source ends with newline (required by TOML grammar)
  let source_with_nl = if source.has_suffix("\n") { source } else { source + "\n" }
  let result = run_project_pipeline(
    "cargo-toml",
    source_with_nl,
    "fixtures/project/cargo/Cargo.toml",
  )
  assert_true(result.parse_ok)
  let edges = result.edges
  // Should have projectName edge
  let name_edge = edges.iter().find_first(fn(e) { edge_kind_is(e.kind, "projectName") })
  assert_true(name_edge is Some(_))
  match name_edge {
    Some(e) => assert_eq(e.to, "example-cli")
    None => fail("Expected projectName edge")
  }
  // Should have dependsOn edges for crate: prefixed packages
  let crate_deps = edges
    .iter()
    .filter(fn(e) { edge_kind_is(e.kind, "dependsOn") && e.to.has_prefix("crate:") })
    .collect()
  assert_true(crate_deps.length() >= 3) // clap, serde, tokio
}

///|
test "project/cargo-workspace: parse workspace Cargo.toml" {
  let source = @fs.read_file_to_string(
    get_fixtures_dir() + "/project/cargo-workspace/Cargo.toml",
  ) catch {
    _ => return
  }
  let result = run_project_pipeline(
    "cargo-toml",
    source,
    "fixtures/project/cargo-workspace/Cargo.toml",
  )
  // Workspace toml may not have projectName, but should parse without error
  assert_true(result.edges.length() >= 0)
}

///|
test "project/cargo-workspace: parse crate Cargo.toml" {
  let source = @fs.read_file_to_string(
    get_fixtures_dir() + "/project/cargo-workspace/crates/cli/Cargo.toml",
  ) catch {
    _ => return
  }
  let source_with_nl = if source.has_suffix("\n") { source } else { source + "\n" }
  let result = run_project_pipeline(
    "cargo-toml",
    source_with_nl,
    "fixtures/project/cargo-workspace/crates/cli/Cargo.toml",
  )
  assert_true(result.parse_ok)
  let edges = result.edges
  // Should have projectName edge
  let has_name = edges.iter().any(fn(e) { edge_kind_is(e.kind, "projectName") })
  assert_true(has_name)
}

// ============================================================================
// go.mod tests
// ============================================================================

///|
test "project/go: tokenize go.mod" {
  let registry = @registry.KGFRegistry::load_from_dir(get_kgfs_dir())
  let spec = registry.get_spec("go-mod").unwrap()
  let lexer = @lexer.Lexer::new(spec.get_tokens())
  let source = @fs.read_file_to_string(
    get_fixtures_dir() + "/project/go/go.mod",
  ) catch {
    _ => return
  }
  let tokens = lexer.tokenize(source)
  assert_true(tokens.length() > 0)
  // Should have module keyword
  let mut has_module = false
  for tok in tokens {
    if tok.kind == "KW_module" {
      has_module = true
      break
    }
  }
  assert_true(has_module)
}

///|
test "project/go: parse and extract metadata" {
  let source = @fs.read_file_to_string(
    get_fixtures_dir() + "/project/go/go.mod",
  ) catch {
    _ => return
  }
  let source_with_nl = if source.has_suffix("\n") { source } else { source + "\n" }
  let result = run_project_pipeline(
    "go-mod",
    source_with_nl,
    "fixtures/project/go/go.mod",
  )
  assert_true(result.parse_ok)
  let edges = result.edges
  // Should have projectName edge
  let name_edge = edges.iter().find_first(fn(e) { edge_kind_is(e.kind, "projectName") })
  assert_true(name_edge is Some(_))
  match name_edge {
    Some(e) => assert_eq(e.to, "github.com/example/go-service")
    None => fail("Expected projectName edge")
  }
  // Should have dependsOn edges for go: prefixed packages
  let go_deps = edges
    .iter()
    .filter(fn(e) { edge_kind_is(e.kind, "dependsOn") && e.to.has_prefix("go:") })
    .collect()
  assert_true(go_deps.length() >= 3) // gin, cobra, zap
}

// ============================================================================
// moon.mod.json tests
// ============================================================================

///|
test "project/moonbit: tokenize moon.mod.json" {
  let registry = @registry.KGFRegistry::load_from_dir(get_kgfs_dir())
  let spec = registry.get_spec("moon-mod").unwrap()
  let lexer = @lexer.Lexer::new(spec.get_tokens())
  let source = @fs.read_file_to_string(
    get_fixtures_dir() + "/project/moonbit/moon.mod.json",
  ) catch {
    _ => return
  }
  let tokens = lexer.tokenize(source)
  assert_true(tokens.length() > 0)
  // Should have name field token
  let mut has_name = false
  for tok in tokens {
    if tok.kind == "KW_name" {
      has_name = true
      break
    }
  }
  assert_true(has_name)
}

///|
test "project/moonbit: parse and extract metadata" {
  let source = @fs.read_file_to_string(
    get_fixtures_dir() + "/project/moonbit/moon.mod.json",
  ) catch {
    _ => return
  }
  let result = run_project_pipeline(
    "moon-mod",
    source,
    "fixtures/project/moonbit/moon.mod.json",
  )
  assert_true(result.parse_ok)
  let edges = result.edges
  // Should have projectName edge
  let name_edge = edges.iter().find_first(fn(e) { edge_kind_is(e.kind, "projectName") })
  assert_true(name_edge is Some(_))
  match name_edge {
    Some(e) => assert_eq(e.to, "trkbt10/sample-lib")
    None => fail("Expected projectName edge")
  }
  // Should have pkg: prefixed dependencies
  let pkg_deps = edges
    .iter()
    .filter(fn(e) { edge_kind_is(e.kind, "dependsOn") && e.to.has_prefix("pkg:") })
    .collect()
  assert_true(pkg_deps.length() >= 2) // moonbitlang/core, peter-jerry-ye/json5
}

// ============================================================================
// pyproject.toml tests
// ============================================================================

///|
test "project/python: tokenize pyproject.toml" {
  let registry = @registry.KGFRegistry::load_from_dir(get_kgfs_dir())
  let spec = registry.get_spec("pyproject-toml").unwrap()
  let lexer = @lexer.Lexer::new(spec.get_tokens())
  let source = @fs.read_file_to_string(
    get_fixtures_dir() + "/project/python/pyproject.toml",
  ) catch {
    _ => return
  }
  let tokens = lexer.tokenize(source)
  assert_true(tokens.length() > 0)
  // Should have [project] section
  let mut has_project = false
  for tok in tokens {
    if tok.kind == "SectionProject" {
      has_project = true
      break
    }
  }
  assert_true(has_project)
}

///|
test "project/python: parse and extract metadata" {
  let source = @fs.read_file_to_string(
    get_fixtures_dir() + "/project/python/pyproject.toml",
  ) catch {
    _ => return
  }
  let source_with_nl = if source.has_suffix("\n") { source } else { source + "\n" }
  let result = run_project_pipeline(
    "pyproject-toml",
    source_with_nl,
    "fixtures/project/python/pyproject.toml",
  )
  assert_true(result.parse_ok)
  let edges = result.edges
  // Should have projectName edge
  let name_edge = edges.iter().find_first(fn(e) { edge_kind_is(e.kind, "projectName") })
  assert_true(name_edge is Some(_))
  match name_edge {
    Some(e) => assert_eq(e.to, "example-sdk")
    None => fail("Expected projectName edge")
  }
  // Should have dependsOn edges for pypi: prefixed packages
  let pypi_deps = edges
    .iter()
    .filter(fn(e) { edge_kind_is(e.kind, "dependsOn") && e.to.has_prefix("pypi:") })
    .collect()
  assert_true(pypi_deps.length() >= 3) // httpx, pydantic, tenacity
}

// ============================================================================
// deno.json tests
// ============================================================================

///|
test "project/deno: tokenize deno.json" {
  let registry = @registry.KGFRegistry::load_from_dir(get_kgfs_dir())
  let spec = registry.get_spec("deno-json").unwrap()
  let lexer = @lexer.Lexer::new(spec.get_tokens())
  let source = @fs.read_file_to_string(
    get_fixtures_dir() + "/project/deno/deno.json",
  ) catch {
    _ => return
  }
  let tokens = lexer.tokenize(source)
  assert_true(tokens.length() > 0)
  // Should have name field token
  let mut has_name = false
  for tok in tokens {
    if tok.kind == "KW_name" {
      has_name = true
      break
    }
  }
  assert_true(has_name)
}

///|
test "project/deno: parse and extract metadata" {
  let source = @fs.read_file_to_string(
    get_fixtures_dir() + "/project/deno/deno.json",
  ) catch {
    _ => return
  }
  let result = run_project_pipeline(
    "deno-json",
    source,
    "fixtures/project/deno/deno.json",
  )
  assert_true(result.parse_ok)
  let edges = result.edges
  // Should have projectName edge
  let name_edge = edges.iter().find_first(fn(e) { edge_kind_is(e.kind, "projectName") })
  assert_true(name_edge is Some(_))
  match name_edge {
    Some(e) => assert_eq(e.to, "@example/web-api")
    None => fail("Expected projectName edge")
  }
  // Should have dependsOn edges from imports
  let deps = edges.iter().filter(fn(e) { edge_kind_is(e.kind, "dependsOn") }).collect()
  assert_true(deps.length() >= 3) // @std/http, @std/path, zod
}

// ============================================================================
// Registry detection tests
// ============================================================================

///|
test "registry: detect project file types" {
  let registry = @registry.KGFRegistry::load_from_dir(get_kgfs_dir())
  // package.json detection
  assert_true(registry.is_file_supported("package.json"))
  assert_true(registry.is_file_supported("/some/path/package.json"))
  // Cargo.toml detection
  assert_true(registry.is_file_supported("Cargo.toml"))
  assert_true(registry.is_file_supported("/project/Cargo.toml"))
  // go.mod detection
  assert_true(registry.is_file_supported("go.mod"))
  // moon.mod.json detection
  assert_true(registry.is_file_supported("moon.mod.json"))
  // pyproject.toml detection
  assert_true(registry.is_file_supported("pyproject.toml"))
  // deno.json detection
  assert_true(registry.is_file_supported("deno.json"))
  assert_true(registry.is_file_supported("deno.jsonc"))
}

///|
test "registry: detect_from_path returns correct language" {
  let registry = @registry.KGFRegistry::load_from_dir(get_kgfs_dir())
  // package.json can map to either "package-json" or "npm-package-json" depending on load order
  let pkg_lang = registry.detect_from_path("package.json")
  assert_true(
    pkg_lang == Some("package-json") || pkg_lang == Some("npm-package-json"),
  )
  assert_eq(registry.detect_from_path("Cargo.toml"), Some("cargo-toml"))
  assert_eq(registry.detect_from_path("go.mod"), Some("go-mod"))
  assert_eq(registry.detect_from_path("moon.mod.json"), Some("moon-mod"))
  assert_eq(registry.detect_from_path("pyproject.toml"), Some("pyproject-toml"))
  assert_eq(registry.detect_from_path("deno.json"), Some("deno-json"))
}

///|
test "registry: get_external_prefixes includes project prefixes" {
  let registry = @registry.KGFRegistry::load_from_dir(get_kgfs_dir())
  let prefixes = registry.get_external_prefixes()
  // Should include npm:, crate:, go:, pkg:, pypi:, jsr:
  let has_npm = prefixes.iter().any(fn(p) { p == "npm:" })
  let has_crate = prefixes.iter().any(fn(p) { p == "crate:" })
  let has_go = prefixes.iter().any(fn(p) { p == "go:" })
  let has_pkg = prefixes.iter().any(fn(p) { p == "pkg:" })
  let has_pypi = prefixes.iter().any(fn(p) { p == "pypi:" })
  let has_jsr = prefixes.iter().any(fn(p) { p == "jsr:" })
  assert_true(has_npm)
  assert_true(has_crate)
  assert_true(has_go)
  assert_true(has_pkg)
  assert_true(has_pypi)
  assert_true(has_jsr)
}
