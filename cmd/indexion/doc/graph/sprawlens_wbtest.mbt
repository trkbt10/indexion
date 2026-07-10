///|
using @test {assert_eq}

///|
test "sprawlens snapshot: renders file symbols from declares edges" {
  let graph = @core_graph.CodeGraph::new()
  let module_id = "/tmp/indexion-snapshot-test/story.md"
  let content = "# 日本語の見出し\n本文の段落\n"
  ignore(graph.get_or_add_module(module_id, file=Some(module_id)))
  graph.add_edge(
    @core_graph.EdgeKind::from_string("declares"),
    module_id,
    module_id + "::heading@0",
    attrs={ "name": "日本語の見出し", "kind": "Heading" },
  )
  graph.add_edge(
    @core_graph.EdgeKind::from_string("declares"),
    module_id,
    module_id + "::paragraph@12",
    attrs={ "name": "本文の段落", "kind": "Paragraph" },
  )
  graph.add_edge(
    @core_graph.EdgeKind::from_string("nextBlock"),
    module_id + "::heading@0",
    module_id + "::paragraph@12",
  )
  let json_text = render_sprawlens_snapshot(
    graph,
    [(module_id, content)],
    "/tmp/indexion-snapshot-test",
    "Story Snapshot",
  )
  let json = @json.parse(json_text) catch { err => fail(err.to_string()) }
  guard json
    is {
      "schemaVersion": Number(schema, ..),
      "nodes": Array(nodes),
      "edges": Array(edges),
      "metrics": { "fileCount": Number(file_count, ..), .. },
      ..
    } else {
    fail("invalid sprawlens snapshot")
  }
  assert_eq(schema.to_int(), 1)
  assert_eq(file_count.to_int(), 1)
  assert_eq(edges.length() >= 2, true)
  let mut found_file = false
  let mut found_heading = false
  for node in nodes {
    match node {
      {
        "type": String("file"),
        "path": String("story.md"),
        "sizeBytes": Number(size_bytes, ..),
        "symbols": Array(symbols),
        ..
      } => {
        found_file = true
        assert_eq(size_bytes.to_int(), @utf8.encode(content).length())
        for symbol in symbols {
          match symbol {
            {
              "name": String("日本語の見出し"),
              "kind": String("type"),
              "startLine": Number(line, ..),
              ..
            } => found_heading = line.to_int() == 1
            _ => ()
          }
        }
      }
      _ => ()
    }
  }
  assert_eq(found_file, true)
  assert_eq(found_heading, true)
}

///|
test "sprawlens snapshot: source offsets follow KGF UTF-16 positions" {
  let stats = file_stats_from_content("😀\n日本語\n")
  assert_eq(stats.size_bytes, @utf8.encode("😀\n日本語\n").length())
  assert_eq(line_from_id("story.md::paragraph@3", stats), 2)
}
