///|
/// XML writer.
///
/// Single source of truth for producing XML text in indexion. Producers
/// build an `XmlElement` tree, then call `render_document` (or
/// `render_element` for a fragment). The renderer is the only place that
/// handles character escaping, attribute ordering, self-closing tags, and
/// indentation, so a producer cannot accidentally emit `<a&b>` or forget
/// a closing tag.
///
/// Scope: pretty-printed XML 1.0, UTF-8, no namespaces declarations beyond
/// what the producer chooses to add as ordinary attributes, no CDATA. The
/// emitted text covers what Cobertura, JUnit XML, SARIF, and similar
/// "structured-report XML" consumers expect.

///|
/// A single XML attribute. Attributes are kept in an explicit list rather
/// than a map so producers control the emission order — Cobertura and many
/// XML tools care about attribute order for human-diffable output.
pub(all) struct XmlAttr {
  name : String
  value : String
}

///|
/// Construct an attribute. Pure helper so call sites read like
/// `attr("name", value)` instead of struct-literal noise.
pub fn attr(name : String, value : String) -> XmlAttr {
  { name, value }
}

///|
/// Node kinds. Comments are included because they're useful for emitting
/// generator banners; CDATA and processing instructions are deliberately
/// left out until a producer needs them.
pub enum XmlNode {
  Element(XmlElement)
  Text(String)
  Comment(String)
}

///|
/// XML element. `children` is `Array[XmlNode]` so an element can hold a
/// mix of nested elements and text. An element with no children renders
/// as a self-closing tag (`<name attr="…"/>`).
pub(all) struct XmlElement {
  name : String
  attributes : Array[XmlAttr]
  children : Array[XmlNode]
}

///|
/// Construct an element. Pure helper used to keep producer code declarative.
pub fn element(
  name : String,
  attributes? : Array[XmlAttr] = [],
  children? : Array[XmlNode] = [],
) -> XmlElement {
  { name, attributes, children }
}

///|
/// Wrap an element as an `XmlNode::Element` for inclusion in another
/// element's children list.
pub fn node_element(el : XmlElement) -> XmlNode {
  Element(el)
}

///|
/// Text node helper.
pub fn node_text(s : String) -> XmlNode {
  Text(s)
}

///|
/// Comment node helper. The `--` sequence is forbidden inside XML comments
/// per the XML 1.0 spec; the renderer replaces any occurrence with `- -`
/// so well-formedness is preserved even if the producer is careless.
pub fn node_comment(s : String) -> XmlNode {
  Comment(s)
}

///|
/// Top-level document options. All optional — producers that don't care
/// about a DOCTYPE leave it as the empty string.
pub(all) struct XmlDocumentOptions {
  /// XML declaration; empty means no declaration line is emitted.
  /// `XmlDocumentOptions::default()` sets this to the standard form.
  declaration : String
  /// Optional DOCTYPE line. Empty means no DOCTYPE. The renderer wraps
  /// this in `<!DOCTYPE …>` exactly as provided — escaping does not apply
  /// because DOCTYPE syntax is not regular XML content.
  doctype : String
  /// Indentation unit per nesting level. Two spaces by default.
  indent : String
  /// Newline used between rendered lines.
  newline : String
}

///|
/// Default document options: standard XML declaration, no DOCTYPE,
/// two-space indent, `\n` newlines.
pub fn XmlDocumentOptions::default() -> XmlDocumentOptions {
  {
    declaration: "<?xml version=\"1.0\" ?>",
    doctype: "",
    indent: "  ",
    newline: "\n",
  }
}

///|
/// Render a full XML document: declaration → DOCTYPE → root element.
pub fn render_document(
  root : XmlElement,
  options? : XmlDocumentOptions = XmlDocumentOptions::default(),
) -> String {
  let buf = StringBuilder::new()
  if options.declaration.length() > 0 {
    buf.write_string(options.declaration)
    buf.write_string(options.newline)
  }
  if options.doctype.length() > 0 {
    buf.write_string("<!DOCTYPE ")
    buf.write_string(options.doctype)
    buf.write_string(">")
    buf.write_string(options.newline)
  }
  write_element(buf, root, 0, options.indent, options.newline)
  buf.to_string()
}

///|
/// Render a single element without document framing. Useful for fragments
/// or for tests that want to assert on a sub-tree.
pub fn render_element(
  el : XmlElement,
  indent? : String = "  ",
  newline? : String = "\n",
) -> String {
  let buf = StringBuilder::new()
  write_element(buf, el, 0, indent, newline)
  buf.to_string()
}

///|
fn write_element(
  buf : StringBuilder,
  el : XmlElement,
  depth : Int,
  indent : String,
  newline : String,
) -> Unit {
  write_indent(buf, indent, depth)
  buf.write_string("<")
  buf.write_string(el.name)
  for a in el.attributes {
    buf.write_string(" ")
    buf.write_string(a.name)
    buf.write_string("=\"")
    buf.write_string(escape(a.value, in_attribute=true))
    buf.write_string("\"")
  }
  if el.children.length() == 0 {
    buf.write_string("/>")
    buf.write_string(newline)
    return
  }
  // Children present. Special-case "single text child" so it renders as
  // <name>text</name> on one line instead of awkward 3-line spreading.
  if el.children.length() == 1 {
    match el.children[0] {
      Text(t) => {
        buf.write_string(">")
        buf.write_string(escape(t))
        buf.write_string("</")
        buf.write_string(el.name)
        buf.write_string(">")
        buf.write_string(newline)
        return
      }
      _ => ()
    }
  }
  buf.write_string(">")
  buf.write_string(newline)
  for child in el.children {
    match child {
      Element(sub) => write_element(buf, sub, depth + 1, indent, newline)
      Text(t) => {
        write_indent(buf, indent, depth + 1)
        buf.write_string(escape(t))
        buf.write_string(newline)
      }
      Comment(c) => {
        write_indent(buf, indent, depth + 1)
        buf.write_string("<!--")
        buf.write_string(sanitize_comment(c))
        buf.write_string("-->")
        buf.write_string(newline)
      }
    }
  }
  write_indent(buf, indent, depth)
  buf.write_string("</")
  buf.write_string(el.name)
  buf.write_string(">")
  buf.write_string(newline)
}

///|
fn write_indent(buf : StringBuilder, indent : String, depth : Int) -> Unit {
  for _ in 0..<depth {
    buf.write_string(indent)
  }
}

///|
/// Escape XML special characters.
///
/// The base set — always escaped — is the three characters that XML 1.0
/// disallows in element text: `&` and `<`, plus `>` which we include to
/// dodge the `]]>` sequence and to follow common practice.
///
/// `in_attribute=true` adds `"` and `'` so the result is safe inside
/// double- or single-quoted attribute values. `false` leaves quotes
/// alone, which keeps body text readable (`<p>say "hi"</p>` rather than
/// `<p>say &quot;hi&quot;</p>`).
pub fn escape(s : String, in_attribute? : Bool = false) -> String {
  let chars = s.to_array()
  let buf = StringBuilder::new()
  for c in chars {
    match c {
      '&' => buf.write_string("&amp;")
      '<' => buf.write_string("&lt;")
      '>' => buf.write_string("&gt;")
      '"' =>
        if in_attribute {
          buf.write_string("&quot;")
        } else {
          buf.write_char(c)
        }
      '\'' =>
        if in_attribute {
          buf.write_string("&apos;")
        } else {
          buf.write_char(c)
        }
      _ => buf.write_char(c)
    }
  }
  buf.to_string()
}

///|
/// XML 1.0 forbids `--` inside comments. We substitute `- -` so a careless
/// producer can't break well-formedness. Trailing `-` is also disallowed
/// directly before the closing `-->`, so we append a space when needed.
fn sanitize_comment(s : String) -> String {
  let chars = s.to_array()
  let buf = StringBuilder::new()
  let mut i = 0
  while i < chars.length() {
    if i + 1 < chars.length() && chars[i] == '-' && chars[i + 1] == '-' {
      buf.write_string("- -")
      i = i + 2
    } else {
      buf.write_char(chars[i])
      i = i + 1
    }
  }
  let out = buf.to_string()
  let out_chars = out.to_array()
  if out_chars.length() > 0 && out_chars[out_chars.length() - 1] == '-' {
    out + " "
  } else {
    out
  }
}
