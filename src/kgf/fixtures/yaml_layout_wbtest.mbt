///|
/// YAML indentation-layout regression tests.
///
/// YAML's nesting is expressed by indentation, which a regex-only lexer
/// cannot read: it can recognise "a line break and some spaces" but not
/// whether those spaces are deeper than the previous line's. Before the
/// `LAYOUT` directive the spec modelled nesting by line heuristics, so every
/// key in a file was a sibling of every other: `on.push.branches` and
/// `jobs.build.steps` were indistinguishable from two top-level keys.
///
/// With `LAYOUT newline=NL_INDENT,NL indent=INDENT dedent=DEDENT ...` the
/// engine's post-lex pass brackets each level with synthetic INDENT/DEDENT
/// tokens and the grammar consumes them exactly, so each key's `declares`
/// edge carries its full dotted path. These tests pin that path — the whole
/// list, in order — because a nesting bug does not lose a key, it moves it:
/// asserting only that `steps` exists would pass just as happily when it is
/// reported under the wrong parent.

///|
/// The `path` attribute of every `declares` edge the spec emits for a YAML
/// source, in emission order.
///
/// The path is what makes `indexion search` / `grep` over YAML structural, so
/// it is the value these tests assert on rather than the bare key name: two
/// different keys in a workflow are routinely both called `name`, and only
/// the path tells them apart.
fn yml_paths_of(run : PipelineResult) -> Array[String] {
  let result : Array[String] = []
  for edge in run.edges {
    if !(edge.kind is @graph.Declares) {
      continue
    }
    result.push(edge.attrs.get("path").unwrap_or(""))
  }
  result
}

///|
/// Assert that a YAML source is consumed whole AND yields exactly the given
/// key paths.
///
/// Both halves matter and neither implies the other. A parse that stops at
/// the first construct the grammar does not model silently drops everything
/// after it, so `parse_complete` guards against a spec that looks correct
/// only because two thirds of the file were never read; the path list guards
/// against a file that is fully consumed but whose structure is flattened.
fn yml_assert_paths(
  source : String,
  path : String,
  expected : Array[String],
) -> Unit raise {
  let run = run_pipeline_with_registry(
    get_fixture_registry(),
    "yaml",
    source,
    path,
  )
  assert_eq(run.lex_errors, 0)
  assert_true(run.parse_complete())
  assert_eq(yml_paths_of(run), expected)
}

///|
/// Three levels of block mapping. Each key's value block must be bracketed by
/// its own INDENT/DEDENT, so `d` — back at column 0 after two levels closed —
/// is a sibling of `a`, not a third child of `a.b`.
test "yaml layout: block mappings nest three levels and dedent exactly" {
  let source =
    #|a:
    #|  b:
    #|    c: 1
    #|d: 2
  yml_assert_paths(source, "nested.yml", ["a", "a.b", "a.b.c", "d"])
}

///|
/// A sequence of mappings. In YAML's compact notation the `- ` itself counts
/// as indentation, so the pairs that follow the first one on an entry's own
/// lines arrive INSIDE an INDENT/DEDENT pair even though they are the head
/// mapping's SIBLINGS. `uses` must therefore come out as `steps.uses`, not as
/// `steps.name.uses`: the entry, not the head key, owns that block.
test "yaml layout: sequence entries hold sibling keys, not nested ones" {
  let source =
    #|steps:
    #|  - name: A
    #|    uses: B
    #|  - name: C
    #|    uses: D
  yml_assert_paths(source, "seq.yml", [
    "steps", "steps.name", "steps.uses", "steps.name", "steps.uses",
  ])
}

///|
/// A key inside a sequence entry whose value IS an indented block. Its
/// children belong to it (`steps.with.submodules`), while the pair after the
/// block is back at the entry's level (`steps.uses`) and the key after the
/// whole sequence is back at the top (`top`).
test "yaml layout: a block under a sequence entry key nests under that key" {
  let source =
    #|steps:
    #|  - name: A
    #|    with:
    #|      submodules: true
    #|      depth: 1
    #|    uses: B
    #|  - name: C
    #|top: 1
  yml_assert_paths(source, "seqblock.yml", [
    "steps", "steps.name", "steps.with", "steps.with.submodules", "steps.with.depth",
    "steps.uses", "steps.name", "top",
  ])
}

///|
/// A sequence of plain scalars. `- alpha` is a sequence item, not a key, so
/// it must declare nothing — and, just as importantly, must not leave a scope
/// pushed behind it. A rule that completed on the name alone would do both,
/// and then `after` would be reported one level too deep.
test "yaml layout: plain sequence items declare no keys" {
  let source =
    #|paths:
    #|  - alpha
    #|  - beta
    #|after: 1
  yml_assert_paths(source, "items.yml", ["paths", "after"])
}

///|
/// Flow collections suppress layout through the LAYOUT `open`/`close` kinds,
/// so they may span lines freely: the line breaks inside `[` … `]` and `{` …
/// `}` carry no INDENT, and the `k: v` pairs inside a flow map are values,
/// not block keys. Only the three block keys may be declared.
test "yaml layout: flow collections spanning lines declare no inner keys" {
  let source =
    #|flow:
    #|  seq: [
    #|    one,
    #|    two,
    #|  ]
    #|  map: {
    #|    k: v,
    #|    j: w,
    #|  }
    #|plain: 1
  yml_assert_paths(source, "flow.yml", ["flow", "flow.seq", "flow.map", "plain"])
}

///|
/// Block scalars. Layout inside `|` and `>` is text, not structure: a shell
/// script under `run:` may contain colons, dashes and braces that mean
/// nothing to YAML. The body is always indented deeper than its key, so the
/// layout pass has already bracketed it and the grammar swallows that bracket
/// whole — `nested:` and `deeper:` inside the script are NOT keys.
///
/// The folded scalar is the second half of the case: its body is indented
/// deeper still, and `folded` itself must survive. It did not when the rule
/// after a block scalar could run past the body's closing DEDENT and eat the
/// next key.
test "yaml layout: block scalar bodies are text, not structure" {
  let source =
    #|job:
    #|  script: |
    #|    if true; then
    #|      nested: not a key
    #|        deeper: still not
    #|    fi
    #|  folded: >-
    #|      wrapped text
    #|      more text
    #|  after: 1
    #|top: 2
  yml_assert_paths(source, "blockscalar.yml", [
    "job", "job.script", "job.folded", "job.after", "top",
  ])
}

///|
/// Comments at odd columns. YAML lets a comment sit at any column, so a
/// comment-only line carries no layout at all: it neither opens nor closes a
/// level, and the INDENT that opens a block lands AFTER it. A grammar that
/// allowed only one line break between a key and its block would lose the
/// whole block to the comment, and every key under it would be read as a
/// sibling of the key instead of a child.
test "yaml layout: comments at any column carry no layout" {
  let source =
    #|a:
    #|      # deeper than the body
    #|  b: 1
    #|# at column 0
    #|  c: 2
    #|     # between two columns
    #|  d: 3
    #|e: 4
  yml_assert_paths(source, "comments.yml", ["a", "a.b", "a.c", "a.d", "e"])
}

///|
/// A comment between a key and the first line of its block. This is the shape
/// every GitHub workflow uses — a comment introducing a job — and it is where
/// the INDENT lands after the comment rather than before it.
test "yaml layout: a comment before a block does not hide the block" {
  let source =
    #|jobs:
    #|  # the job this comment introduces
    #|  build:
    #|    runs-on: x
    #|after: 1
  yml_assert_paths(source, "jobcomment.yml", [
    "jobs", "jobs.build", "jobs.build.runs-on", "after",
  ])
}

///|
/// Blank lines. A line with no content has no meaningful indentation, so it
/// must not close the block it sits inside: `c` is still a child of `a` even
/// though two blank lines and a column-0 comment separate it from `b`.
test "yaml layout: blank lines do not close a block" {
  let source =
    #|a:
    #|
    #|  b: 1
    #|
    #|# a comment at column 0
    #|
    #|  c: 2
    #|
    #|d: 3
  yml_assert_paths(source, "blank.yml", ["a", "a.b", "a.c", "d"])
}

///|
/// A multi-document stream. `---` starts a new document at the top level, so
/// the keys after it are NOT nested under whatever was open before it, and
/// `...` ends one.
test "yaml layout: document separators reset to the top level" {
  let source =
    #|---
    #|a: 1
    #|b:
    #|  c: 2
    #|---
    #|d: 3
    #|e:
    #|  f: 4
    #|...
  yml_assert_paths(source, "docs.yml", ["a", "b", "b.c", "d", "e", "e.f"])
}

///|
/// A colon only ends a key when whitespace or the end of the line follows it.
/// Every other colon is an ordinary character of a plain scalar, so a docker
/// volume mount or an image tag must not turn the text before it into a key —
/// and a sequence item that happens to contain a colon must declare nothing.
test "yaml layout: a colon inside a scalar does not make a key" {
  let source =
    #|services:
    #|  web:
    #|    image: node:20
    #|    volumes:
    #|      - ./config.yaml:/etc/config.yaml
    #|    url: https://example.com/p
  yml_assert_paths(source, "compose.yml", [
    "services", "services.web", "services.web.image", "services.web.volumes", "services.web.url",
  ])
}

///|
/// The synthetic kinds must actually reach the token stream: INDENT where a
/// line goes deeper, DEDENT for every level a shallower line closes, and one
/// DEDENT per level still open at end of input. They are zero-width, so they
/// are invisible in the text a rule consumes and are checked by kind here.
test "yaml layout: the lexer emits INDENT and DEDENT for YAML" {
  let spec = get_fixture_registry().get_spec("yaml").unwrap()
  let tokens = @lexer.Lexer::for_spec(spec).tokenize(
    "a:\n  b:\n    c: 1\nd: 2\n",
  )
  let kinds : Array[String] = []
  for tok in tokens {
    if tok.kind == "INDENT" || tok.kind == "DEDENT" {
      kinds.push(tok.kind)
    }
  }
  // Two levels open under `a`, both closed by `d` at column 0.
  assert_eq(kinds, ["INDENT", "INDENT", "DEDENT", "DEDENT"])
}

///|
/// INDENT and DEDENT are synthetic: no source text matches them, so the lex
/// section must NOT define them as TOKENs. `kgf check` enforces this, and the
/// spec has to keep satisfying it — a TOKEN rule of that name would make the
/// pass and the lexer fight over the same kind.
test "yaml layout: INDENT and DEDENT are synthetic, not lex tokens" {
  let spec = get_fixture_registry().get_spec("yaml").unwrap()
  for token_def in spec.get_tokens() {
    assert_true(token_def.name != "INDENT")
    assert_true(token_def.name != "DEDENT")
  }
  let layout = spec.get_layout().unwrap()
  assert_eq(layout.get_indent(), "INDENT")
  assert_eq(layout.get_dedent(), "DEDENT")
}

///|
/// The repo's own workflows must parse whole. These are the files the spec
/// exists for, and each exercises several of the cases above at once —
/// comments between jobs, sequences of step mappings, `run: |` scripts and
/// flow sequences — in combinations no hand-written source would cover.
test "yaml layout: the repo's own workflows parse whole" {
  // The test process's working directory is not the repo root, so the
  // workflow directory is found the same way the fixtures and kgfs
  // directories are: by walking up from cwd to the ancestor that holds it.
  // A checkout without the workflow directory (a source tarball, say) has
  // nothing for this case to read; the other tests cover the spec itself, so
  // the loop below simply finds no file and the count assertion is skipped.
  let workflows = match find_ancestor_dir(".github") {
    Some(dir) => dir + "/workflows"
    None => ""
  }
  let mut checked = 0
  for
    name in [
      "ci.yml", "copilot-setup-steps.yml", "pages.yml", "release.yml", "windows-build-test.yml",
    ] {
    let path = workflows + "/" + name
    let source = @fs.read_file_to_string(path) catch { _ => "" }
    // A workflow since renamed or removed is not a spec failure. The count
    // asserted below is what stops this test from passing vacuously if every
    // one of them were unreadable.
    if source.length() == 0 {
      continue
    }
    checked = checked + 1
    let run = run_pipeline_with_registry(
      get_fixture_registry(),
      "yaml",
      source,
      path,
    )
    assert_eq(run.lex_errors, 0)
    assert_true(run.parse_complete())
    // Every workflow has a top-level `jobs`, reported at the top level rather
    // than under whatever key preceded it. Before LAYOUT it came out nested
    // under `on.push`, because the `paths:` block above it never closed.
    let paths = yml_paths_of(run)
    assert_true(paths.iter().any(fn(p) { p == "jobs" }))
  }
  if workflows.length() > 0 {
    assert_true(checked > 0)
  }
}

///|
/// Read a YAML file from the repository-tracked fixture directory and run it
/// through the real pipeline.
///
/// The inline sources above isolate one layout rule each, which is what makes
/// a failure readable. They cannot show that those rules still hold when the
/// constructs are COMBINED the way a real file combines them — a sequence of
/// mappings inside a block inside a document, with comments and flow
/// collections between them. `fixtures/dsl/yaml/` is that file, tracked in
/// the repository so the fixture and its expectation move together.
fn yml_fixture_run(name : String) -> PipelineResult raise {
  let path = get_fixtures_dir() + "/dsl/yaml/" + name
  let source = @fs.read_file_to_string(path) catch { _ => "" }
  // A fixture that cannot be read must fail the test rather than skip it:
  // a silently missing file is how a broken spec keeps passing.
  assert_true(source.length() > 0)
  let run = run_pipeline_with_registry(
    get_fixture_registry(),
    "yaml",
    source,
    path,
  )
  assert_eq(run.lex_errors, 0)
  assert_true(run.parse_complete())
  run
}

///|
/// A realistic CI workflow: nested block mappings, sequences of mappings whose
/// entries carry sibling keys, flow collections, a block scalar, and comments
/// at column 0 and at depth.
///
/// The full path list is asserted, in order, because a nesting bug does not
/// drop a key — it MOVES one, and a test that only checked for the presence
/// of `jobs.build.steps` would pass just as happily with every step reported
/// under the wrong parent.
test "yaml fixture: ci-workflow.yml key paths" {
  let run = yml_fixture_run("ci-workflow.yml")
  assert_eq(yml_paths_of(run), [
    "name", "on", "on.push", "on.push.branches", "on.pull_request", "on.pull_request.branches",
    "env", "env.REGISTRY", "env.IMAGE_NAME", "jobs", "jobs.build", "jobs.build.runs-on",
    "jobs.build.strategy", "jobs.build.strategy.fail-fast", "jobs.build.strategy.matrix",
    "jobs.build.strategy.matrix.node", "jobs.build.strategy.matrix.include", "jobs.build.strategy.matrix.include.node",
    "jobs.build.strategy.matrix.include.coverage", "jobs.build.steps", "jobs.build.steps.uses",
    "jobs.build.steps.name", "jobs.build.steps.uses", "jobs.build.steps.with", "jobs.build.steps.with.node-version",
    "jobs.build.steps.with.cache", "jobs.build.steps.name", "jobs.build.steps.run",
    "jobs.build.steps.name", "jobs.build.steps.run", "jobs.publish", "jobs.publish.needs",
    "jobs.publish.if", "jobs.publish.runs-on", "jobs.publish.steps", "jobs.publish.steps.name",
    "jobs.publish.steps.run",
  ])
}

///|
/// A multi-document file. The `---` that opens the second document returns to
/// the top level: its `apiVersion` is a root key again, not a child of
/// whatever the first document left open. Flow mappings used as values
/// (`labels: {app: ...}`, `requests: {cpu: ...}`) contribute no keys of their
/// own but must not disturb the path of the keys around them.
test "yaml fixture: deployment.yaml spans documents without leaking paths" {
  let run = yml_fixture_run("deployment.yaml")
  let paths = yml_paths_of(run)
  assert_eq(paths, [
    "apiVersion", "kind", "metadata", "metadata.name", "metadata.namespace", "metadata.labels",
    "apiVersion", "kind", "metadata", "metadata.name", "metadata.namespace", "spec",
    "spec.replicas", "spec.selector", "spec.selector.matchLabels", "spec.selector.matchLabels.app",
    "spec.template", "spec.template.metadata", "spec.template.metadata.annotations",
    "spec.template.metadata.annotations.checksum/config", "spec.template.spec", "spec.template.spec.containers",
    "spec.template.spec.containers.name", "spec.template.spec.containers.image",
    "spec.template.spec.containers.ports", "spec.template.spec.containers.args",
    "spec.template.spec.containers.env", "spec.template.spec.containers.env.name",
    "spec.template.spec.containers.env.valueFrom", "spec.template.spec.containers.env.valueFrom.secretKeyRef",
    "spec.template.spec.containers.env.valueFrom.secretKeyRef.name", "spec.template.spec.containers.env.valueFrom.secretKeyRef.key",
    "spec.template.spec.containers.resources", "spec.template.spec.containers.resources.requests",
    "spec.template.spec.containers.resources.limits", "spec.template.spec.containers.readinessProbe",
    "spec.template.spec.containers.readinessProbe.httpGet", "spec.template.spec.containers.readinessProbe.httpGet.path",
    "spec.template.spec.containers.readinessProbe.httpGet.port", "spec.template.spec.volumes",
    "spec.template.spec.volumes.name", "spec.template.spec.volumes.configMap", "spec.template.spec.volumes.configMap.name",
  ])
  // The second document restarts at the root: `apiVersion` appears once per
  // document, at depth 0 both times.
  let roots = paths.iter().filter(fn(p) { p == "apiVersion" }).count()
  assert_eq(roots, 2)
}
