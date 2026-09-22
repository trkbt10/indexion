// Doc-comment extraction over the repository-tracked programming fixtures.
//
// The cross-package snapshots serialise modules, moduleDependsOn and edge
// counts — they do NOT carry `$doc_text`. A spec that stopped attaching doc
// comments to the declarations they belong to would therefore keep every
// snapshot green while silently emptying the docs that `indexion doc` and
// the README generators are built on.
//
// The `declares_*` suites do assert docs, but over INLINE sources written
// inside the test. That proves the grammar can attach a doc comment; it
// cannot prove the shipped fixture files still carry one, because nothing
// ties the two together. These tests close that gap: they read the real
// fixture files and require a MULTI-LINE doc comment to survive extraction
// with both of its lines intact.

///|
/// The `doc` attribute of every `declares` edge a fixture file produces,
/// keyed by the declared name.
fn fixture_docs_of(
  lang : String,
  rel_path : String,
) -> Map[String, String] raise {
  let path = get_fixtures_dir() + rel_path
  let source = @fs.read_file_to_string(path) catch { _ => "" }
  // A fixture that cannot be read must fail rather than skip: a silently
  // missing file is how a broken spec keeps passing.
  assert_true(source.length() > 0)
  let run = run_pipeline_with_registry(
    get_fixture_registry(),
    lang,
    source,
    path,
  )
  assert_eq(run.lex_errors, 0)
  let docs : Map[String, String] = Map([])
  for edge in run.edges {
    if !(edge.kind is @graph.Declares) {
      continue
    }
    let name = edge.attrs.get("name").unwrap_or("")
    let doc = edge.attrs.get("doc").unwrap_or("")
    // Several declarations may share a name across scopes; the first one
    // that carries a doc is the one these tests describe.
    if doc.length() > 0 && !docs.contains(name) {
      docs.set(name, doc)
    }
  }
  docs
}

///|
/// Assert that `name` is declared in the fixture with a doc comment that
/// still contains BOTH given fragments.
///
/// Two fragments drawn from different LINES of the same comment is the point:
/// a spec that captures only a comment's first line, or that collapses the
/// block into its delimiter, still satisfies a "doc is non-empty" check. It
/// cannot satisfy this one.
fn assert_multiline_doc(
  lang : String,
  rel_path : String,
  name : String,
  first_line : String,
  later_line : String,
) -> Unit raise {
  let docs = fixture_docs_of(lang, rel_path)
  let doc = match docs.get(name) {
    Some(d) => d
    None =>
      fail(
        lang +
        ": no declares edge carrying a doc for '" +
        name +
        "' in " +
        rel_path,
      )
  }
  assert_true(doc.contains(first_line))
  assert_true(doc.contains(later_line))
}

///|
/// Javadoc: a `/** … */` block whose body lines each start with `*`. Both
/// the summary line and a line from the paragraph below the blank `*` must
/// survive, which is what shows the block was read to its end rather than
/// truncated at the first line.
test "fixture docs: java javadoc keeps every line of the block" {
  assert_multiline_doc(
    "java", "/programming/java/UserService.java", "Lookup", "The outcome of a lookup that may have been served from a cache.",
    "Nested because it is meaningless outside this service",
  )
}

///|
/// C# XML documentation comments: consecutive `///` lines forming one
/// `<summary>` element. The opening tag and the prose on the following line
/// belong to the same doc, so both must appear.
test "fixture docs: csharp xml doc spans its consecutive /// lines" {
  assert_multiline_doc(
    "csharp", "/programming/csharp/UserService.cs", "UserService", "<summary>", "Manages user accounts",
  )
}

///|
/// Python docstrings: a triple-quoted string that is the first statement of
/// a def. The summary line and the indented paragraph after the blank line
/// are one docstring and must not be split.
test "fixture docs: python docstring keeps its body paragraph" {
  assert_multiline_doc(
    "python", "/programming/python/pkg/store.py", "list_pending", "Returns the pending tasks sorted by priority.",
    "the most urgent ones rather than an arbitrary prefix",
  )
}

///|
/// TSDoc: a `/** … */` block above an exported function.
test "fixture docs: typescript tsdoc reaches the declaration" {
  assert_multiline_doc(
    "typescript", "/programming/typescript/src/utils.ts", "validateEmail", "Validates an email address.",
    "*",
  )
}
