// Tests for the post-merge enrichment pass (enrich_graph).

///|
/// Helper: construct a source-language KGFSpec with a sigil-style token so
/// `collect_sigil_token_kinds` picks it up. Modeled on MoonBit's PackageRef.
fn make_source_spec() -> @kgf_types.KGFSpec {
  @kgf_types.KGFSpec::new(
    "moonbit",
    tokens=[@kgf_types.TokenDef::new("PackageRef", "@[a-zA-Z_][a-zA-Z0-9_]*")],
    resolver=@kgf_types.ResolverSpec::new(bare_prefix="pkg:"),
  )
}

///|
/// Helper: a manifest-language spec declaring the "project" role with a
/// specific identity edge kind. Mirrors moon-mod.kgf's features.
fn make_project_manifest_spec(
  identity_edge_kind : String,
  bare_prefix? : String = "pkg:",
) -> @kgf_types.KGFSpec {
  let features : Map[String, Array[String]] = Map([])
  features.set("manifest_role", ["project"])
  features.set("identity_edge", [identity_edge_kind])
  @kgf_types.KGFSpec::new(
    "manifest-project",
    resolver=@kgf_types.ResolverSpec::new(bare_prefix~),
    features=Some(features),
  )
}

///|
/// Helper: a package-level manifest spec that also declares entry_edges.
/// `identity_edge_kind=""` means this manifest does not emit a name edge (the
/// moon.pkg case — package identity comes from its containing project, not
/// from the manifest itself).
fn make_package_manifest_spec(
  identity_edge_kind : String,
  entry_edge_kinds : Array[String],
  bare_prefix? : String = "",
  ancestors? : Array[String] = [],
) -> @kgf_types.KGFSpec {
  let features : Map[String, Array[String]] = Map([])
  features.set("manifest_role", ["package"])
  if identity_edge_kind.length() > 0 {
    features.set("identity_edge", [identity_edge_kind])
  }
  if entry_edge_kinds.length() > 0 {
    features.set("entry_edges", entry_edge_kinds)
  }
  let resolve_chain : Array[@kgf_types.ResolveStep] = []
  if ancestors.length() > 0 {
    resolve_chain.push(@kgf_types.ResolveStep::ancestors(ancestors))
  }
  @kgf_types.KGFSpec::new(
    "manifest-package",
    resolver=@kgf_types.ResolverSpec::new(bare_prefix~, resolve_chain~),
    features=Some(features),
  )
}

///|
test "enrich_graph: MoonBit @alias in source file emits moduleDependsOn via manifest alias" {
  let graph = @graph.CodeGraph::new()
  // Manifest-level edge with explicit alias attribute.
  let _ = graph.get_or_add_module(
    "src/pipeline/moon.pkg",
    file=Some("src/pipeline/moon.pkg"),
  )
  let _ = graph.get_or_add_module(
    "src/pipeline/discover.mbt",
    file=Some("src/pipeline/discover.mbt"),
  )
  let manifest_attrs : Map[String, String] = Map([])
  manifest_attrs.set("via", "trkbt10/indexion/src/filter")
  manifest_attrs.set("dep_kind", "value")
  manifest_attrs.set("alias", "@filter")
  graph.add_edge(
    @graph.EdgeKind::from_string("moduleDependsOn"),
    "src/pipeline/moon.pkg",
    "pkg:trkbt10/indexion/src/filter",
    attrs=manifest_attrs,
  )
  // Source file tokens include a PackageRef (@filter).
  let tokens : Array[@kgf_types.Tok] = [
    @kgf_types.Tok::new("PackageRef", "@filter", 0),
    @kgf_types.Tok::new("DOT", ".", 7),
    @kgf_types.Tok::new("Ident", "FilterConfig", 8),
  ]
  let ft : Array[FileTokens] = [
    FileTokens::new("src/pipeline/discover.mbt", "moonbit", tokens),
  ]
  let specs : Map[String, @kgf_types.KGFSpec] = Map([])
  specs.set("moonbit", make_source_spec())
  enrich_graph(graph, ft, specs)
  // Exactly one new module_depends_on edge should have been added, from the
  // source file to the manifest's resolved target.
  let mut found = false
  for edge in graph.get_edges() {
    if edge.from == "src/pipeline/discover.mbt" &&
      edge.kind is @graph.ModuleDependsOn {
      assert_eq(edge.to, "pkg:trkbt10/indexion/src/filter")
      found = true
    }
  }
  assert_true(found)
}

///|
test "enrich_graph: implicit alias is derived from trailing segment when no alias attr" {
  let graph = @graph.CodeGraph::new()
  let _ = graph.get_or_add_module("pkg/moon.pkg", file=Some("pkg/moon.pkg"))
  let _ = graph.get_or_add_module("pkg/source.mbt", file=Some("pkg/source.mbt"))
  // Manifest edge with no `alias` attr — enrichment must derive `bench` from
  // the trailing segment of the via path.
  let attrs : Map[String, String] = Map([])
  attrs.set("via", "moonbitlang/core/bench")
  attrs.set("dep_kind", "value")
  graph.add_edge(
    @graph.EdgeKind::from_string("moduleDependsOn"),
    "pkg/moon.pkg",
    "pkg:moonbitlang/core/bench",
    attrs~,
  )
  let tokens : Array[@kgf_types.Tok] = [
    @kgf_types.Tok::new("PackageRef", "@bench", 0),
  ]
  let ft : Array[FileTokens] = [
    FileTokens::new("pkg/source.mbt", "moonbit", tokens),
  ]
  let specs : Map[String, @kgf_types.KGFSpec] = Map([])
  specs.set("moonbit", make_source_spec())
  enrich_graph(graph, ft, specs)
  let mut found = false
  for edge in graph.get_edges() {
    if edge.from == "pkg/source.mbt" && edge.kind is @graph.ModuleDependsOn {
      assert_eq(edge.to, "pkg:moonbitlang/core/bench")
      found = true
    }
  }
  assert_true(found)
}

///|
test "enrich_graph: canonicalize rewrites internal pkg target to package manifest id" {
  let graph = @graph.CodeGraph::new()
  // Internal project manifest — emits projectName edge.
  let _ = graph.get_or_add_module("moon.mod.json", file=Some("moon.mod.json"))
  graph.add_edge(
    @graph.EdgeKind::from_string("projectName"),
    "moon.mod.json",
    "trkbt10/indexion",
  )
  // The internal package (target of canonicalization). moon.pkg declares the
  // package's identity via a self-referential packageEntry edge, per
  // moonpkg.kgf's features.
  let _ = graph.get_or_add_module(
    "src/filter/moon.pkg",
    file=Some("src/filter/moon.pkg"),
  )
  graph.add_edge(
    @graph.EdgeKind::from_string("packageEntry"),
    "src/filter/moon.pkg",
    "src/filter/moon.pkg",
  )
  // A source file that (before canonicalization) targets `pkg:<proj>/src/filter`.
  let _ = graph.get_or_add_module("src/caller.mbt", file=Some("src/caller.mbt"))
  let attrs : Map[String, String] = Map([])
  attrs.set("via", "trkbt10/indexion/src/filter")
  graph.add_edge(
    @graph.EdgeKind::from_string("moduleDependsOn"),
    "src/caller.mbt",
    "pkg:trkbt10/indexion/src/filter",
    attrs~,
  )
  let specs : Map[String, @kgf_types.KGFSpec] = Map([])
  specs.set("moonbit", make_source_spec())
  specs.set("moon-mod", make_project_manifest_spec("projectName"))
  specs.set(
    "moon-pkg",
    make_package_manifest_spec("", ["packageEntry"], bare_prefix="pkg:"),
  )
  enrich_graph(graph, [], specs)
  // The pkg: target should have been rewritten to the internal manifest id.
  let mut found_canonical = false
  let mut found_uncanonical = false
  for edge in graph.get_edges() {
    if edge.from == "src/caller.mbt" && edge.kind is @graph.ModuleDependsOn {
      if edge.to == "src/filter/moon.pkg" {
        found_canonical = true
      } else if edge.to == "pkg:trkbt10/indexion/src/filter" {
        found_uncanonical = true
      }
    }
  }
  assert_true(found_canonical)
  assert_false(found_uncanonical)
}

///|
test "enrich_graph: workspace package ancestor-walk target is rewritten to internal entry" {
  // The `node_modules/` directory is not hardcoded — it is advertised by the
  // TS package-json spec as a resolver `ancestors` step. The canonicalization
  // pass walks the target looking for that advertised segment.
  let graph = @graph.CodeGraph::new()
  // Workspace package — declares its identity via packageName + entry via
  // mainEntry.
  let _ = graph.get_or_add_module(
    "packages/api-client/package.json",
    file=Some("packages/api-client/package.json"),
  )
  graph.add_edge(
    @graph.EdgeKind::from_string("packageName"),
    "packages/api-client/package.json",
    "@indexion/api-client",
  )
  graph.add_edge(
    @graph.EdgeKind::from_string("mainEntry"),
    "packages/api-client/package.json",
    "./src/index.ts",
  )
  let _ = graph.get_or_add_module(
    "packages/api-client/src/index.ts",
    file=Some("packages/api-client/src/index.ts"),
  )
  let _ = graph.get_or_add_module(
    "packages/graph-canvas/src/consumer.ts",
    file=Some("packages/graph-canvas/src/consumer.ts"),
  )
  let attrs : Map[String, String] = Map([])
  attrs.set("via", "@indexion/api-client")
  graph.add_edge(
    @graph.EdgeKind::from_string("moduleDependsOn"),
    "packages/graph-canvas/src/consumer.ts",
    "packages/graph-canvas/node_modules/@indexion/api-client/src/index.ts",
    attrs~,
  )
  let specs : Map[String, @kgf_types.KGFSpec] = Map([])
  // TS-ecosystem package manifest: declares node_modules/ as an ancestor walk
  // dir and packageName/mainEntry as identity/entry edges.
  specs.set(
    "package-json",
    make_package_manifest_spec("packageName", ["mainEntry"], ancestors=[
      "node_modules/",
    ]),
  )
  enrich_graph(graph, [], specs)
  let mut found_canonical = false
  for edge in graph.get_edges() {
    if edge.from == "packages/graph-canvas/src/consumer.ts" &&
      edge.to == "packages/api-client/src/index.ts" {
      found_canonical = true
    }
  }
  assert_true(found_canonical)
}

///|
test "enrich_graph: self-loop edges are dropped after canonicalization" {
  let graph = @graph.CodeGraph::new()
  let _ = graph.get_or_add_module("moon.mod.json", file=Some("moon.mod.json"))
  graph.add_edge(
    @graph.EdgeKind::from_string("projectName"),
    "moon.mod.json",
    "proj",
  )
  let _ = graph.get_or_add_module("a/moon.pkg", file=Some("a/moon.pkg"))
  graph.add_edge(
    @graph.EdgeKind::from_string("moduleDependsOn"),
    "a/moon.pkg",
    "pkg:proj/a",
  )
  // Additionally declare the sub-package manifest (moon.pkg style) so the
  // canonicalization pass can discover it. Its role is "package" but it has no
  // identity_edge in this simplified test — discovery happens through the
  // nested-manifest branch of try_match_project.
  let moonpkg_features : Map[String, Array[String]] = Map([])
  moonpkg_features.set("manifest_role", ["package"])
  moonpkg_features.set("entry_edges", ["packageEntry"])
  let moon_pkg_spec : @kgf_types.KGFSpec = @kgf_types.KGFSpec::new(
    "moon-pkg",
    resolver=@kgf_types.ResolverSpec::new(bare_prefix="pkg:"),
    features=Some(moonpkg_features),
  )
  // Emit the self-referential packageEntry edge that moon.pkg would produce.
  graph.add_edge(
    @graph.EdgeKind::from_string("packageEntry"),
    "a/moon.pkg",
    "a/moon.pkg",
  )
  let specs : Map[String, @kgf_types.KGFSpec] = Map([])
  specs.set("moonbit", make_source_spec())
  specs.set("moon-mod", make_project_manifest_spec("projectName"))
  specs.set("moon-pkg", moon_pkg_spec)
  enrich_graph(graph, [], specs)
  // After canonicalization `pkg:proj/a` → `a/moon.pkg`, creating a self-loop
  // (a/moon.pkg → a/moon.pkg). The self-loop must be gone.
  for edge in graph.get_edges() {
    if edge.kind is @graph.ModuleDependsOn {
      assert_false(edge.from == edge.to)
    }
  }
}
