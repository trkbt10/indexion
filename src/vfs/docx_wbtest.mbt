///|
/// Whitebox tests for DOCX (WordprocessingML) archive expansion.
/// Validates that VFS correctly includes/excludes entries
/// based on the ECMA-376 part structure defined in docx.kgf.

///|
/// Build a unique temp directory path for test artifacts.
fn docx_temp_dir(label : String) -> String {
  let base = match @config.get_global_cache_dir() {
    Some(dir) => dir + "/indexion-test"
    None => "/tmp/indexion-test"
  }
  base + "/docx-" + label + "-" + @env.now().to_string()
}

///|
/// Convert a String to FixedArray[Byte] via fzip's str_to_u8.
fn string_to_fixed_bytes(s : String) -> FixedArray[Byte] {
  @fzip.str_to_u8(s)
}

///|
/// Convert FixedArray[Byte] to Bytes for writing to disk.
fn fixed_array_to_bytes(arr : FixedArray[Byte]) -> Bytes {
  Bytes::from_array(Array::from_fixed_array(arr))
}

///|
/// XML namespace for WordprocessingML (ECMA-376 Part 1, Section 11.3.10).
let wml_ns : String = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"

///|
/// XML namespace for extended properties (ECMA-376 Part 2, Section 11.2).
let ep_ns : String = "http://schemas.openxmlformats.org/officeDocument/2006/extended-properties"

///|
/// XML namespace for custom properties (ECMA-376 Part 2, Section 11.3).
let custom_ns : String = "http://schemas.openxmlformats.org/officeDocument/2006/custom-properties"

///|
/// Dublin Core namespace for core properties.
let dc_ns : String = "http://purl.org/dc/elements/1.1/"

///|
/// Dublin Core Terms namespace.
let dcterms_ns : String = "http://purl.org/dc/terms/"

///|
/// Core Properties namespace.
let cp_ns : String = "http://schemas.openxmlformats.org/package/2006/metadata/core-properties"

///|
/// Content Types namespace.
let ct_ns : String = "http://schemas.openxmlformats.org/package/2006/content-types"

///|
/// Relationships namespace.
let rels_ns : String = "http://schemas.openxmlformats.org/package/2006/relationships"

///|
/// Build the [Content_Types].xml part.
/// This is a structural part that should be EXCLUDED by the KGF spec.
fn make_content_types_xml() -> String {
  let buf = StringBuilder::new()
  buf.write_string("<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n")
  buf.write_string("<Types xmlns=\"")
  buf.write_string(ct_ns)
  buf.write_string("\">\n")
  buf.write_string("  <Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/>\n")
  buf.write_string("  <Default Extension=\"xml\" ContentType=\"application/xml\"/>\n")
  buf.write_string("  <Override PartName=\"/word/document.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml\"/>\n")
  buf.write_string("</Types>")
  buf.to_string()
}

///|
/// Build the top-level _rels/.rels part.
/// Structural relationship part — should be EXCLUDED.
fn make_root_rels() -> String {
  let buf = StringBuilder::new()
  buf.write_string("<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n")
  buf.write_string("<Relationships xmlns=\"")
  buf.write_string(rels_ns)
  buf.write_string("\">\n")
  buf.write_string("  <Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"word/document.xml\"/>\n")
  buf.write_string("  <Relationship Id=\"rId2\" Type=\"http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties\" Target=\"docProps/core.xml\"/>\n")
  buf.write_string("</Relationships>")
  buf.to_string()
}

///|
/// Build word/_rels/document.xml.rels.
/// Structural relationship part — should be EXCLUDED.
fn make_document_rels() -> String {
  let buf = StringBuilder::new()
  buf.write_string("<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n")
  buf.write_string("<Relationships xmlns=\"")
  buf.write_string(rels_ns)
  buf.write_string("\">\n")
  buf.write_string("  <Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles\" Target=\"styles.xml\"/>\n")
  buf.write_string("  <Relationship Id=\"rId2\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/header\" Target=\"header1.xml\"/>\n")
  buf.write_string("</Relationships>")
  buf.to_string()
}

///|
/// Build word/glossary/_rels/document.xml.rels.
/// Structural relationship part for glossary — should be EXCLUDED.
fn make_glossary_rels() -> String {
  let buf = StringBuilder::new()
  buf.write_string("<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n")
  buf.write_string("<Relationships xmlns=\"")
  buf.write_string(rels_ns)
  buf.write_string("\">\n")
  buf.write_string("  <Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles\" Target=\"styles.xml\"/>\n")
  buf.write_string("</Relationships>")
  buf.to_string()
}

///|
/// Build word/document.xml — the main document body.
/// Contains paragraphs with runs and text elements per ECMA-376 Section 17.3.
fn make_document_xml() -> String {
  let buf = StringBuilder::new()
  buf.write_string("<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n")
  buf.write_string("<w:document xmlns:w=\"")
  buf.write_string(wml_ns)
  buf.write_string("\">\n")
  buf.write_string("  <w:body>\n")
  buf.write_string("    <w:p>\n")
  buf.write_string("      <w:r>\n")
  buf.write_string("        <w:t>This is the main document body.</w:t>\n")
  buf.write_string("      </w:r>\n")
  buf.write_string("    </w:p>\n")
  buf.write_string("    <w:p>\n")
  buf.write_string("      <w:r>\n")
  buf.write_string("        <w:t>Second paragraph with formatting.</w:t>\n")
  buf.write_string("      </w:r>\n")
  buf.write_string("    </w:p>\n")
  buf.write_string("  </w:body>\n")
  buf.write_string("</w:document>")
  buf.to_string()
}

///|
/// Build a word/headerN.xml part.
/// Headers use <w:hdr> root element per ECMA-376 Section 17.10.3.
fn make_header_xml(number : Int, text : String) -> String {
  let buf = StringBuilder::new()
  buf.write_string("<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n")
  buf.write_string("<w:hdr xmlns:w=\"")
  buf.write_string(wml_ns)
  buf.write_string("\">\n")
  buf.write_string("  <w:p>\n")
  buf.write_string("    <w:r>\n")
  buf.write_string("      <w:t>Header ")
  buf.write_string(number.to_string())
  buf.write_string(": ")
  buf.write_string(text)
  buf.write_string("</w:t>\n")
  buf.write_string("    </w:r>\n")
  buf.write_string("  </w:p>\n")
  buf.write_string("</w:hdr>")
  buf.to_string()
}

///|
/// Build a word/footerN.xml part.
/// Footers use <w:ftr> root element per ECMA-376 Section 17.10.2.
fn make_footer_xml(number : Int, text : String) -> String {
  let buf = StringBuilder::new()
  buf.write_string("<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n")
  buf.write_string("<w:ftr xmlns:w=\"")
  buf.write_string(wml_ns)
  buf.write_string("\">\n")
  buf.write_string("  <w:p>\n")
  buf.write_string("    <w:r>\n")
  buf.write_string("      <w:t>Footer ")
  buf.write_string(number.to_string())
  buf.write_string(": ")
  buf.write_string(text)
  buf.write_string("</w:t>\n")
  buf.write_string("    </w:r>\n")
  buf.write_string("  </w:p>\n")
  buf.write_string("</w:ftr>")
  buf.to_string()
}

///|
/// Build word/footnotes.xml.
/// Contains footnote elements per ECMA-376 Section 17.11.8.
fn make_footnotes_xml() -> String {
  let buf = StringBuilder::new()
  buf.write_string("<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n")
  buf.write_string("<w:footnotes xmlns:w=\"")
  buf.write_string(wml_ns)
  buf.write_string("\">\n")
  buf.write_string("  <w:footnote w:type=\"separator\" w:id=\"-1\">\n")
  buf.write_string("    <w:p><w:r><w:separator/></w:r></w:p>\n")
  buf.write_string("  </w:footnote>\n")
  buf.write_string("  <w:footnote w:id=\"1\">\n")
  buf.write_string("    <w:p>\n")
  buf.write_string("      <w:r>\n")
  buf.write_string("        <w:t>This is a footnote with additional context.</w:t>\n")
  buf.write_string("      </w:r>\n")
  buf.write_string("    </w:p>\n")
  buf.write_string("  </w:footnote>\n")
  buf.write_string("</w:footnotes>")
  buf.to_string()
}

///|
/// Build word/endnotes.xml.
/// Contains endnote elements per ECMA-376 Section 17.11.4.
fn make_endnotes_xml() -> String {
  let buf = StringBuilder::new()
  buf.write_string("<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n")
  buf.write_string("<w:endnotes xmlns:w=\"")
  buf.write_string(wml_ns)
  buf.write_string("\">\n")
  buf.write_string("  <w:endnote w:type=\"separator\" w:id=\"-1\">\n")
  buf.write_string("    <w:p><w:r><w:separator/></w:r></w:p>\n")
  buf.write_string("  </w:endnote>\n")
  buf.write_string("  <w:endnote w:id=\"1\">\n")
  buf.write_string("    <w:p>\n")
  buf.write_string("      <w:r>\n")
  buf.write_string("        <w:t>This is an endnote reference.</w:t>\n")
  buf.write_string("      </w:r>\n")
  buf.write_string("    </w:p>\n")
  buf.write_string("  </w:endnote>\n")
  buf.write_string("</w:endnotes>")
  buf.to_string()
}

///|
/// Build word/comments.xml.
/// Contains comment elements per ECMA-376 Section 17.13.4.2.
fn make_comments_xml() -> String {
  let buf = StringBuilder::new()
  buf.write_string("<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n")
  buf.write_string("<w:comments xmlns:w=\"")
  buf.write_string(wml_ns)
  buf.write_string("\">\n")
  buf.write_string("  <w:comment w:id=\"0\" w:author=\"Reviewer\" w:date=\"2024-01-15T10:30:00Z\">\n")
  buf.write_string("    <w:p>\n")
  buf.write_string("      <w:r>\n")
  buf.write_string("        <w:t>Please review this section carefully.</w:t>\n")
  buf.write_string("      </w:r>\n")
  buf.write_string("    </w:p>\n")
  buf.write_string("  </w:comment>\n")
  buf.write_string("</w:comments>")
  buf.to_string()
}

///|
/// Build word/commentsExtended.xml.
/// Extended comments introduced in Office 2013 (ISO/IEC 29500:2012 amendment).
fn make_comments_extended_xml() -> String {
  let buf = StringBuilder::new()
  buf.write_string("<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n")
  buf.write_string("<w15:commentsEx xmlns:w15=\"http://schemas.microsoft.com/office/word/2012/wordml\">\n")
  buf.write_string("  <w15:commentEx w15:paraId=\"00000001\" w15:done=\"0\"/>\n")
  buf.write_string("</w15:commentsEx>")
  buf.to_string()
}

///|
/// Build word/numbering.xml.
/// List numbering definitions per ECMA-376 Section 17.9.
fn make_numbering_xml() -> String {
  let buf = StringBuilder::new()
  buf.write_string("<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n")
  buf.write_string("<w:numbering xmlns:w=\"")
  buf.write_string(wml_ns)
  buf.write_string("\">\n")
  buf.write_string("  <w:abstractNum w:abstractNumId=\"0\">\n")
  buf.write_string("    <w:lvl w:ilvl=\"0\">\n")
  buf.write_string("      <w:start w:val=\"1\"/>\n")
  buf.write_string("      <w:numFmt w:val=\"decimal\"/>\n")
  buf.write_string("      <w:lvlText w:val=\"%1.\"/>\n")
  buf.write_string("    </w:lvl>\n")
  buf.write_string("  </w:abstractNum>\n")
  buf.write_string("  <w:num w:numId=\"1\">\n")
  buf.write_string("    <w:abstractNumId w:val=\"0\"/>\n")
  buf.write_string("  </w:num>\n")
  buf.write_string("</w:numbering>")
  buf.to_string()
}

///|
/// Build word/styles.xml.
/// Style definitions per ECMA-376 Section 17.7.
fn make_styles_xml() -> String {
  let buf = StringBuilder::new()
  buf.write_string("<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n")
  buf.write_string("<w:styles xmlns:w=\"")
  buf.write_string(wml_ns)
  buf.write_string("\">\n")
  buf.write_string("  <w:style w:type=\"paragraph\" w:styleId=\"Normal\">\n")
  buf.write_string("    <w:name w:val=\"Normal\"/>\n")
  buf.write_string("    <w:qFormat/>\n")
  buf.write_string("  </w:style>\n")
  buf.write_string("  <w:style w:type=\"paragraph\" w:styleId=\"Heading1\">\n")
  buf.write_string("    <w:name w:val=\"heading 1\"/>\n")
  buf.write_string("    <w:basedOn w:val=\"Normal\"/>\n")
  buf.write_string("    <w:qFormat/>\n")
  buf.write_string("  </w:style>\n")
  buf.write_string("</w:styles>")
  buf.to_string()
}

///|
/// Build word/glossary/document.xml.
/// Glossary document (building blocks) per ECMA-376 Section 17.12.
fn make_glossary_document_xml() -> String {
  let buf = StringBuilder::new()
  buf.write_string("<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n")
  buf.write_string("<w:glossaryDocument xmlns:w=\"")
  buf.write_string(wml_ns)
  buf.write_string("\">\n")
  buf.write_string("  <w:docParts>\n")
  buf.write_string("    <w:docPart>\n")
  buf.write_string("      <w:docPartPr>\n")
  buf.write_string("        <w:name w:val=\"AutoText Entry\"/>\n")
  buf.write_string("      </w:docPartPr>\n")
  buf.write_string("      <w:docPartBody>\n")
  buf.write_string("        <w:p>\n")
  buf.write_string("          <w:r>\n")
  buf.write_string("            <w:t>Glossary building block content.</w:t>\n")
  buf.write_string("          </w:r>\n")
  buf.write_string("        </w:p>\n")
  buf.write_string("      </w:docPartBody>\n")
  buf.write_string("    </w:docPart>\n")
  buf.write_string("  </w:docParts>\n")
  buf.write_string("</w:glossaryDocument>")
  buf.to_string()
}

///|
/// Build docProps/core.xml.
/// Dublin Core metadata per ECMA-376 Part 2, Section 11.1.
fn make_core_properties_xml() -> String {
  let buf = StringBuilder::new()
  buf.write_string("<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n")
  buf.write_string("<cp:coreProperties xmlns:cp=\"")
  buf.write_string(cp_ns)
  buf.write_string("\" xmlns:dc=\"")
  buf.write_string(dc_ns)
  buf.write_string("\" xmlns:dcterms=\"")
  buf.write_string(dcterms_ns)
  buf.write_string("\">\n")
  buf.write_string("  <dc:title>Test Document Title</dc:title>\n")
  buf.write_string("  <dc:creator>Test Author</dc:creator>\n")
  buf.write_string("  <dc:subject>ECMA-376 Conformance Test</dc:subject>\n")
  buf.write_string("  <dcterms:created>2024-01-15T10:00:00Z</dcterms:created>\n")
  buf.write_string("  <dcterms:modified>2024-01-15T12:00:00Z</dcterms:modified>\n")
  buf.write_string("</cp:coreProperties>")
  buf.to_string()
}

///|
/// Build docProps/app.xml.
/// Application metadata per ECMA-376 Part 2, Section 11.2.
fn make_app_properties_xml() -> String {
  let buf = StringBuilder::new()
  buf.write_string("<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n")
  buf.write_string("<Properties xmlns=\"")
  buf.write_string(ep_ns)
  buf.write_string("\">\n")
  buf.write_string("  <Application>indexion test suite</Application>\n")
  buf.write_string("  <Pages>3</Pages>\n")
  buf.write_string("  <Words>150</Words>\n")
  buf.write_string("  <Characters>900</Characters>\n")
  buf.write_string("</Properties>")
  buf.to_string()
}

///|
/// Build docProps/custom.xml.
/// Custom properties per ECMA-376 Part 2, Section 11.3.
fn make_custom_properties_xml() -> String {
  let buf = StringBuilder::new()
  buf.write_string("<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n")
  buf.write_string("<Properties xmlns=\"")
  buf.write_string(custom_ns)
  buf.write_string("\">\n")
  buf.write_string("  <property fmtid=\"{D5CDD505-2E9C-101B-9397-08002B2CF9AE}\" pid=\"2\" name=\"Project\">\n")
  buf.write_string("    <vt:lpwstr xmlns:vt=\"http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes\">indexion</vt:lpwstr>\n")
  buf.write_string("  </property>\n")
  buf.write_string("</Properties>")
  buf.to_string()
}

///|
/// Assemble all parts into a DOCX ZIP archive using fzip.
/// Returns the ZIP bytes as FixedArray[Byte].
fn build_docx_fixture() -> FixedArray[Byte] {
  let entries : Array[(String, FixedArray[Byte])] = []
  // Structural parts (should be EXCLUDED)
  entries.push(("[Content_Types].xml", string_to_fixed_bytes(make_content_types_xml())))
  entries.push(("_rels/.rels", string_to_fixed_bytes(make_root_rels())))
  entries.push(("word/_rels/document.xml.rels", string_to_fixed_bytes(make_document_rels())))
  entries.push(("word/glossary/_rels/document.xml.rels", string_to_fixed_bytes(make_glossary_rels())))
  // Main document body
  entries.push(("word/document.xml", string_to_fixed_bytes(make_document_xml())))
  // Headers (first page, odd, even)
  entries.push(("word/header1.xml", string_to_fixed_bytes(make_header_xml(1, "First Page"))))
  entries.push(("word/header2.xml", string_to_fixed_bytes(make_header_xml(2, "Odd Pages"))))
  entries.push(("word/header3.xml", string_to_fixed_bytes(make_header_xml(3, "Even Pages"))))
  // Footers
  entries.push(("word/footer1.xml", string_to_fixed_bytes(make_footer_xml(1, "First Page"))))
  entries.push(("word/footer2.xml", string_to_fixed_bytes(make_footer_xml(2, "Odd Pages"))))
  entries.push(("word/footer3.xml", string_to_fixed_bytes(make_footer_xml(3, "Even Pages"))))
  // Notes and comments
  entries.push(("word/footnotes.xml", string_to_fixed_bytes(make_footnotes_xml())))
  entries.push(("word/endnotes.xml", string_to_fixed_bytes(make_endnotes_xml())))
  entries.push(("word/comments.xml", string_to_fixed_bytes(make_comments_xml())))
  entries.push(("word/commentsExtended.xml", string_to_fixed_bytes(make_comments_extended_xml())))
  // Definitions
  entries.push(("word/numbering.xml", string_to_fixed_bytes(make_numbering_xml())))
  entries.push(("word/styles.xml", string_to_fixed_bytes(make_styles_xml())))
  // Glossary
  entries.push(("word/glossary/document.xml", string_to_fixed_bytes(make_glossary_document_xml())))
  // Properties
  entries.push(("docProps/core.xml", string_to_fixed_bytes(make_core_properties_xml())))
  entries.push(("docProps/app.xml", string_to_fixed_bytes(make_app_properties_xml())))
  entries.push(("docProps/custom.xml", string_to_fixed_bytes(make_custom_properties_xml())))
  // Binary media entry (should be excluded by inner_includes — not in the pattern list)
  let fake_image : FixedArray[Byte] = FixedArray::make(8, b'\x89')
  fake_image[1] = b'\x50'
  fake_image[2] = b'\x4E'
  fake_image[3] = b'\x47'
  entries.push(("word/media/image1.png", fake_image))
  @fzip.zip_sync(entries)
}

///|
/// Write FixedArray[Byte] to a file path.
fn write_fixture_to_disk(
  path : String,
  data : FixedArray[Byte],
) -> Unit raise Error {
  @fs.write_bytes_to_file(path, fixed_array_to_bytes(data))
}

///|
/// The docx.kgf inner_includes patterns.
/// Kept in sync with the spec — the test validates these patterns
/// correctly select ECMA-376 document-relevant parts.
fn docx_inner_includes() -> Array[String] {
  [
    "word/document.xml",
    "word/footnotes.xml",
    "word/endnotes.xml",
    "word/comments.xml",
    "word/commentsExtended.xml",
    "word/header*.xml",
    "word/footer*.xml",
    "word/numbering.xml",
    "word/styles.xml",
    "word/glossary/document.xml",
    "docProps/core.xml",
    "docProps/app.xml",
    "docProps/custom.xml",
  ]
}

///|
/// The docx.kgf inner_excludes patterns.
fn docx_inner_excludes() -> Array[String] {
  ["word/_rels/*", "word/glossary/_rels/*"]
}

///|
/// Build an ArchiveSpec matching the docx.kgf definition.
fn docx_archive_spec() -> ArchiveSpec {
  { inner_includes: docx_inner_includes(), inner_excludes: docx_inner_excludes() }
}

///|
/// All ECMA-376 part names that MUST be included in the VFS expansion.
fn expected_included_parts() -> Array[String] {
  [
    "word/document.xml",
    "word/header1.xml",
    "word/header2.xml",
    "word/header3.xml",
    "word/footer1.xml",
    "word/footer2.xml",
    "word/footer3.xml",
    "word/footnotes.xml",
    "word/endnotes.xml",
    "word/comments.xml",
    "word/commentsExtended.xml",
    "word/numbering.xml",
    "word/styles.xml",
    "word/glossary/document.xml",
    "docProps/core.xml",
    "docProps/app.xml",
    "docProps/custom.xml",
  ]
}

///|
/// All part names that MUST be excluded from the VFS expansion.
fn expected_excluded_parts() -> Array[String] {
  [
    "[Content_Types].xml",
    "_rels/.rels",
    "word/_rels/document.xml.rels",
    "word/glossary/_rels/document.xml.rels",
    "word/media/image1.png",
  ]
}

///|
test "docx: expand_archive includes all document-relevant parts" {
  let dir = docx_temp_dir("includes")
  @fs.create_dir(dir)
  let docx_path = dir + "/test.docx"
  let fixture = build_docx_fixture()
  write_fixture_to_disk(docx_path, fixture)
  let entries = expand_archive(docx_path, docx_archive_spec())
  let entry_names : Array[String] = []
  for e in entries {
    // Extract inner path from virtual_path: "dir/test.docx!/word/document.xml" -> "word/document.xml"
    entry_names.push(inner_path(e.virtual_path))
  }
  let expected = expected_included_parts()
  for part in expected {
    let mut found = false
    for name in entry_names {
      if name == part {
        found = true
        break
      }
    }
    assert_true(found, msg="expected included part not found: " + part)
  }
  // Cleanup
  @fs.remove_file(docx_path) catch { _ => () }
}

///|
test "docx: expand_archive excludes structural and binary parts" {
  let dir = docx_temp_dir("excludes")
  @fs.create_dir(dir)
  let docx_path = dir + "/test.docx"
  let fixture = build_docx_fixture()
  write_fixture_to_disk(docx_path, fixture)
  let entries = expand_archive(docx_path, docx_archive_spec())
  let entry_names : Array[String] = []
  for e in entries {
    entry_names.push(inner_path(e.virtual_path))
  }
  let excluded = expected_excluded_parts()
  for part in excluded {
    for name in entry_names {
      assert_true(
        name != part,
        msg="excluded part was incorrectly included: " + part,
      )
    }
  }
  // Cleanup
  @fs.remove_file(docx_path) catch { _ => () }
}

///|
test "docx: expand_archive returns correct entry count" {
  let dir = docx_temp_dir("count")
  @fs.create_dir(dir)
  let docx_path = dir + "/test.docx"
  let fixture = build_docx_fixture()
  write_fixture_to_disk(docx_path, fixture)
  let entries = expand_archive(docx_path, docx_archive_spec())
  let expected_count = expected_included_parts().length()
  assert_eq(entries.length(), expected_count)
  // Cleanup
  @fs.remove_file(docx_path) catch { _ => () }
}

///|
test "docx: all text entries are UTF-8 decodable" {
  let dir = docx_temp_dir("utf8")
  @fs.create_dir(dir)
  let docx_path = dir + "/test.docx"
  let fixture = build_docx_fixture()
  write_fixture_to_disk(docx_path, fixture)
  let entries = expand_archive(docx_path, docx_archive_spec())
  for e in entries {
    // All entries from our fixture are text XML — none should be binary
    assert_true(
      !e.is_binary,
      msg="entry should be text but was marked binary: " + e.virtual_path,
    )
    // Content must be non-empty
    assert_true(
      e.content.length() > 0,
      msg="entry content is empty: " + e.virtual_path,
    )
    // Content must contain XML declaration
    assert_true(
      e.content.contains("<?xml"),
      msg="entry missing XML declaration: " + e.virtual_path,
    )
  }
  // Cleanup
  @fs.remove_file(docx_path) catch { _ => () }
}

///|
test "docx: virtual paths use archive separator" {
  let dir = docx_temp_dir("vpath")
  @fs.create_dir(dir)
  let docx_path = dir + "/test.docx"
  let fixture = build_docx_fixture()
  write_fixture_to_disk(docx_path, fixture)
  let entries = expand_archive(docx_path, docx_archive_spec())
  for e in entries {
    // Virtual path must contain the archive separator "!/"
    assert_true(
      e.virtual_path.contains("!/"),
      msg="virtual path missing archive separator: " + e.virtual_path,
    )
    // archive_source must be set to the docx path
    match e.archive_source {
      Some(src) => assert_eq(src, docx_path)
      None =>
        assert_true(
          false,
          msg="archive_source should be Some for archive entry: " + e.virtual_path,
        )
    }
    // parse_virtual_path must correctly decompose
    let (archive_part, inner_opt) = parse_virtual_path(e.virtual_path)
    assert_eq(archive_part, docx_path)
    match inner_opt {
      Some(inner) =>
        assert_true(
          inner.length() > 0,
          msg="inner path should be non-empty for: " + e.virtual_path,
        )
      None =>
        assert_true(
          false,
          msg="parse_virtual_path should return Some inner for archive entry",
        )
    }
  }
  // Cleanup
  @fs.remove_file(docx_path) catch { _ => () }
}

///|
test "docx: document.xml contains expected paragraph text" {
  let dir = docx_temp_dir("content")
  @fs.create_dir(dir)
  let docx_path = dir + "/test.docx"
  let fixture = build_docx_fixture()
  write_fixture_to_disk(docx_path, fixture)
  let entries = expand_archive(docx_path, docx_archive_spec())
  let mut doc_content = ""
  for e in entries {
    if inner_path(e.virtual_path) == "word/document.xml" {
      doc_content = e.content
      break
    }
  }
  assert_true(doc_content.contains("main document body"))
  assert_true(doc_content.contains("Second paragraph"))
  assert_true(doc_content.contains("<w:document"))
  assert_true(doc_content.contains(wml_ns))
  // Cleanup
  @fs.remove_file(docx_path) catch { _ => () }
}

///|
test "docx: header and footer content is accessible" {
  let dir = docx_temp_dir("hdrftr")
  @fs.create_dir(dir)
  let docx_path = dir + "/test.docx"
  let fixture = build_docx_fixture()
  write_fixture_to_disk(docx_path, fixture)
  let entries = expand_archive(docx_path, docx_archive_spec())
  let mut header_count = 0
  let mut footer_count = 0
  for e in entries {
    let inner = inner_path(e.virtual_path)
    if @glob.glob_match(inner, "word/header*.xml") {
      header_count += 1
      assert_true(e.content.contains("<w:hdr"))
      assert_true(e.content.contains("Header"))
    }
    if @glob.glob_match(inner, "word/footer*.xml") {
      footer_count += 1
      assert_true(e.content.contains("<w:ftr"))
      assert_true(e.content.contains("Footer"))
    }
  }
  assert_eq(header_count, 3)
  assert_eq(footer_count, 3)
  // Cleanup
  @fs.remove_file(docx_path) catch { _ => () }
}

///|
test "docx: comments and notes are included with content" {
  let dir = docx_temp_dir("notes")
  @fs.create_dir(dir)
  let docx_path = dir + "/test.docx"
  let fixture = build_docx_fixture()
  write_fixture_to_disk(docx_path, fixture)
  let entries = expand_archive(docx_path, docx_archive_spec())
  let mut found_footnotes = false
  let mut found_endnotes = false
  let mut found_comments = false
  let mut found_comments_ext = false
  for e in entries {
    let inner = inner_path(e.virtual_path)
    if inner == "word/footnotes.xml" {
      found_footnotes = true
      assert_true(e.content.contains("footnote with additional context"))
    }
    if inner == "word/endnotes.xml" {
      found_endnotes = true
      assert_true(e.content.contains("endnote reference"))
    }
    if inner == "word/comments.xml" {
      found_comments = true
      assert_true(e.content.contains("review this section"))
      assert_true(e.content.contains("w:author=\"Reviewer\""))
    }
    if inner == "word/commentsExtended.xml" {
      found_comments_ext = true
      assert_true(e.content.contains("w15:commentEx"))
    }
  }
  assert_true(found_footnotes)
  assert_true(found_endnotes)
  assert_true(found_comments)
  assert_true(found_comments_ext)
  // Cleanup
  @fs.remove_file(docx_path) catch { _ => () }
}

///|
test "docx: numbering and styles definitions are included" {
  let dir = docx_temp_dir("defs")
  @fs.create_dir(dir)
  let docx_path = dir + "/test.docx"
  let fixture = build_docx_fixture()
  write_fixture_to_disk(docx_path, fixture)
  let entries = expand_archive(docx_path, docx_archive_spec())
  let mut found_numbering = false
  let mut found_styles = false
  for e in entries {
    let inner = inner_path(e.virtual_path)
    if inner == "word/numbering.xml" {
      found_numbering = true
      assert_true(e.content.contains("w:abstractNum"))
      assert_true(e.content.contains("decimal"))
    }
    if inner == "word/styles.xml" {
      found_styles = true
      assert_true(e.content.contains("Normal"))
      assert_true(e.content.contains("heading 1"))
    }
  }
  assert_true(found_numbering)
  assert_true(found_styles)
  // Cleanup
  @fs.remove_file(docx_path) catch { _ => () }
}

///|
test "docx: glossary document is included" {
  let dir = docx_temp_dir("glossary")
  @fs.create_dir(dir)
  let docx_path = dir + "/test.docx"
  let fixture = build_docx_fixture()
  write_fixture_to_disk(docx_path, fixture)
  let entries = expand_archive(docx_path, docx_archive_spec())
  let mut found = false
  for e in entries {
    if inner_path(e.virtual_path) == "word/glossary/document.xml" {
      found = true
      assert_true(e.content.contains("glossaryDocument"))
      assert_true(e.content.contains("building block content"))
    }
  }
  assert_true(found, msg="word/glossary/document.xml not found in expanded entries")
  // Cleanup
  @fs.remove_file(docx_path) catch { _ => () }
}

///|
test "docx: all three docProps parts are included" {
  let dir = docx_temp_dir("props")
  @fs.create_dir(dir)
  let docx_path = dir + "/test.docx"
  let fixture = build_docx_fixture()
  write_fixture_to_disk(docx_path, fixture)
  let entries = expand_archive(docx_path, docx_archive_spec())
  let mut found_core = false
  let mut found_app = false
  let mut found_custom = false
  for e in entries {
    let inner = inner_path(e.virtual_path)
    if inner == "docProps/core.xml" {
      found_core = true
      assert_true(e.content.contains("Test Document Title"))
      assert_true(e.content.contains("Test Author"))
    }
    if inner == "docProps/app.xml" {
      found_app = true
      assert_true(e.content.contains("indexion test suite"))
    }
    if inner == "docProps/custom.xml" {
      found_custom = true
      assert_true(e.content.contains("indexion"))
    }
  }
  assert_true(found_core, msg="docProps/core.xml not found")
  assert_true(found_app, msg="docProps/app.xml not found")
  assert_true(found_custom, msg="docProps/custom.xml not found")
  // Cleanup
  @fs.remove_file(docx_path) catch { _ => () }
}

///|
test "docx: glossary _rels are excluded" {
  let dir = docx_temp_dir("glossary-rels")
  @fs.create_dir(dir)
  let docx_path = dir + "/test.docx"
  let fixture = build_docx_fixture()
  write_fixture_to_disk(docx_path, fixture)
  let entries = expand_archive(docx_path, docx_archive_spec())
  for e in entries {
    let inner = inner_path(e.virtual_path)
    assert_true(
      !@glob.glob_match(inner, "word/glossary/_rels/*"),
      msg="glossary _rels should be excluded: " + inner,
    )
    assert_true(
      !@glob.glob_match(inner, "word/_rels/*"),
      msg="word _rels should be excluded: " + inner,
    )
  }
  // Cleanup
  @fs.remove_file(docx_path) catch { _ => () }
}
