///|
/// Tests for ManifestPage and WikiManifest JSON round-trip and
/// tolerance of optional fields being absent or null.

///|
test "ManifestPage from_json: full fields" {
  let json : Json = {
    "id": "foo",
    "title": "Foo Page",
    "file": "foo.md",
    "sources": ["src/a.mbt", "src/b.mbt"],
    "children": ["bar"],
    "provenance": "synthesized",
    "last_actor": "agent:claude",
  }
  let page : ManifestPage = @json.from_json(json) catch { e => panic() }
  assert_eq(page.id, "foo")
  assert_eq(page.title, "Foo Page")
  assert_eq(page.file, "foo.md")
  assert_eq(page.sources, ["src/a.mbt", "src/b.mbt"])
  assert_eq(page.children, ["bar"])
  assert_eq(page.provenance, Some("synthesized"))
  assert_eq(page.last_actor, Some("agent:claude"))
}

///|
test "ManifestPage from_json: optional fields absent" {
  // provenance and last_actor are absent — must decode as None, not fail.
  let json : Json = {
    "id": "bar",
    "title": "Bar Page",
    "file": "bar.md",
    "sources": [],
    "children": [],
  }
  let page : ManifestPage = @json.from_json(json) catch { e => panic() }
  assert_eq(page.id, "bar")
  assert_eq(page.provenance, None)
  assert_eq(page.last_actor, None)
}

///|
test "ManifestPage from_json: optional fields null" {
  let json : Json = {
    "id": "baz",
    "title": "Baz",
    "file": "baz.md",
    "sources": [],
    "children": [],
    "provenance": Json::null(),
    "last_actor": Json::null(),
  }
  let page : ManifestPage = @json.from_json(json) catch { e => panic() }
  assert_eq(page.provenance, None)
  assert_eq(page.last_actor, None)
}

///|
test "ManifestPage from_json: sources and children absent" {
  // sources and children absent — must default to empty array.
  let json : Json = {
    "id": "qux",
    "title": "Qux",
    "file": "qux.md",
  }
  let page : ManifestPage = @json.from_json(json) catch { e => panic() }
  assert_eq(page.sources, [])
  assert_eq(page.children, [])
}

///|
test "ManifestPage ToJson / FromJson round-trip" {
  let original = ManifestPage::new(
    id="round",
    title="Round Trip",
    file="round.md",
    sources=["x.mbt"],
    children=["child1"],
    provenance=Some("manual"),
    last_actor=Some("user"),
  )
  let json = original.to_json()
  let decoded : ManifestPage = @json.from_json(json) catch { e => panic() }
  assert_eq(decoded, original)
}

///|
test "WikiManifest from_json: full" {
  let json : Json = {
    "title": "My Wiki",
    "pages": [
      {
        "id": "overview",
        "title": "Overview",
        "file": "overview.md",
        "sources": [],
        "children": [],
      },
      {
        "id": "guide",
        "title": "Guide",
        "file": "guide.md",
        "sources": ["src/a.mbt"],
        "children": [],
        "provenance": "synthesized",
        "last_actor": "agent:claude",
      },
    ],
  }
  let manifest : WikiManifest = @json.from_json(json) catch { e => panic() }
  assert_eq(manifest.title, "My Wiki")
  assert_eq(manifest.pages.length(), 2)
  assert_eq(manifest.pages[0].id, "overview")
  assert_eq(manifest.pages[0].provenance, None)
  assert_eq(manifest.pages[1].id, "guide")
  assert_eq(manifest.pages[1].provenance, Some("synthesized"))
}

///|
test "WikiManifest ToJson / FromJson round-trip" {
  let original = WikiManifest::new(
    title="Test Wiki",
    pages=[
      ManifestPage::new(
        id="p1",
        title="Page 1",
        file="p1.md",
        sources=["a.mbt"],
        provenance=Some("extracted"),
      ),
      ManifestPage::new(id="p2", title="Page 2", file="p2.md"),
    ],
  )
  let json = original.to_json()
  let decoded : WikiManifest = @json.from_json(json) catch { e => panic() }
  assert_eq(decoded, original)
}
