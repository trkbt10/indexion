///|
test "render: empty element renders as self-closing tag" {
  let el = element("br")
  assert_eq(render_element(el), "<br/>\n")
}

///|
test "render: attributes preserve insertion order and are quoted" {
  let el = element("input", attributes=[
    attr("type", "text"),
    attr("name", "x"),
    attr("value", "1"),
  ])
  assert_eq(
    render_element(el),
    "<input type=\"text\" name=\"x\" value=\"1\"/>\n",
  )
}

///|
test "render: single text child renders inline" {
  let el = element("p", children=[node_text("hello")])
  assert_eq(render_element(el), "<p>hello</p>\n")
}

///|
test "render: nested elements are indented" {
  let inner = element("b", children=[node_text("bold")])
  let outer = element("p", children=[node_text("hi"), node_element(inner)])
  // Mixed-content element: every child goes on its own line.
  let want =
    #|<p>
    #|  hi
    #|  <b>bold</b>
    #|</p>
    #|
  assert_eq(render_element(outer), want)
}

///|
test "render: attribute values are escaped against all five entities" {
  let el = element("a", attributes=[
    attr("href", "x?y=1&z=2"),
    attr("title", "she said \"hi\" & '"),
  ])
  let out = render_element(el)
  assert_true(out.contains("href=\"x?y=1&amp;z=2\""))
  assert_true(out.contains("title=\"she said &quot;hi&quot; &amp; &apos;\""))
}

///|
test "render: text content escapes &, < and >" {
  let el = element("p", children=[node_text("a < b && c > d")])
  assert_eq(render_element(el), "<p>a &lt; b &amp;&amp; c &gt; d</p>\n")
}

///|
test "render: document adds declaration and optional DOCTYPE" {
  let root = element("coverage")
  let opts : XmlDocumentOptions = {
    declaration: "<?xml version=\"1.0\" ?>",
    doctype: "coverage SYSTEM \"http://example/coverage.dtd\"",
    indent: "  ",
    newline: "\n",
  }
  let out = render_document(root, options=opts)
  let want =
    #|<?xml version="1.0" ?>
    #|<!DOCTYPE coverage SYSTEM "http://example/coverage.dtd">
    #|<coverage/>
    #|
  assert_eq(out, want)
}

///|
test "render: comment renders with -- collapsed to - -" {
  let el = element("root", children=[node_comment(" generated -- by tool ")])
  let out = render_element(el)
  assert_true(out.contains("<!-- generated - - by tool -->"))
}

///|
test "render: comment trailing dash gets a trailing space" {
  let el = element("r", children=[node_comment("ends with -")])
  let out = render_element(el)
  assert_true(out.contains("<!--ends with - -->"))
}

///|
test "escape: text context escapes &, <, > only" {
  assert_eq(escape("a & b < c > d"), "a &amp; b &lt; c &gt; d")
  // Quotes are not escaped in text context.
  assert_eq(escape("she said \"x\""), "she said \"x\"")
}

///|
test "escape: attribute context adds quote-character entities" {
  assert_eq(
    escape("a&b<c>d\"e'f", in_attribute=true),
    "a&amp;b&lt;c&gt;d&quot;e&apos;f",
  )
}

///|
test "escape: default == text context" {
  // The default `in_attribute=false` must match the explicit form.
  assert_eq(escape("\"x\" & 'y'"), escape("\"x\" & 'y'", in_attribute=false))
}
