// White-box tests for CAS types.

///|
test "ContentHash::from_string and to_string" {
  let hash = ContentHash::from_string("abcd1234abcd1234abcd1234abcd1234")
  assert_eq!(hash.to_string(), "abcd1234abcd1234abcd1234abcd1234")
}

///|
test "SymbolicRef::new" {
  let ref = SymbolicRef::new("npm:lodash", "moduleDependsOn", "import lodash")
  assert_eq!(ref.ref_str, "npm:lodash")
  assert_eq!(ref.edge_kind, "moduleDependsOn")
  assert_eq!(ref.via, "import lodash")
}

///|
test "ModuleChunk::new" {
  let hash = ContentHash::from_string("abcd1234abcd1234abcd1234abcd1234")
  let source_hash = ContentHash::from_string("1234abcd1234abcd1234abcd1234abcd")
  let spec_hash = ContentHash::from_string("5678efgh5678efgh5678efgh5678efgh")
  let helper = @graph.CodeGraph::new()
  let mod_node = helper.get_or_add_module(
    "src/main.ts",
    file=Some("src/main.ts"),
  )
  let chunk = ModuleChunk::new(hash, "src/main.ts", mod_node, source_hash, spec_hash)
  assert_eq!(chunk.module_id, "src/main.ts")
  assert_eq!(chunk.hash, hash)
  assert_eq!(chunk.source_hash, source_hash)
  assert_eq!(chunk.spec_hash, spec_hash)
  assert_eq!(chunk.symbols.size(), 0)
  assert_eq!(chunk.edges.length(), 0)
  assert_eq!(chunk.external_refs.length(), 0)
}

///|
test "ModuleChunk::add_symbol" {
  let hash = ContentHash::from_string("abcd1234abcd1234abcd1234abcd1234")
  let source_hash = ContentHash::from_string("1234abcd1234abcd1234abcd1234abcd")
  let spec_hash = ContentHash::from_string("5678efgh5678efgh5678efgh5678efgh")
  let helper = @graph.CodeGraph::new()
  let mod_node = helper.get_or_add_module(
    "src/main.ts",
    file=Some("src/main.ts"),
  )
  let chunk = ModuleChunk::new(hash, "src/main.ts", mod_node, source_hash, spec_hash)
  let symbol = helper.get_or_add_symbol(
    "src/main.ts#foo",
    name="foo",
    kind="function",
    ns="main",
    module_id="src/main.ts",
  )
  chunk.add_symbol("src/main.ts#foo", symbol)
  assert_eq!(chunk.symbols.size(), 1)
  assert_true!(chunk.symbols.contains("src/main.ts#foo"))
}

///|
test "ModuleChunk::add_edge" {
  let hash = ContentHash::from_string("abcd1234abcd1234abcd1234abcd1234")
  let source_hash = ContentHash::from_string("1234abcd1234abcd1234abcd1234abcd")
  let spec_hash = ContentHash::from_string("5678efgh5678efgh5678efgh5678efgh")
  let helper = @graph.CodeGraph::new()
  let mod_node = helper.get_or_add_module(
    "src/main.ts",
    file=Some("src/main.ts"),
  )
  let chunk = ModuleChunk::new(hash, "src/main.ts", mod_node, source_hash, spec_hash)
  helper.add_edge(
    @graph.EdgeKind::from_string("declares"),
    "src/main.ts",
    "src/main.ts#foo",
    attrs=Map::new(),
  )
  let edges = helper.get_edges()
  if edges.length() > 0 {
    chunk.add_edge(edges[0])
  }
  assert_eq!(chunk.edges.length(), 1)
}

///|
test "ModuleChunk::add_external_ref" {
  let hash = ContentHash::from_string("abcd1234abcd1234abcd1234abcd1234")
  let source_hash = ContentHash::from_string("1234abcd1234abcd1234abcd1234abcd")
  let spec_hash = ContentHash::from_string("5678efgh5678efgh5678efgh5678efgh")
  let helper = @graph.CodeGraph::new()
  let mod_node = helper.get_or_add_module(
    "src/main.ts",
    file=Some("src/main.ts"),
  )
  let chunk = ModuleChunk::new(hash, "src/main.ts", mod_node, source_hash, spec_hash)
  let ext_ref = SymbolicRef::new(
    "npm:lodash",
    "moduleDependsOn",
    "import _ from 'lodash'",
  )
  chunk.add_external_ref(ext_ref)
  assert_eq!(chunk.external_refs.length(), 1)
  assert_eq!(chunk.external_refs[0].ref_str, "npm:lodash")
}
