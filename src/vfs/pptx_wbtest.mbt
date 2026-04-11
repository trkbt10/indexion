///|
/// Test fixture helpers for PPTX (ECMA-376 PresentationML) archive expansion.
/// Creates a realistic PPTX structure programmatically using fzip,
/// then verifies that VFS correctly includes/excludes entries per KGF spec.

///|
/// Convert a MoonBit String to FixedArray[Byte] via fzip's UTF-8 encoder.
fn string_to_bytes(s : String) -> FixedArray[Byte] {
  @fzip.str_to_u8(s)
}

///|
/// Build a temporary directory path for test fixtures.
fn pptx_test_dir(suffix : String) -> String {
  let base = match @config.get_global_cache_dir() {
    Some(dir) => dir + "/indexion-test"
    None => "/tmp/indexion-test"
  }
  base + "/pptx-" + suffix
}

///|
/// Minimal [Content_Types].xml — structural, should be EXCLUDED.
fn content_types_xml() -> String {
  #|<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
  #|<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  #|  <Default Extension="xml" ContentType="application/xml"/>
  #|  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  #|  <Override PartName="/ppt/presentation.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml"/>
  #|  <Override PartName="/ppt/slides/slide1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slide+xml"/>
  #|  <Override PartName="/ppt/slides/slide2.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slide+xml"/>
  #|  <Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>
  #|</Types>
  #|
}

///|
/// Top-level .rels — structural, should be EXCLUDED.
fn top_rels_xml() -> String {
  #|<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
  #|<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  #|  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="ppt/presentation.xml"/>
  #|  <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>
  #|</Relationships>
  #|
}

///|
/// ppt/_rels/presentation.xml.rels — structural, should be EXCLUDED.
fn presentation_rels_xml() -> String {
  #|<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
  #|<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  #|  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide" Target="slides/slide1.xml"/>
  #|  <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide" Target="slides/slide2.xml"/>
  #|  <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster" Target="slideMasters/slideMaster1.xml"/>
  #|</Relationships>
  #|
}

///|
/// ppt/slides/_rels/slide1.xml.rels — structural, should be EXCLUDED.
fn slide_rels_xml() -> String {
  #|<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
  #|<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  #|  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout" Target="../slideLayouts/slideLayout1.xml"/>
  #|  <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/notesSlide" Target="../notesSlides/notesSlide1.xml"/>
  #|</Relationships>
  #|
}

///|
/// ppt/presentation.xml — presentation metadata with slide order.
fn presentation_xml() -> String {
  #|<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
  #|<p:presentation xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"
  #|    xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"
  #|    xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">
  #|  <p:sldMasterIdLst>
  #|    <p:sldMasterId id="2147483648" r:id="rId3"/>
  #|  </p:sldMasterIdLst>
  #|  <p:sldIdLst>
  #|    <p:sldId id="256" r:id="rId1"/>
  #|    <p:sldId id="257" r:id="rId2"/>
  #|  </p:sldIdLst>
  #|  <p:sldSz cx="9144000" cy="6858000"/>
  #|  <p:notesSz cx="6858000" cy="9144000"/>
  #|</p:presentation>
  #|
}

///|
/// A slide XML with realistic text runs following ECMA-376 DrawingML.
fn slide_xml(title : String, body_text : String) -> String {
  let buf = StringBuilder::new()
  buf.write_string(
    #|<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    ,
  )
  buf.write_string("\n")
  buf.write_string(
    #|<p:sld xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"
    ,
  )
  buf.write_string("\n")
  buf.write_string(
    #|    xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"
    ,
  )
  buf.write_string("\n")
  buf.write_string(
    #|    xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">
    ,
  )
  buf.write_string("\n")
  buf.write_string("  <p:cSld>\n")
  buf.write_string("    <p:spTree>\n")
  buf.write_string("      <p:sp>\n")
  buf.write_string("        <p:txBody>\n")
  buf.write_string("          <a:p>\n")
  buf.write_string("            <a:r>\n")
  buf.write_string("              <a:t>")
  buf.write_string(title)
  buf.write_string("</a:t>\n")
  buf.write_string("            </a:r>\n")
  buf.write_string("          </a:p>\n")
  buf.write_string("        </p:txBody>\n")
  buf.write_string("      </p:sp>\n")
  buf.write_string("      <p:sp>\n")
  buf.write_string("        <p:txBody>\n")
  buf.write_string("          <a:p>\n")
  buf.write_string("            <a:r>\n")
  buf.write_string("              <a:t>")
  buf.write_string(body_text)
  buf.write_string("</a:t>\n")
  buf.write_string("            </a:r>\n")
  buf.write_string("          </a:p>\n")
  buf.write_string("        </p:txBody>\n")
  buf.write_string("      </p:sp>\n")
  buf.write_string("    </p:spTree>\n")
  buf.write_string("  </p:cSld>\n")
  buf.write_string("</p:sld>\n")
  buf.to_string()
}

///|
/// A notes slide XML with speaker notes text.
fn notes_slide_xml(notes_text : String) -> String {
  let buf = StringBuilder::new()
  buf.write_string(
    #|<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    ,
  )
  buf.write_string("\n")
  buf.write_string(
    #|<p:notes xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"
    ,
  )
  buf.write_string("\n")
  buf.write_string(
    #|    xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">
    ,
  )
  buf.write_string("\n")
  buf.write_string("  <p:cSld>\n")
  buf.write_string("    <p:spTree>\n")
  buf.write_string("      <p:sp>\n")
  buf.write_string("        <p:txBody>\n")
  buf.write_string("          <a:p>\n")
  buf.write_string("            <a:r>\n")
  buf.write_string("              <a:t>")
  buf.write_string(notes_text)
  buf.write_string("</a:t>\n")
  buf.write_string("            </a:r>\n")
  buf.write_string("          </a:p>\n")
  buf.write_string("        </p:txBody>\n")
  buf.write_string("      </p:sp>\n")
  buf.write_string("    </p:spTree>\n")
  buf.write_string("  </p:cSld>\n")
  buf.write_string("</p:notes>\n")
  buf.to_string()
}

///|
/// Slide master XML with template text placeholders.
fn slide_master_xml() -> String {
  #|<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
  #|<p:sldMaster xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"
  #|    xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"
  #|    xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  #|  <p:cSld>
  #|    <p:spTree>
  #|      <p:sp>
  #|        <p:txBody>
  #|          <a:p>
  #|            <a:r>
  #|              <a:t>Click to edit Master title style</a:t>
  #|            </a:r>
  #|          </a:p>
  #|        </p:txBody>
  #|      </p:sp>
  #|    </p:spTree>
  #|  </p:cSld>
  #|</p:sldMaster>
  #|
}

///|
/// Slide layout XML with layout definition.
fn slide_layout_xml() -> String {
  #|<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
  #|<p:sldLayout xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"
  #|    xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"
  #|    xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"
  #|    type="title" preserve="1">
  #|  <p:cSld name="Title Slide">
  #|    <p:spTree>
  #|      <p:sp>
  #|        <p:txBody>
  #|          <a:p>
  #|            <a:r>
  #|              <a:t>Title Layout Placeholder</a:t>
  #|            </a:r>
  #|          </a:p>
  #|        </p:txBody>
  #|      </p:sp>
  #|    </p:spTree>
  #|  </p:cSld>
  #|</p:sldLayout>
  #|
}

///|
/// Comment XML following ECMA-376 comment schema.
fn comment_xml() -> String {
  #|<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
  #|<p:cmLst xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">
  #|  <p:cm authorId="0" dt="2024-01-15T10:30:00Z" idx="1">
  #|    <p:pos x="100" y="200"/>
  #|    <p:text>This slide needs more detail on the architecture diagram.</p:text>
  #|  </p:cm>
  #|</p:cmLst>
  #|
}

///|
/// Comment authors XML.
fn comment_authors_xml() -> String {
  #|<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
  #|<p:cmAuthorLst xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">
  #|  <p:cmAuthor id="0" name="Reviewer" initials="R" lastIdx="1" clrIdx="0"/>
  #|</p:cmAuthorLst>
  #|
}

///|
/// Handout master XML.
fn handout_master_xml() -> String {
  #|<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
  #|<p:handoutMaster xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"
  #|    xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">
  #|  <p:cSld>
  #|    <p:spTree>
  #|      <p:sp>
  #|        <p:txBody>
  #|          <a:p>
  #|            <a:r>
  #|              <a:t>Handout Header Text</a:t>
  #|            </a:r>
  #|          </a:p>
  #|        </p:txBody>
  #|      </p:sp>
  #|    </p:spTree>
  #|  </p:cSld>
  #|</p:handoutMaster>
  #|
}

///|
/// Custom tag XML.
fn tag_xml() -> String {
  #|<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
  #|<p:tagLst xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">
  #|  <p:tag name="DEPARTMENT" val="Engineering"/>
  #|  <p:tag name="CONFIDENTIALITY" val="Internal"/>
  #|</p:tagLst>
  #|
}

///|
/// Dublin Core metadata (docProps/core.xml).
fn doc_props_core_xml() -> String {
  #|<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
  #|<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties"
  #|    xmlns:dc="http://purl.org/dc/elements/1.1/"
  #|    xmlns:dcterms="http://purl.org/dc/terms/"
  #|    xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
  #|  <dc:title>Quarterly Architecture Review</dc:title>
  #|  <dc:creator>Test Author</dc:creator>
  #|  <dc:subject>Software Architecture</dc:subject>
  #|  <dc:description>A comprehensive review of system architecture decisions.</dc:description>
  #|  <dcterms:created xsi:type="dcterms:W3CDTF">2024-01-01T00:00:00Z</dcterms:created>
  #|  <dcterms:modified xsi:type="dcterms:W3CDTF">2024-06-15T14:30:00Z</dcterms:modified>
  #|</cp:coreProperties>
  #|
}

///|
/// Application metadata (docProps/app.xml).
fn doc_props_app_xml() -> String {
  #|<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
  #|<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties">
  #|  <Application>Microsoft Office PowerPoint</Application>
  #|  <Slides>2</Slides>
  #|  <HiddenSlides>0</HiddenSlides>
  #|  <Notes>1</Notes>
  #|  <TotalTime>45</TotalTime>
  #|  <Company>Test Corp</Company>
  #|</Properties>
  #|
}

///|
/// Custom properties (docProps/custom.xml).
fn doc_props_custom_xml() -> String {
  #|<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
  #|<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/custom-properties"
  #|    xmlns:vt="http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes">
  #|  <property fmtid="{D5CDD505-2E9C-101B-9397-08002B2CF9AE}" pid="2" name="ReviewStatus">
  #|    <vt:lpwstr>Draft</vt:lpwstr>
  #|  </property>
  #|</Properties>
  #|
}

///|
/// Notes slide rels — structural, should be EXCLUDED.
fn notes_slide_rels_xml() -> String {
  #|<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
  #|<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  #|  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide" Target="../slides/slide1.xml"/>
  #|</Relationships>
  #|
}

///|
/// Slide master rels — structural, should be EXCLUDED.
fn slide_master_rels_xml() -> String {
  #|<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
  #|<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  #|  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout" Target="../slideLayouts/slideLayout1.xml"/>
  #|</Relationships>
  #|
}

///|
/// Slide layout rels — structural, should be EXCLUDED.
fn slide_layout_rels_xml() -> String {
  #|<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
  #|<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  #|  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster" Target="../slideMasters/slideMaster1.xml"/>
  #|</Relationships>
  #|
}

///|
/// Comment rels — structural, should be EXCLUDED.
fn comment_rels_xml() -> String {
  #|<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
  #|<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  #|</Relationships>
  #|
}

///|
/// Handout master rels — structural, should be EXCLUDED.
fn handout_master_rels_xml() -> String {
  #|<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
  #|<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  #|</Relationships>
  #|
}

///|
/// Build a complete PPTX fixture as a ZIP byte array.
/// Contains all ECMA-376 PresentationML parts: slides, notes, masters,
/// layouts, comments, tags, handouts, docProps, plus structural files
/// that should be excluded by the KGF spec.
fn build_pptx_fixture() -> FixedArray[Byte] {
  let files : Array[(String, FixedArray[Byte])] = []
  // --- Structural files (should be EXCLUDED) ---
  files.push(("[Content_Types].xml", string_to_bytes(content_types_xml())))
  files.push(("_rels/.rels", string_to_bytes(top_rels_xml())))
  files.push(
    (
      "ppt/_rels/presentation.xml.rels",
      string_to_bytes(presentation_rels_xml()),
    ),
  )
  files.push(
    (
      "ppt/slides/_rels/slide1.xml.rels",
      string_to_bytes(slide_rels_xml()),
    ),
  )
  files.push(
    (
      "ppt/slides/_rels/slide2.xml.rels",
      string_to_bytes(slide_rels_xml()),
    ),
  )
  files.push(
    (
      "ppt/notesSlides/_rels/notesSlide1.xml.rels",
      string_to_bytes(notes_slide_rels_xml()),
    ),
  )
  files.push(
    (
      "ppt/slideMasters/_rels/slideMaster1.xml.rels",
      string_to_bytes(slide_master_rels_xml()),
    ),
  )
  files.push(
    (
      "ppt/slideLayouts/_rels/slideLayout1.xml.rels",
      string_to_bytes(slide_layout_rels_xml()),
    ),
  )
  files.push(
    (
      "ppt/comments/_rels/comment1.xml.rels",
      string_to_bytes(comment_rels_xml()),
    ),
  )
  files.push(
    (
      "ppt/handoutMasters/_rels/handoutMaster1.xml.rels",
      string_to_bytes(handout_master_rels_xml()),
    ),
  )
  // --- Document-relevant content (should be INCLUDED) ---
  files.push(("ppt/presentation.xml", string_to_bytes(presentation_xml())))
  files.push(
    (
      "ppt/slides/slide1.xml",
      string_to_bytes(
        slide_xml(
          "Architecture Overview",
          "This slide presents the high-level system architecture.",
        ),
      ),
    ),
  )
  files.push(
    (
      "ppt/slides/slide2.xml",
      string_to_bytes(
        slide_xml(
          "Performance Metrics",
          "Key performance indicators and benchmarks for Q4.",
        ),
      ),
    ),
  )
  files.push(
    (
      "ppt/notesSlides/notesSlide1.xml",
      string_to_bytes(
        notes_slide_xml(
          "Remember to discuss the migration timeline with the team.",
        ),
      ),
    ),
  )
  files.push(
    (
      "ppt/slideMasters/slideMaster1.xml",
      string_to_bytes(slide_master_xml()),
    ),
  )
  files.push(
    (
      "ppt/slideLayouts/slideLayout1.xml",
      string_to_bytes(slide_layout_xml()),
    ),
  )
  files.push(
    ("ppt/comments/comment1.xml", string_to_bytes(comment_xml())),
  )
  files.push(
    ("ppt/commentAuthors.xml", string_to_bytes(comment_authors_xml())),
  )
  files.push(
    (
      "ppt/handoutMasters/handoutMaster1.xml",
      string_to_bytes(handout_master_xml()),
    ),
  )
  files.push(("ppt/tags/tag1.xml", string_to_bytes(tag_xml())))
  files.push(("docProps/core.xml", string_to_bytes(doc_props_core_xml())))
  files.push(("docProps/app.xml", string_to_bytes(doc_props_app_xml())))
  files.push(
    ("docProps/custom.xml", string_to_bytes(doc_props_custom_xml())),
  )
  @fzip.zip_sync(files)
}

///|
/// Write a FixedArray[Byte] to a file path.
fn write_fixture_to_file(
  path : String,
  data : FixedArray[Byte],
) -> Unit raise Error {
  let len = data.length()
  let arr : Array[Byte] = Array::new(capacity=len)
  for i in 0..<len {
    arr.push(data[i])
  }
  @fs.write_bytes_to_file(path, Bytes::from_array(arr))
}

///|
/// Ensure a directory exists, creating it recursively if needed.
fn ensure_dir(path : String) -> Unit raise Error {
  if not(@fs.path_exists(path)) {
    @fs.create_dir(path)
  }
}

///|
/// The set of inner paths that the PPTX KGF spec should INCLUDE.
fn expected_included_paths() -> Array[String] {
  [
    "ppt/presentation.xml",
    "ppt/slides/slide1.xml",
    "ppt/slides/slide2.xml",
    "ppt/notesSlides/notesSlide1.xml",
    "ppt/slideMasters/slideMaster1.xml",
    "ppt/slideLayouts/slideLayout1.xml",
    "ppt/comments/comment1.xml",
    "ppt/commentAuthors.xml",
    "ppt/handoutMasters/handoutMaster1.xml",
    "ppt/tags/tag1.xml",
    "docProps/core.xml",
    "docProps/app.xml",
    "docProps/custom.xml",
  ]
}

///|
/// The set of inner paths that the PPTX KGF spec should EXCLUDE.
fn expected_excluded_paths() -> Array[String] {
  [
    "[Content_Types].xml",
    "_rels/.rels",
    "ppt/_rels/presentation.xml.rels",
    "ppt/slides/_rels/slide1.xml.rels",
    "ppt/slides/_rels/slide2.xml.rels",
    "ppt/notesSlides/_rels/notesSlide1.xml.rels",
    "ppt/slideMasters/_rels/slideMaster1.xml.rels",
    "ppt/slideLayouts/_rels/slideLayout1.xml.rels",
    "ppt/comments/_rels/comment1.xml.rels",
    "ppt/handoutMasters/_rels/handoutMaster1.xml.rels",
  ]
}

///|
/// Build the ArchiveSpec matching the current pptx.kgf configuration.
fn pptx_archive_spec() -> ArchiveSpec {
  {
    inner_includes: [
      "ppt/slides/slide*.xml",
      "ppt/notesSlides/notesSlide*.xml",
      "ppt/slideMasters/slideMaster*.xml",
      "ppt/slideLayouts/slideLayout*.xml",
      "ppt/presentation.xml",
      "ppt/comments/comment*.xml",
      "ppt/commentAuthors.xml",
      "ppt/handoutMasters/handoutMaster*.xml",
      "ppt/tags/tag*.xml",
      "docProps/core.xml",
      "docProps/app.xml",
      "docProps/custom.xml",
    ],
    inner_excludes: [
      "ppt/_rels/*",
      "ppt/slides/_rels/*",
      "ppt/notesSlides/_rels/*",
      "ppt/slideMasters/_rels/*",
      "ppt/slideLayouts/_rels/*",
      "ppt/comments/_rels/*",
      "ppt/handoutMasters/_rels/*",
    ],
  }
}

///|
/// Verify expand_archive returns exactly the expected included entries.
test "pptx: expand_archive includes all document-relevant parts" {
  let test_dir = pptx_test_dir("expand-includes")
  ensure_dir!(test_dir)
  let pptx_path = test_dir + "/fixture.pptx"
  let zip_data = build_pptx_fixture()
  write_fixture_to_file!(pptx_path, zip_data)
  let spec = pptx_archive_spec()
  let entries = expand_archive!(pptx_path, spec)
  let entry_inner_paths : Array[String] = []
  for e in entries {
    // Extract the inner path after the "!/" separator
    entry_inner_paths.push(inner_path(e.virtual_path))
  }
  let expected = expected_included_paths()
  // Verify count matches
  assert_eq!(entries.length(), expected.length())
  // Verify every expected path is present
  for exp in expected {
    let mut found = false
    for actual in entry_inner_paths {
      if actual == exp {
        found = true
        break
      }
    }
    assert_true!(found)
  }
}

///|
/// Verify expand_archive excludes all structural/relationship files.
test "pptx: expand_archive excludes structural rels and content types" {
  let test_dir = pptx_test_dir("expand-excludes")
  ensure_dir!(test_dir)
  let pptx_path = test_dir + "/fixture.pptx"
  let zip_data = build_pptx_fixture()
  write_fixture_to_file!(pptx_path, zip_data)
  let spec = pptx_archive_spec()
  let entries = expand_archive!(pptx_path, spec)
  let excluded = expected_excluded_paths()
  for e in entries {
    let ip = inner_path(e.virtual_path)
    for ex in excluded {
      // No entry's inner path should match any excluded path
      assert_true!(ip != ex)
    }
  }
}

///|
/// Verify that all included entries are valid UTF-8 text (not binary).
test "pptx: all document entries are UTF-8 text" {
  let test_dir = pptx_test_dir("utf8-check")
  ensure_dir!(test_dir)
  let pptx_path = test_dir + "/fixture.pptx"
  let zip_data = build_pptx_fixture()
  write_fixture_to_file!(pptx_path, zip_data)
  let spec = pptx_archive_spec()
  let entries = expand_archive!(pptx_path, spec)
  for e in entries {
    // All XML entries should be decoded as text, not binary
    assert_false!(e.is_binary)
    // Content should be non-empty
    assert_true!(e.content.length() > 0)
  }
}

///|
/// Verify virtual paths use the "!/" separator correctly.
test "pptx: virtual paths use archive separator" {
  let test_dir = pptx_test_dir("vpath-separator")
  ensure_dir!(test_dir)
  let pptx_path = test_dir + "/fixture.pptx"
  let zip_data = build_pptx_fixture()
  write_fixture_to_file!(pptx_path, zip_data)
  let spec = pptx_archive_spec()
  let entries = expand_archive!(pptx_path, spec)
  for e in entries {
    // Every virtual path must start with the archive path + "!/"
    let expected_prefix = pptx_path + "!/"
    let prefix_len = expected_prefix.length()
    assert_true!(e.virtual_path.length() > prefix_len)
    let actual_prefix = e.virtual_path[:prefix_len].to_string()
    assert_eq!(actual_prefix, expected_prefix)
    // parse_virtual_path should decompose correctly
    let (archive_part, inner_opt) = parse_virtual_path(e.virtual_path)
    assert_eq!(archive_part, pptx_path)
    match inner_opt {
      Some(ip) => assert_true!(ip.length() > 0)
      None => assert_true!(false)
    }
    // archive_source should be set
    assert_eq!(e.archive_source, Some(pptx_path))
  }
}

///|
/// Verify slide content contains expected text runs.
test "pptx: slide content contains expected text" {
  let test_dir = pptx_test_dir("slide-content")
  ensure_dir!(test_dir)
  let pptx_path = test_dir + "/fixture.pptx"
  let zip_data = build_pptx_fixture()
  write_fixture_to_file!(pptx_path, zip_data)
  let spec = pptx_archive_spec()
  let entries = expand_archive!(pptx_path, spec)
  // Find slide1 and verify its content
  for e in entries {
    let ip = inner_path(e.virtual_path)
    if ip == "ppt/slides/slide1.xml" {
      assert_true!(e.content.contains("Architecture Overview"))
      assert_true!(
        e.content.contains(
          "This slide presents the high-level system architecture.",
        ),
      )
      assert_true!(e.content.contains("<a:t>"))
    }
    if ip == "ppt/slides/slide2.xml" {
      assert_true!(e.content.contains("Performance Metrics"))
    }
    if ip == "ppt/notesSlides/notesSlide1.xml" {
      assert_true!(
        e.content.contains(
          "Remember to discuss the migration timeline with the team.",
        ),
      )
    }
    if ip == "docProps/core.xml" {
      assert_true!(e.content.contains("Quarterly Architecture Review"))
      assert_true!(e.content.contains("Test Author"))
    }
    if ip == "ppt/comments/comment1.xml" {
      assert_true!(
        e.content.contains(
          "This slide needs more detail on the architecture diagram.",
        ),
      )
    }
    if ip == "ppt/tags/tag1.xml" {
      assert_true!(e.content.contains("DEPARTMENT"))
      assert_true!(e.content.contains("Engineering"))
    }
    if ip == "docProps/app.xml" {
      assert_true!(e.content.contains("<Slides>2</Slides>"))
    }
  }
}

///|
/// Verify that the glob patterns in the KGF spec correctly match
/// the expected inner paths (unit test for pattern correctness).
test "pptx: kgf glob patterns match expected paths" {
  let spec = pptx_archive_spec()
  let included = expected_included_paths()
  let excluded = expected_excluded_paths()
  // Every included path must match at least one include pattern
  // and must not match any exclude pattern
  for path in included {
    let mut matches_include = false
    for pattern in spec.inner_includes {
      if @glob.glob_match(path, pattern) {
        matches_include = true
        break
      }
    }
    assert_true!(matches_include)
    for pattern in spec.inner_excludes {
      assert_false!(@glob.glob_match(path, pattern))
    }
  }
  // Every excluded path must either not match any include pattern
  // or must match at least one exclude pattern
  for path in excluded {
    let mut matches_include = false
    for pattern in spec.inner_includes {
      if @glob.glob_match(path, pattern) {
        matches_include = true
        break
      }
    }
    if matches_include {
      // If it matches an include, it must also match an exclude
      let mut matches_exclude = false
      for pattern in spec.inner_excludes {
        if @glob.glob_match(path, pattern) {
          matches_exclude = true
          break
        }
      }
      assert_true!(matches_exclude)
    }
    // If it doesn't match any include, it's excluded by omission — fine
  }
}
