///|
/// The shipped specs that adopted `extends:`, and the source patterns that
/// stopped being contested, checked against the real `kgfs/` directory.
///
/// `extends_e2e_wbtest.mbt` proves the inheritance mechanism on scratch
/// specs. This file proves the *adoption*: that the specs which used to be
/// byte-for-byte copies still behave as they did once the copied sections
/// were deleted, and that every pattern those specs claim now has exactly
/// one owner.
///
/// Both halves guard the same failure mode. A derived section replaces the
/// base's whole rather than merging into it, so deleting one section too
/// many silently drops behaviour instead of raising an error; and a spec
/// that claims a pattern it loses analyses nothing while still looking, in
/// `kgf list`, like it might.
///
/// The assertions read the *resolved* spec — what `KGFRegistry` hands every
/// consumer — so they hold whether a section was inherited or written out.

///|
/// The rule bodies of a spec's grammar, keyed by rule name.
fn ext_rule_exprs(spec : @kgf_types.KGFSpec) -> Map[String, String] {
  let out : Map[String, String] = Map([])
  for name, rule in spec.get_rules() {
    out.set(name, rule.get_expr())
  }
  out
}

///|
/// The token definitions of a spec's lexer, as `name=pattern` strings in
/// declaration order. Order matters to a lexer, so this keeps it.
fn ext_token_defs(spec : @kgf_types.KGFSpec) -> Array[String] {
  let out : Array[String] = []
  for tok in spec.get_tokens() {
    out.push(tok.get_name() + "=" + tok.get_pattern())
  }
  out
}

///|
/// True when both specs resolve to the same grammar rules.
fn ext_same_grammar(a : @kgf_types.KGFSpec, b : @kgf_types.KGFSpec) -> Bool {
  let ra = ext_rule_exprs(a)
  let rb = ext_rule_exprs(b)
  if ra.size() != rb.size() {
    return false
  }
  for name, expr in ra {
    if rb.get(name) != Some(expr) {
      return false
    }
  }
  true
}

///|
/// True when two string lists are equal element for element.
fn ext_same_list(x : Array[String], y : Array[String]) -> Bool {
  if x.length() != y.length() {
    return false
  }
  for i in 0..<x.length() {
    if x[i] != y[i] {
      return false
    }
  }
  true
}

///|
/// True when both specs resolve to the same `=== features` block.
fn ext_same_features(a : @kgf_types.KGFSpec, b : @kgf_types.KGFSpec) -> Bool {
  match (a.get_features(), b.get_features()) {
    (None, None) => true
    (Some(fa), Some(fb)) => {
      if fa.size() != fb.size() {
        return false
      }
      for k, va in fa {
        match fb.get(k) {
          Some(vb) => if !ext_same_list(va, vb) { return false }
          None => return false
        }
      }
      true
    }
    _ => false
  }
}

///|
/// True when both specs carry semantics for the same rules, with the same
/// number of `on` blocks each. The blocks themselves are not comparable,
/// but this is enough to catch a section that went missing.
fn ext_same_semantic_rules(
  a : @kgf_types.KGFSpec,
  b : @kgf_types.KGFSpec,
) -> Bool {
  match (a.get_semantics(), b.get_semantics()) {
    (None, None) => true
    (Some(sa), Some(sb)) => {
      if sa.size() != sb.size() {
        return false
      }
      for name, blocks in sa {
        match sb.get(name) {
          Some(other) => if blocks.length() != other.length() { return false }
          None => return false
        }
      }
      true
    }
    _ => false
  }
}

///|
/// True when both specs resolve to the same resolver configuration, apart
/// from `sources:`, which is never inherited.
fn ext_same_resolver_body(
  a : @kgf_types.KGFSpec,
  b : @kgf_types.KGFSpec,
) -> Bool {
  let ra = a.get_resolver()
  let rb = b.get_resolver()
  ext_same_list(ra.get_exts(), rb.get_exts()) &&
  ext_same_list(ra.get_indexes(), rb.get_indexes()) &&
  ext_same_list(ra.get_relative_prefixes(), rb.get_relative_prefixes()) &&
  ra.get_bare_prefix() == rb.get_bare_prefix() &&
  ext_same_list(ext_chain_signature(a), ext_chain_signature(b))
}

///|
/// One string per resolve-chain step (type plus its file list), so two
/// chains compare structurally rather than through the legacy `exts:` keys.
fn ext_chain_signature(spec : @kgf_types.KGFSpec) -> Array[String] {
  spec
  .get_resolver()
  .get_resolve_chain()
  .map(fn(step) {
    step.get_step_type().as_string() +
    ":" +
    step.get_file() +
    ":" +
    step.get_files().join(",")
  })
}

///|
/// The extensions a resolve chain probes (`ext:` steps), for ownership checks.
fn ext_chain_exts(spec : @kgf_types.KGFSpec) -> Array[String] {
  let out : Array[String] = []
  for step in spec.get_resolver().get_resolve_chain() {
    if step.get_step_type().as_string() == "ext" {
      for f in step.get_files() {
        out.push(f)
      }
    }
  }
  out
}

///|
/// TSX is TypeScript with JSX added. Only `=== lex` and `=== grammar` differ;
/// everything else is inherited, so the shared sections must still resolve
/// to TypeScript's, and the JSX-only rules must be present in the derived
/// grammar and absent from the base.
test "extends: typescript-jsx inherits everything but lex and grammar" {
  let registry = get_fixture_registry()
  let tsx = registry.get_spec("typescript-jsx").unwrap()
  let ts = registry.get_spec("typescript").unwrap()
  assert_eq(tsx.get_extends(), Some("typescript"))

  // Inherited wholesale.
  assert_true(ext_same_features(tsx, ts))
  assert_true(ext_same_semantic_rules(tsx, ts))
  assert_true(ext_same_resolver_body(tsx, ts))
  assert_eq(tsx.get_ignore(), ts.get_ignore())
  assert_eq(tsx.get_attrs().size(), ts.get_attrs().size())

  // Declared by the derived spec, and genuinely different.
  assert_true(!ext_same_grammar(tsx, ts))
  assert_true(tsx.get_rule("JsxElement") is Some(_))
  assert_true(ts.get_rule("JsxElement") is None)
  assert_true(ext_token_defs(tsx).length() > ext_token_defs(ts).length())

  // `language:` and `sources:` are never inherited.
  assert_eq(tsx.get_language(), "typescript-jsx")
  assert_true(ext_same_list(tsx.get_resolver().get_sources(), [".tsx"]))
}

///|
/// JSX is JavaScript with JSX added, and with its own resolver: a bare
/// `./Button` in a .jsx file has to reach `Button.jsx`, and `./dir` has to
/// reach `dir/index.jsx`. So three sections are declared, not two.
test "extends: javascript-jsx inherits attrs, features, semantics and ignore" {
  let registry = get_fixture_registry()
  let jsx = registry.get_spec("javascript-jsx").unwrap()
  let js = registry.get_spec("javascript").unwrap()
  assert_eq(jsx.get_extends(), Some("javascript"))
  assert_true(ext_same_features(jsx, js))
  assert_true(ext_same_semantic_rules(jsx, js))
  assert_eq(jsx.get_ignore(), js.get_ignore())
  assert_eq(jsx.get_attrs().size(), js.get_attrs().size())

  // The grammar is the second declared section.
  assert_true(!ext_same_grammar(jsx, js))
  assert_true(jsx.get_rule("JsxElement") is Some(_))
  assert_true(js.get_rule("JsxElement") is None)

  // The resolver is the third: it must name the .jsx extension and index
  // that the base cannot. This is the section it would be easiest to drop
  // by mistake, since JSX and JS agree on everything else in it.
  assert_true(!ext_same_resolver_body(jsx, js))
  assert_true(ext_chain_exts(jsx).contains(".jsx"))
  assert_true(!ext_chain_exts(js).contains(".jsx"))
  assert_true(ext_same_list(jsx.get_resolver().get_sources(), [".jsx"]))
}

///|
/// A GitLab wiki page is a GitHub wiki page with different special-file
/// names. Everything that describes the markup is inherited; only the two
/// sections that carry filenames are declared.
test "extends: gitlab-wiki inherits github-wiki's markup sections" {
  let registry = get_fixture_registry()
  let gl = registry.get_spec("gitlab-wiki").unwrap()
  let gh = registry.get_spec("github-wiki").unwrap()
  assert_eq(gl.get_extends(), Some("github-wiki"))

  // Markup: lex, grammar, attrs, semantics and ignore all inherited.
  assert_true(ext_same_list(ext_token_defs(gl), ext_token_defs(gh)))
  assert_true(ext_same_grammar(gl, gh))
  assert_true(ext_same_semantic_rules(gl, gh))
  assert_eq(gl.get_ignore(), gh.get_ignore())
  assert_eq(gl.get_attrs().size(), gh.get_attrs().size())

  // The two declared sections carry each host's own conventions.
  assert_eq(gl.get_feature("nav_file"), Some(["_sidebar.md"]))
  assert_eq(gh.get_feature("nav_file"), Some(["_Sidebar.md"]))
  assert_eq(gl.get_feature("home_file"), Some(["home.md"]))
  assert_eq(gh.get_feature("home_file"), Some(["Home.md"]))
  assert_true(ext_same_list(gl.get_resolver().get_indexes(), ["/home.md"]))
  assert_true(ext_same_list(gh.get_resolver().get_indexes(), ["/Home.md"]))

  // GitLab has no footer page. A derived section replaces the base's whole,
  // so leaving the key out of gitlab-wiki's `=== features` is what drops it —
  // this asserts the omission really takes effect rather than being merged
  // over from the base.
  assert_eq(gh.get_feature("footer_file"), Some(["_Footer.md"]))
  assert_eq(gl.get_feature("footer_file"), None)
}

///|
/// The SDD specs are Markdown with extra `on DocumentSection` blocks. They
/// declare `=== features` and `=== semantics` and inherit the rest.
///
/// Because a derived `=== semantics` replaces every `on` block of the base,
/// each SDD spec has to repeat Markdown's `on DocumentSection` block itself.
/// If that repetition were ever dropped, SDD documents would silently lose
/// the generic document notes — headings, section refs, literals, tables —
/// while still parsing and still producing their own requirement notes.
test "extends: sdd specs inherit markdown and keep its DocumentSection block" {
  let registry = get_fixture_registry()
  let md = registry.get_spec("markdown").unwrap()
  for name in ["sdd-user-story", "sdd-requirement"] {
    let sdd = registry.get_spec(name).unwrap()
    assert_eq(sdd.get_extends(), Some("markdown"))

    // Inherited wholesale: lex, grammar, attrs, resolver.
    assert_true(ext_same_list(ext_token_defs(sdd), ext_token_defs(md)))
    assert_true(ext_same_grammar(sdd, md))
    assert_eq(sdd.get_attrs().size(), md.get_attrs().size())
    assert_true(ext_same_resolver_body(sdd, md))

    // Markdown's link semantics survive the wholesale override, because the
    // SDD specs repeat every `on` block of the base alongside their own.
    assert_true(sdd.get_semantic("InlineLink") is Some(_))
    assert_true(sdd.get_semantic("InlineImage") is Some(_))
    assert_true(sdd.get_semantic("WikiLink") is Some(_))
    assert_true(sdd.get_semantic("AngleLink") is Some(_))

    // And so does the generic document block: markdown declares exactly one
    // `on DocumentSection`, each SDD spec declares that one plus its own.
    let md_doc = md.get_semantic("DocumentSection").unwrap()
    let sdd_doc = sdd.get_semantic("DocumentSection").unwrap()
    assert_eq(md_doc.length(), 1)
    assert_true(sdd_doc.length() > md_doc.length())

    // Selected by their own commands, never by extension.
    assert_eq(sdd.get_feature("detection_scope"), Some(["overlay"]))
  }
}

///|
/// A markdown link target is bound as a single token in every shape.
///
/// `path:LinkPath` bound the label to a multi-token rule, which yields only
/// that rule's *last* token. For the angle-wrapped form `[x](<p>)` the last
/// token is the closing `>`, so the spec emitted a `url:>` edge instead of
/// the path — the concrete damage behind the multi-token-label warning
/// `kgf check` used to report on this rule.
///
/// The assertions describe the behaviour, not the grammar: what has to hold
/// is that every shape of a target yields the target, and that no shape
/// yields the delimiter.
test "extends: markdown binds an angle-wrapped link target to the path" {
  let source =
    #|[bare](./docs/a.md)
    #|[angled](<./docs/b.md>)
    #|![img](<./img/c.png>)
    #|[angled with title](<./docs/d.md> "T")
  let result = run_pipeline_with_registry(
    get_fixture_registry(),
    "markdown",
    source,
    "doc.md",
  )
  assert_true(result.parse_complete())
  let mut bare = 0
  let mut angled = 0
  let mut image = 0
  let mut titled = 0
  let mut bogus = 0
  for edge in result.edges {
    match edge.attrs.get("via").unwrap_or("") {
      "./docs/a.md" => bare = bare + 1
      "./docs/b.md" => angled = angled + 1
      "./img/c.png" => image = image + 1
      "./docs/d.md" => titled = titled + 1
      ">" => bogus = bogus + 1
      _ => ()
    }
  }
  assert_true(bare > 0)
  assert_true(angled > 0)
  assert_true(image > 0)
  assert_true(titled > 0)
  assert_eq(bogus, 0)
}

///|
/// Every source pattern claimed by the specs this work touched has exactly
/// one owner, so no spec is left claiming a pattern it never sees.
///
/// `.h` is deliberately absent from this list: c/cpp is a separate contest,
/// owned elsewhere.
test "extends: contested source patterns resolved to a single owner" {
  let registry = get_fixture_registry()
  let contested : Map[String, Bool] = Map([])
  for conflict in registry.get_source_conflicts() {
    contested.set(conflict.get_pattern(), true)
  }
  let settled = [
    ".sql", ".txt", ".text", ".b64", ".base64", ".hex", "package.json",
  ]
  for pattern in settled {
    assert_eq(contested.get(pattern), None)
  }

  // And the owner is the spec that actually extracts something. Each of
  // these used to be decided by registration order, and three of the four
  // were decided wrongly: `.sql` could fall to the tokenizer that emits no
  // edges, and `.txt`/`.text` fell to a spec that declares no content_type,
  // so a plain-text file reached the pipeline described as nothing at all.
  assert_eq(registry.detect_from_path("schema.sql"), Some("sql-ddl"))
  assert_eq(registry.detect_from_path("notes.txt"), Some("plaintext"))
  assert_eq(registry.detect_from_path("notes.text"), Some("plaintext"))
  assert_eq(registry.detect_from_path("package.json"), Some("package-json"))

  // The toy extensions have no owner at all now, which is the honest answer
  // for a format an extension cannot identify: `.hex` names both a PNG and a
  // JPEG hex dump, and whichever spec won decoded both. Auto-detection now
  // refuses and the CLI asks for `--spec=`.
  assert_eq(registry.detect_from_path("logo.png.hex"), None)
  assert_eq(registry.detect_from_path("logo.png.b64"), None)
  assert_eq(registry.detect_from_path("blob.base64"), None)
}

///|
/// The specs that gave up a pattern are still reachable by name, and still
/// extract what they always did. Ceding a contest must not mean losing a
/// capability.
test "extends: specs that ceded a pattern stay selectable and useful" {
  let registry = get_fixture_registry()
  let fixtures = get_fixtures_dir()

  // `sql` is a tokenizer with no semantics: it earns its keep through
  // `indexion grep`, so what must survive is its token stream.
  let sql = registry.get_spec("sql").unwrap()
  assert_eq(sql.get_resolver().get_sources().length(), 0)
  let sql_src = @fs.read_file_to_string(fixtures + "/dsl/sql/queries.sql") catch {
    _ => ""
  }
  assert_true(sql_src.length() > 0)
  let sql_tokens = @lexer.Lexer::for_spec(sql).tokenize(sql_src)
  assert_true(sql_tokens.length() > 0)
  assert_true(sql_tokens.iter().any(fn(t) { t.kind == "KeywordDML" }))

  // `universal` segments mixed text far more finely than `plaintext` does.
  // That segmentation is why it exists, and it must still be available.
  let universal = registry.get_spec("universal").unwrap()
  let plaintext = registry.get_spec("plaintext").unwrap()
  let ja = @fs.read_file_to_string(fixtures + "/natural/japanese/quotes.txt") catch {
    _ => ""
  }
  assert_true(ja.length() > 0)
  let u_tokens = @lexer.Lexer::for_spec(universal).tokenize(ja)
  let p_tokens = @lexer.Lexer::for_spec(plaintext).tokenize(ja)
  assert_true(u_tokens.length() > p_tokens.length())

  // `plaintext` won the pattern because it is the one that tells the
  // pipeline what the file *is*; `universal` declares none of that, so a
  // .txt file read under it arrived with no content_type and an empty
  // coverage/vocabulary set.
  assert_eq(plaintext.get_feature("content_type"), Some(["document"]))
  assert_eq(universal.get_feature("content_type"), None)
  assert_eq(universal.get_feature("detection_scope"), Some(["overlay"]))
  assert_eq(universal.get_resolver().get_sources().length(), 0)

  // `npm-package-json` reads the entry points and workspace globs that the
  // owning `package-json` spec does not, and neither spec's extraction is a
  // superset of the other's — which is why they were not merged.
  let npm_src = @fs.read_file_to_string(fixtures + "/project/npm/package.json") catch {
    _ => ""
  }
  assert_true(npm_src.length() > 0)
  let npm_result = run_pipeline_with_registry(
    registry, "npm-package-json", npm_src, "fixtures/project/npm/package.json",
  )
  assert_true(npm_result.parse_complete())
  assert_true(
    npm_result.edges.iter().any(fn(e) { edge_kind_is(e.kind, "mainEntry") }),
  )
  assert_true(
    npm_result.edges.iter().any(fn(e) { edge_kind_is(e.kind, "typesEntry") }),
  )
  let own_result = run_pipeline_with_registry(
    registry, "package-json", npm_src, "fixtures/project/npm/package.json",
  )
  assert_true(
    own_result.edges
    .iter()
    .any(fn(e) { edge_kind_is(e.kind, "projectLicense") }),
  )
  assert_true(
    !own_result.edges.iter().any(fn(e) { edge_kind_is(e.kind, "mainEntry") }),
  )

  // The overlay stays registered, so docgen still reads its manifest
  // features when it builds cluster metadata across every spec.
  let npm_spec = registry.get_spec("npm-package-json").unwrap()
  assert_eq(npm_spec.get_feature("detection_scope"), Some(["overlay"]))
  assert_eq(npm_spec.get_feature("identity_edge"), Some(["packageName"]))
  assert_eq(
    npm_spec.get_feature("entry_edges"),
    Some(["mainEntry", "typesEntry"]),
  )
  assert_eq(npm_spec.get_resolver().get_sources().length(), 0)
}
