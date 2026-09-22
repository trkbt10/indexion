///|
/// Diagram fixtures tests.
/// Validates KGF parsing for diagram description languages (Mermaid, etc.).

///|
test "diagram: tokenize mermaid flowchart" {
  let registry = get_fixture_registry()
  let spec = registry.get_spec("mermaid").unwrap()
  let lexer = @lexer.Lexer::new(spec.get_tokens())
  let fixtures = get_fixtures_dir()
  let src = @fs.read_file_to_string(fixtures + "/diagram/mermaid/flowchart.mmd") catch {
    _ => ""
  }
  if src.length() > 0 {
    let tokens = lexer.tokenize(src)
    assert_true(tokens.length() > 0)
    assert_true(tokens.iter().any(fn(t) { t.kind == "KW_flowchart" }))
    assert_true(tokens.iter().any(fn(t) { t.kind == "KW_subgraph" }))
    assert_true(tokens.iter().any(fn(t) { t.kind == "KW_end" }))
    assert_true(tokens.iter().any(fn(t) { t.kind == "Ident" }))
    assert_true(tokens.iter().any(fn(t) { t.kind == "Arrow" }))
  }
}

///|
test "diagram: tokenize mermaid sequence diagram" {
  let registry = get_fixture_registry()
  let spec = registry.get_spec("mermaid").unwrap()
  let lexer = @lexer.Lexer::new(spec.get_tokens())
  let fixtures = get_fixtures_dir()
  let src = @fs.read_file_to_string(fixtures + "/diagram/mermaid/sequence.mmd") catch {
    _ => ""
  }
  if src.length() > 0 {
    let tokens = lexer.tokenize(src)
    assert_true(tokens.length() > 0)
    assert_true(tokens.iter().any(fn(t) { t.kind == "KW_sequenceDiagram" }))
    assert_true(tokens.iter().any(fn(t) { t.kind == "KW_participant" }))
    assert_true(tokens.iter().any(fn(t) { t.kind == "KW_loop" }))
  }
}

///|
test "diagram: tokenize mermaid class diagram" {
  let registry = get_fixture_registry()
  let spec = registry.get_spec("mermaid").unwrap()
  let lexer = @lexer.Lexer::new(spec.get_tokens())
  let fixtures = get_fixtures_dir()
  let src = @fs.read_file_to_string(fixtures + "/diagram/mermaid/class.mmd") catch {
    _ => ""
  }
  if src.length() > 0 {
    let tokens = lexer.tokenize(src)
    assert_true(tokens.length() > 0)
    assert_true(tokens.iter().any(fn(t) { t.kind == "KW_classDiagram" }))
    assert_true(tokens.iter().any(fn(t) { t.kind == "KW_class" }))
    assert_true(
      tokens.iter().any(fn(t) { t.kind == "Ident" && t.text == "Animal" }),
    )
    assert_true(
      tokens.iter().any(fn(t) { t.kind == "Ident" && t.text == "Duck" }),
    )
  }
}

///|
test "diagram: tokenize mermaid er diagram" {
  let registry = get_fixture_registry()
  let spec = registry.get_spec("mermaid").unwrap()
  let lexer = @lexer.Lexer::new(spec.get_tokens())
  let fixtures = get_fixtures_dir()
  let src = @fs.read_file_to_string(fixtures + "/diagram/mermaid/er.mmd") catch {
    _ => ""
  }
  if src.length() > 0 {
    let tokens = lexer.tokenize(src)
    assert_true(tokens.length() > 0)
    assert_true(tokens.iter().any(fn(t) { t.kind == "KW_erDiagram" }))
    assert_true(
      tokens.iter().any(fn(t) { t.kind == "Ident" && t.text == "CUSTOMER" }),
    )
    assert_true(
      tokens.iter().any(fn(t) { t.kind == "Ident" && t.text == "ORDER" }),
    )
  }
}

///|
test "diagram: tokenize mermaid gantt chart" {
  let registry = get_fixture_registry()
  let spec = registry.get_spec("mermaid").unwrap()
  let lexer = @lexer.Lexer::new(spec.get_tokens())
  let fixtures = get_fixtures_dir()
  let src = @fs.read_file_to_string(fixtures + "/diagram/mermaid/gantt.mmd") catch {
    _ => ""
  }
  if src.length() > 0 {
    let tokens = lexer.tokenize(src)
    assert_true(tokens.length() > 0)
    assert_true(tokens.iter().any(fn(t) { t.kind == "KW_gantt" }))
    assert_true(tokens.iter().any(fn(t) { t.kind == "KW_title" }))
    assert_true(tokens.iter().any(fn(t) { t.kind == "KW_dateFormat" }))
    assert_true(tokens.iter().any(fn(t) { t.kind == "KW_section" }))
  }
}

///|
test "diagram: tokenize mermaid state diagram" {
  let registry = get_fixture_registry()
  let spec = registry.get_spec("mermaid").unwrap()
  let lexer = @lexer.Lexer::new(spec.get_tokens())
  let fixtures = get_fixtures_dir()
  let src = @fs.read_file_to_string(fixtures + "/diagram/mermaid/state.mmd") catch {
    _ => ""
  }
  if src.length() > 0 {
    let tokens = lexer.tokenize(src)
    assert_true(tokens.length() > 0)
    assert_true(tokens.iter().any(fn(t) { t.kind == "KW_stateDiagram" }))
    assert_true(tokens.iter().any(fn(t) { t.kind == "KW_state" }))
    assert_true(
      tokens.iter().any(fn(t) { t.kind == "Ident" && t.text == "Idle" }),
    )
    assert_true(
      tokens.iter().any(fn(t) { t.kind == "Ident" && t.text == "Processing" }),
    )
  }
}

///|
test "diagram: mermaid spec registry lookup by extension" {
  let registry = get_fixture_registry()
  let lang_mmd = registry.detect_from_path("diagram.mmd")
  assert_true(lang_mmd is Some(_))
  assert_eq(lang_mmd.unwrap(), "mermaid")
  let lang_mermaid = registry.detect_from_path("diagram.mermaid")
  assert_true(lang_mermaid is Some(_))
  assert_eq(lang_mermaid.unwrap(), "mermaid")
}

///|
/// Every diagram fixture must parse to its last token. `Line` used to have
/// no catch-all alternative, so a flowchart stopped at its first arrow, an
/// ER diagram at its first cardinality and a class diagram at `<|--`, and
/// every node after that point was invisible.
test "diagram: mermaid parses every fixture to the end" {
  let registry = get_fixture_registry()
  let fixtures = get_fixtures_dir()
  for
    name in ["flowchart", "sequence", "class", "er", "state", "gantt", "broken"] {
    let path = fixtures + "/diagram/mermaid/" + name + ".mmd"
    let source = @fs.read_file_to_string(path) catch { _ => "" }
    assert_true(source.length() > 0)
    let result = run_pipeline_with_registry(
      registry, "mermaid", source, "diagram.mmd",
    )
    assert_true(result.parse_ok)
    assert_eq(result.tokens_consumed, result.tokens_total)
  }
}

///|
/// A flowchart node carries a shape suffix (`A[Start]`, `B{Decision}`) and
/// an edge may carry an inline label (`-->|Yes|`). The node names bound on a
/// nested `Node` rule reached the semantics as that rule's LAST token — the
/// closing bracket — so edges were recorded between nodes called `]`.
test "diagram: mermaid flowchart edges use node names, not brackets" {
  let source =
    #|flowchart TD
    #|    A[Start] --> B{Decision}
    #|    B -->|Yes| C[Process]
    #|    B -->|No| D[End]
  let result = run_pipeline_with_registry(
    get_fixture_registry(),
    "mermaid",
    source,
    "flow.mmd",
  )
  assert_true(result.parse_complete())
  let mut a_to_b = 0
  let mut b_to_c = 0
  let mut b_to_d = 0
  for edge in result.edges {
    let src = edge.attrs.get("src").unwrap_or("")
    let dst = edge.attrs.get("dst").unwrap_or("")
    assert_true(src != "]")
    assert_true(dst != "]")
    // The inline `|Yes|` / `|No|` label is part of the link, not a node.
    assert_true(dst != "Yes")
    assert_true(dst != "No")
    if src == "A" && dst == "B" {
      a_to_b += 1
    }
    if src == "B" && dst == "C" {
      b_to_c += 1
    }
    if src == "B" && dst == "D" {
      b_to_d += 1
    }
  }
  assert_eq(a_to_b, 1)
  assert_eq(b_to_c, 1)
  assert_eq(b_to_d, 1)
}

///|
/// ER relationships use two-character cardinalities around `--` or `..`, and
/// entity names are routinely hyphenated. The cardinality token also matched
/// a lone `|`, `{`, `}` or `o`, which stole the `|` of a flowchart edge
/// label and any node named `o`; the set was missing `}|` and `|{`.
test "diagram: mermaid er relationships keep hyphenated entity names" {
  let source =
    #|erDiagram
    #|    CUSTOMER ||--o{ ORDER : places
    #|    ORDER ||--|{ LINE-ITEM : contains
    #|    CUSTOMER }|..|{ DELIVERY-ADDRESS : uses
  let result = run_pipeline_with_registry(
    get_fixture_registry(),
    "mermaid",
    source,
    "er.mmd",
  )
  assert_true(result.parse_complete())
  let mut order = 0
  let mut line_item = 0
  let mut address = 0
  for edge in result.edges {
    let src = edge.attrs.get("src").unwrap_or("")
    let dst = edge.attrs.get("dst").unwrap_or("")
    if src == "CUSTOMER" && dst == "ORDER" {
      order += 1
    }
    if src == "ORDER" && dst == "LINE-ITEM" {
      line_item += 1
    }
    if src == "CUSTOMER" && dst == "DELIVERY-ADDRESS" {
      address += 1
    }
  }
  assert_eq(order, 1)
  assert_eq(line_item, 1)
  assert_eq(address, 1)
}

///|
/// A class relationship (`<|--`, `*--`, `o--`) lexes as several tokens, and
/// the state-diagram marker `[*]` is an anonymous endpoint: an edge touching
/// it must declare no reference rather than one with an empty id.
test "diagram: mermaid class and state edges" {
  let class_source =
    #|classDiagram
    #|    Animal <|-- Duck
    #|    Animal <|-- Fish
  let class_result = run_pipeline_with_registry(
    get_fixture_registry(),
    "mermaid",
    class_source,
    "class.mmd",
  )
  assert_true(class_result.parse_complete())
  let mut duck = 0
  let mut fish = 0
  for edge in class_result.edges {
    let src = edge.attrs.get("src").unwrap_or("")
    let dst = edge.attrs.get("dst").unwrap_or("")
    if src == "Animal" && dst == "Duck" {
      duck += 1
    }
    if src == "Animal" && dst == "Fish" {
      fish += 1
    }
  }
  assert_eq(duck, 1)
  assert_eq(fish, 1)
  let state_source =
    #|stateDiagram-v2
    #|    [*] --> Idle
    #|    Idle --> Processing : submit
    #|    Processing --> [*]
  let state_result = run_pipeline_with_registry(
    get_fixture_registry(),
    "mermaid",
    state_source,
    "state.mmd",
  )
  assert_true(state_result.parse_complete())
  let mut idle_to_processing = 0
  for edge in state_result.edges {
    let src = edge.attrs.get("src").unwrap_or("")
    let dst = edge.attrs.get("dst").unwrap_or("")
    if edge_kind_is(edge.kind, "references") && edge.attrs.get("src") is Some(_) {
      // Neither endpoint of a recorded reference may be the anonymous marker.
      assert_true(src.length() > 0)
      assert_true(dst.length() > 0)
    }
    if src == "Idle" && dst == "Processing" {
      idle_to_processing += 1
    }
  }
  assert_eq(idle_to_processing, 1)
}

///|
/// A sequence arrow `-->>' lexes as Arrow + GT because the longer
/// SeqArrowDotted is defined after Arrow; the edge rule must still pair the
/// two participants around it.
test "diagram: mermaid sequence messages pair their participants" {
  let source =
    #|sequenceDiagram
    #|    participant Alice
    #|    participant Bob
    #|    Alice->>Bob: Hello
    #|    Bob-->>Alice: Hi there
  let result = run_pipeline_with_registry(
    get_fixture_registry(),
    "mermaid",
    source,
    "seq.mmd",
  )
  assert_true(result.parse_complete())
  let mut alice_decl = 0
  let mut bob_decl = 0
  let mut a_to_b = 0
  let mut b_to_a = 0
  for edge in result.edges {
    if edge_kind_is(edge.kind, "declares") {
      let name = edge.attrs.get("name").unwrap_or("")
      if name == "Alice" {
        alice_decl += 1
      }
      if name == "Bob" {
        bob_decl += 1
      }
    }
    let src = edge.attrs.get("src").unwrap_or("")
    let dst = edge.attrs.get("dst").unwrap_or("")
    if src == "Alice" && dst == "Bob" {
      a_to_b += 1
    }
    if src == "Bob" && dst == "Alice" {
      b_to_a += 1
    }
  }
  assert_eq(alice_decl, 1)
  assert_eq(bob_decl, 1)
  assert_eq(a_to_b, 1)
  assert_eq(b_to_a, 1)
}
