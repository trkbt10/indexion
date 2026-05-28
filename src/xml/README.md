# xml

Single source of truth for producing XML text in indexion.

Producers build an `XmlElement` tree, then call `render_document` (full
document with declaration / DOCTYPE) or `render_element` (fragment). The
renderer is the only place that handles character escaping, attribute
quoting, self-closing tags, and indentation — so a producer cannot
forget to escape `&` or to close a tag.

## API

```moonbit
let el = @xml.element(
  "coverage",
  attributes=[@xml.attr("line-rate", "0.9412")],
  children=[
    @xml.node_element(@xml.element("source", children=[@xml.node_text("/repo")])),
  ],
)
let opts : @xml.XmlDocumentOptions = {
  declaration: "<?xml version=\"1.0\" ?>",
  doctype: "coverage SYSTEM \"…/coverage-04.dtd\"",
  indent: "  ",
  newline: "\n",
}
let xml_text = @xml.render_document(el, options=opts)
```

## Scope

- XML 1.0, UTF-8.
- Elements, attributes, text, comments.
- Self-closing empty elements.
- Single-text-child elements rendered inline (`<p>hi</p>`).
- Pretty-printed with configurable indent and newline.

Out of scope (until a producer needs them): CDATA, processing
instructions, explicit namespace declarations beyond ordinary
attributes, entity references beyond the five predefined ones.

## Consumers

- `@coverage.render_cobertura` (Cobertura `coverage.xml`)
