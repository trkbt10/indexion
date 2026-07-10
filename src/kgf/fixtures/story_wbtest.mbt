///|
using @test {fail}

///|
test "story-prose: declares headings and paragraphs" {
  let registry = @registry.KGFRegistry::load_from_dir(get_kgfs_dir() + "/story")
  let source =
    #|# Chapter One
    #|
    #|The studio was filled with roses.
    #|
    #|宋金花は十字架を見上げた。
  let result = run_pipeline_with_registry(
    registry, "story-prose", source, "prose/01-chapter.txt",
  )
  assert_true(result.parse_ok)
  let mut heading_count = 0
  let mut paragraph_count = 0
  let mut next_count = 0
  for edge in result.edges {
    if edge_kind_is(edge.kind, "declares") {
      let kind = edge.attrs.get("kind").unwrap_or("")
      let name = edge.attrs.get("name").unwrap_or("")
      if kind == "Heading" && name == "Chapter One" {
        heading_count += 1
      }
      if kind == "Paragraph" && name.contains("studio") {
        paragraph_count += 1
      }
      if kind == "Paragraph" && name.contains("宋金花") {
        paragraph_count += 1
      }
    }
    if edge_kind_is(edge.kind, "nextBlock") {
      next_count += 1
    }
  }
  assert_eq(heading_count, 1)
  assert_eq(paragraph_count, 2)
  assert_eq(next_count, 2)
}

///|
test "story-prose: filtered parser keeps semantic block events" {
  let registry = @registry.KGFRegistry::load_from_dir(get_kgfs_dir() + "/story")
  let spec = registry.get_spec("story-prose").unwrap()
  let source =
    #|# Chapter One
    #|
    #|The studio was filled with roses.
  let lexer = @lexer.Lexer::new(spec.get_tokens())
  let tokens = lexer.tokenize(source)
  let peg_result = Some(@peg.build_peg(spec)) catch { _ => None }
  guard peg_result is Some(peg) else { fail("failed to build story-prose PEG") }
  let active = @peg.collect_active_rules(spec)
  assert_true(active.contains("Heading"))
  assert_true(active.contains("Paragraph"))
  let result = @peg.run_parse_filtered(
    peg,
    spec,
    spec.get_start_rule(),
    tokens,
    active,
  )
  guard result is Some(eval_result) else { fail("filtered parse failed") }
  let events = eval_result.get_events()
  assert_true(events.iter().any(fn(event) { event.0 == "Heading" }))
  assert_true(events.iter().any(fn(event) { event.0 == "Paragraph" }))
}

///|
test "story-prose: filtered parser keeps events on fixture readme" {
  let registry = @registry.KGFRegistry::load_from_dir(get_kgfs_dir() + "/story")
  let spec = registry.get_spec("story-prose").unwrap()
  let path = get_fixtures_dir() + "/story/dorian-gray/README.md"
  let source_result = Some(@fs.read_file_to_string(path)) catch { _ => None }
  guard source_result is Some(source) else {
    fail("failed to read Dorian Gray story fixture")
  }
  let lexer = @lexer.Lexer::new(spec.get_tokens())
  let tokens = lexer.tokenize(source)
  let peg_result = Some(@peg.build_peg(spec)) catch { _ => None }
  guard peg_result is Some(peg) else { fail("failed to build story-prose PEG") }
  let active = @peg.collect_active_rules(spec)
  let result = @peg.run_parse_filtered(
    peg,
    spec,
    spec.get_start_rule(),
    tokens,
    active,
  )
  guard result is Some(eval_result) else { fail("filtered parse failed") }
  let events = eval_result.get_events()
  assert_true(events.iter().any(fn(event) { event.0 == "Heading" }))
  assert_true(events.iter().any(fn(event) { event.0 == "Paragraph" }))
}
