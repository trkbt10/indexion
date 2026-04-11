///|
/// XLSX (ECMA-376 SpreadsheetML) archive expansion test.
/// Validates that VFS correctly extracts document-relevant parts
/// and excludes structural/relationship parts from XLSX archives.

///|
/// Convert a FixedArray[Byte] (from fzip) to Bytes (for fs write).
fn fixed_to_bytes(fa : FixedArray[Byte]) -> Bytes {
  let arr : Array[Byte] = []
  for i in 0..<fa.length() {
    arr.push(fa[i])
  }
  Bytes::from_array(arr)
}

///|
/// Create a unique temporary directory for this test run.
fn xlsx_test_dir() -> String {
  let dir = "/tmp/indexion-vfs-xlsx/" + @env.now().to_string()
  @config.ensure_dir_recursive(dir)
  dir
}

///|
/// Build a realistic XLSX ZIP archive in memory.
/// Contains ECMA-376 SpreadsheetML parts covering all document-relevant
/// content types plus structural parts that should be excluded.
fn build_xlsx_fixture() -> FixedArray[Byte] {
  let files : Array[(String, FixedArray[Byte])] = []
  // --- Parts that SHOULD be included ---
  // Worksheet with cell data and formulas
  files.push(
    (
      "xl/worksheets/sheet1.xml",
      @fzip.str_to_u8(
        #|<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        #|<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"
        #|  xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
        #|  <sheetData>
        #|    <row r="1" spans="1:3">
        #|      <c r="A1" t="s"><v>0</v></c>
        #|      <c r="B1" t="s"><v>1</v></c>
        #|      <c r="C1" t="s"><v>2</v></c>
        #|    </row>
        #|    <row r="2" spans="1:3">
        #|      <c r="A2"><v>100</v></c>
        #|      <c r="B2"><v>200</v></c>
        #|      <c r="C2"><f>SUM(A2:B2)</f><v>300</v></c>
        #|    </row>
        #|    <row r="3" spans="1:3">
        #|      <c r="A3"><v>150</v></c>
        #|      <c r="B3"><v>250</v></c>
        #|      <c r="C3"><f>SUM(A3:B3)</f><v>400</v></c>
        #|    </row>
        #|  </sheetData>
        #|</worksheet>
        ,
      ),
    ),
  )
  // Second worksheet
  files.push(
    (
      "xl/worksheets/sheet2.xml",
      @fzip.str_to_u8(
        #|<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        #|<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
        #|  <sheetData>
        #|    <row r="1" spans="1:1">
        #|      <c r="A1" t="s"><v>3</v></c>
        #|    </row>
        #|  </sheetData>
        #|</worksheet>
        ,
      ),
    ),
  )
  // Shared strings table (all text cell values reference this)
  files.push(
    (
      "xl/sharedStrings.xml",
      @fzip.str_to_u8(
        #|<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        #|<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"
        #|  count="4" uniqueCount="4">
        #|  <si><t>Revenue</t></si>
        #|  <si><t>Cost</t></si>
        #|  <si><t>Profit</t></si>
        #|  <si><t>Summary Sheet</t></si>
        #|</sst>
        ,
      ),
    ),
  )
  // Workbook (sheet names, defined names)
  files.push(
    (
      "xl/workbook.xml",
      @fzip.str_to_u8(
        #|<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        #|<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"
        #|  xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
        #|  <sheets>
        #|    <sheet name="Financial Data" sheetId="1" r:id="rId1"/>
        #|    <sheet name="Summary" sheetId="2" r:id="rId2"/>
        #|  </sheets>
        #|  <definedNames>
        #|    <definedName name="TotalRevenue">'Financial Data'!$A$2:$A$3</definedName>
        #|  </definedNames>
        #|</workbook>
        ,
      ),
    ),
  )
  // Cell comments
  files.push(
    (
      "xl/comments1.xml",
      @fzip.str_to_u8(
        #|<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        #|<comments xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
        #|  <authors><author>Analyst</author></authors>
        #|  <commentList>
        #|    <comment ref="A1" authorId="0">
        #|      <text><r><t>This column contains quarterly revenue figures.</t></r></text>
        #|    </comment>
        #|  </commentList>
        #|</comments>
        ,
      ),
    ),
  )
  // Threaded comments (Office 365)
  files.push(
    (
      "xl/threadedComments/threadedComment1.xml",
      @fzip.str_to_u8(
        #|<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        #|<ThreadedComments xmlns="http://schemas.microsoft.com/office/spreadsheetml/2018/threadedcomments">
        #|  <threadedComment id="{A1B2C3}" ref="C2" personId="{D4E5F6}">
        #|    <text>Verify this formula matches the budget model.</text>
        #|  </threadedComment>
        #|</ThreadedComments>
        ,
      ),
    ),
  )
  // Structured table definition
  files.push(
    (
      "xl/tables/table1.xml",
      @fzip.str_to_u8(
        #|<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        #|<table xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"
        #|  id="1" name="FinancialSummary" displayName="FinancialSummary" ref="A1:C3">
        #|  <tableColumns count="3">
        #|    <tableColumn id="1" name="Revenue"/>
        #|    <tableColumn id="2" name="Cost"/>
        #|    <tableColumn id="3" name="Profit"/>
        #|  </tableColumns>
        #|</table>
        ,
      ),
    ),
  )
  // Pivot table definition
  files.push(
    (
      "xl/pivotTables/pivotTable1.xml",
      @fzip.str_to_u8(
        #|<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        #|<pivotTableDefinition xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"
        #|  name="PivotTable1" dataCaption="Values">
        #|  <location ref="E1:F5"/>
        #|  <pivotFields count="1">
        #|    <pivotField axis="axisRow" showAll="0"/>
        #|  </pivotFields>
        #|</pivotTableDefinition>
        ,
      ),
    ),
  )
  // Pivot cache definition
  files.push(
    (
      "xl/pivotCache/pivotCacheDefinition1.xml",
      @fzip.str_to_u8(
        #|<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        #|<pivotCacheDefinition xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"
        #|  r:id="rId1" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
        #|  <cacheSource type="worksheet">
        #|    <worksheetSource ref="A1:C3" sheet="Financial Data"/>
        #|  </cacheSource>
        #|</pivotCacheDefinition>
        ,
      ),
    ),
  )
  // Chart definition
  files.push(
    (
      "xl/charts/chart1.xml",
      @fzip.str_to_u8(
        #|<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        #|<c:chartSpace xmlns:c="http://schemas.openxmlformats.org/drawingml/2006/chart">
        #|  <c:chart>
        #|    <c:title><c:tx><c:rich>
        #|      <a:p xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">
        #|        <a:r><a:t>Revenue vs Cost</a:t></a:r>
        #|      </a:p>
        #|    </c:rich></c:tx></c:title>
        #|  </c:chart>
        #|</c:chartSpace>
        ,
      ),
    ),
  )
  // Calculation chain
  files.push(
    (
      "xl/calcChain.xml",
      @fzip.str_to_u8(
        #|<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        #|<calcChain xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
        #|  <c r="C2" i="1"/>
        #|  <c r="C3" i="1"/>
        #|</calcChain>
        ,
      ),
    ),
  )
  // Data connections
  files.push(
    (
      "xl/connections.xml",
      @fzip.str_to_u8(
        #|<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        #|<connections xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
        #|  <connection id="1" name="ExternalDB" type="1"
        #|    description="Connection to reporting database"/>
        #|</connections>
        ,
      ),
    ),
  )
  // Cell metadata
  files.push(
    (
      "xl/metadata.xml",
      @fzip.str_to_u8(
        #|<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        #|<metadata xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
        #|  <metadataTypes count="1">
        #|    <metadataType name="XLRICHVALUE" minSupportedVersion="120000"/>
        #|  </metadataTypes>
        #|</metadata>
        ,
      ),
    ),
  )
  // Dublin Core metadata
  files.push(
    (
      "docProps/core.xml",
      @fzip.str_to_u8(
        #|<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        #|<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties"
        #|  xmlns:dc="http://purl.org/dc/elements/1.1/"
        #|  xmlns:dcterms="http://purl.org/dc/terms/">
        #|  <dc:title>Q4 Financial Report</dc:title>
        #|  <dc:creator>Finance Team</dc:creator>
        #|  <dc:description>Quarterly financial summary with pivot analysis</dc:description>
        #|  <dcterms:created>2025-12-01T00:00:00Z</dcterms:created>
        #|</cp:coreProperties>
        ,
      ),
    ),
  )
  // Application metadata
  files.push(
    (
      "docProps/app.xml",
      @fzip.str_to_u8(
        #|<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        #|<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties">
        #|  <Application>Microsoft Excel</Application>
        #|  <AppVersion>16.0</AppVersion>
        #|  <Company>Acme Corp</Company>
        #|</Properties>
        ,
      ),
    ),
  )
  // Custom properties
  files.push(
    (
      "docProps/custom.xml",
      @fzip.str_to_u8(
        #|<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        #|<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/custom-properties"
        #|  xmlns:vt="http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes">
        #|  <property fmtid="{D5CDD505-2E9C-101B-9397-08002B2CF9AE}" pid="2" name="Department">
        #|    <vt:lpwstr>Finance</vt:lpwstr>
        #|  </property>
        #|</Properties>
        ,
      ),
    ),
  )
  // --- Parts that SHOULD be excluded ---
  // Content types (structural)
  files.push(
    (
      "[Content_Types].xml",
      @fzip.str_to_u8(
        #|<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        #|<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
        #|  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
        #|  <Default Extension="xml" ContentType="application/xml"/>
        #|  <Override PartName="/xl/workbook.xml"
        #|    ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
        #|</Types>
        ,
      ),
    ),
  )
  // Root relationships
  files.push(
    (
      "_rels/.rels",
      @fzip.str_to_u8(
        #|<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        #|<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        #|  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument"
        #|    Target="xl/workbook.xml"/>
        #|</Relationships>
        ,
      ),
    ),
  )
  // Workbook relationships
  files.push(
    (
      "xl/_rels/workbook.xml.rels",
      @fzip.str_to_u8(
        #|<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        #|<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        #|  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet"
        #|    Target="worksheets/sheet1.xml"/>
        #|  <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet"
        #|    Target="worksheets/sheet2.xml"/>
        #|</Relationships>
        ,
      ),
    ),
  )
  // Worksheet relationships (excluded by inner_excludes)
  files.push(
    (
      "xl/worksheets/_rels/sheet1.xml.rels",
      @fzip.str_to_u8(
        #|<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        #|<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        #|  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/comments"
        #|    Target="../comments1.xml"/>
        #|</Relationships>
        ,
      ),
    ),
  )
  // Styles (excluded — formatting data, not text content)
  files.push(
    (
      "xl/styles.xml",
      @fzip.str_to_u8(
        #|<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        #|<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
        #|  <numFmts count="1">
        #|    <numFmt numFmtId="164" formatCode="#,##0.00"/>
        #|  </numFmts>
        #|</styleSheet>
        ,
      ),
    ),
  )
  // Theme (excluded)
  files.push(
    (
      "xl/theme/theme1.xml",
      @fzip.str_to_u8(
        #|<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        #|<a:theme xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" name="Office Theme">
        #|  <a:themeElements/>
        #|</a:theme>
        ,
      ),
    ),
  )
  @fzip.zip_sync(files)
}

///|
/// Collect the set of inner paths (after "!/") from VFS entries.
fn collect_inner_paths(entries : Array[VFSEntry]) -> Array[String] {
  let paths : Array[String] = []
  for entry in entries {
    paths.push(inner_path(entry.virtual_path))
  }
  paths
}

///|
/// Check if a path list contains the given path.
fn has_path(paths : Array[String], target : String) -> Bool {
  for p in paths {
    if p == target {
      return true
    }
  } nobreak {
    false
  }
}

///|
/// Check that an entry with the given inner path has non-empty text content.
fn has_text_content(entries : Array[VFSEntry], target_inner : String) -> Bool {
  for entry in entries {
    if inner_path(entry.virtual_path) == target_inner {
      return !entry.is_binary && entry.content.length() > 0
    }
  } nobreak {
    false
  }
}

///|
/// Test that all ECMA-376 document-relevant parts are included.
test "xlsx: document-relevant parts are included" {
  let dir = xlsx_test_dir()
  let xlsx_path = dir + "/test_fixture.xlsx"
  let zip_data = build_xlsx_fixture()
  @fs.write_bytes_to_file(xlsx_path, fixed_to_bytes(zip_data)) catch {
    e => raise e
  }
  let spec = ArchiveSpec::{
    inner_includes: [
      "xl/worksheets/sheet*.xml",
      "xl/sharedStrings.xml",
      "xl/workbook.xml",
      "xl/comments*.xml",
      "xl/threadedComments/threadedComment*.xml",
      "xl/tables/table*.xml",
      "xl/pivotTables/pivotTable*.xml",
      "xl/pivotCache/pivotCacheDefinition*.xml",
      "xl/charts/chart*.xml",
      "xl/calcChain.xml",
      "xl/connections.xml",
      "xl/metadata.xml",
      "docProps/core.xml",
      "docProps/app.xml",
      "docProps/custom.xml",
    ],
    inner_excludes: [
      "_rels/*",
      "xl/_rels/*",
      "xl/worksheets/_rels/*",
      "[Content_Types].xml",
      "xl/styles.xml",
      "xl/theme/*",
    ],
  }
  let entries = expand_archive(xlsx_path, spec) catch { e => raise e }
  let paths = collect_inner_paths(entries)
  // Worksheets
  assert_true(has_path(paths, "xl/worksheets/sheet1.xml"))
  assert_true(has_path(paths, "xl/worksheets/sheet2.xml"))
  // Shared strings
  assert_true(has_path(paths, "xl/sharedStrings.xml"))
  // Workbook
  assert_true(has_path(paths, "xl/workbook.xml"))
  // Comments
  assert_true(has_path(paths, "xl/comments1.xml"))
  // Threaded comments
  assert_true(has_path(paths, "xl/threadedComments/threadedComment1.xml"))
  // Tables
  assert_true(has_path(paths, "xl/tables/table1.xml"))
  // Pivot tables
  assert_true(has_path(paths, "xl/pivotTables/pivotTable1.xml"))
  // Pivot cache
  assert_true(has_path(paths, "xl/pivotCache/pivotCacheDefinition1.xml"))
  // Charts
  assert_true(has_path(paths, "xl/charts/chart1.xml"))
  // Calculation chain
  assert_true(has_path(paths, "xl/calcChain.xml"))
  // Connections
  assert_true(has_path(paths, "xl/connections.xml"))
  // Metadata
  assert_true(has_path(paths, "xl/metadata.xml"))
  // Dublin Core metadata
  assert_true(has_path(paths, "docProps/core.xml"))
  // Application metadata
  assert_true(has_path(paths, "docProps/app.xml"))
  // Custom properties
  assert_true(has_path(paths, "docProps/custom.xml"))
}

///|
/// Test that structural/relationship parts are excluded.
test "xlsx: structural parts are excluded" {
  let dir = xlsx_test_dir()
  let xlsx_path = dir + "/test_excluded.xlsx"
  let zip_data = build_xlsx_fixture()
  @fs.write_bytes_to_file(xlsx_path, fixed_to_bytes(zip_data)) catch {
    e => raise e
  }
  let spec = ArchiveSpec::{
    inner_includes: [
      "xl/worksheets/sheet*.xml",
      "xl/sharedStrings.xml",
      "xl/workbook.xml",
      "xl/comments*.xml",
      "xl/threadedComments/threadedComment*.xml",
      "xl/tables/table*.xml",
      "xl/pivotTables/pivotTable*.xml",
      "xl/pivotCache/pivotCacheDefinition*.xml",
      "xl/charts/chart*.xml",
      "xl/calcChain.xml",
      "xl/connections.xml",
      "xl/metadata.xml",
      "docProps/core.xml",
      "docProps/app.xml",
      "docProps/custom.xml",
    ],
    inner_excludes: [
      "_rels/*",
      "xl/_rels/*",
      "xl/worksheets/_rels/*",
      "[Content_Types].xml",
      "xl/styles.xml",
      "xl/theme/*",
    ],
  }
  let entries = expand_archive(xlsx_path, spec) catch { e => raise e }
  let paths = collect_inner_paths(entries)
  // Content types must be excluded
  assert_false(has_path(paths, "[Content_Types].xml"))
  // Root relationships must be excluded
  assert_false(has_path(paths, "_rels/.rels"))
  // Workbook relationships must be excluded
  assert_false(has_path(paths, "xl/_rels/workbook.xml.rels"))
  // Worksheet relationships must be excluded
  assert_false(has_path(paths, "xl/worksheets/_rels/sheet1.xml.rels"))
  // Styles must be excluded (formatting, not text content)
  assert_false(has_path(paths, "xl/styles.xml"))
  // Theme must be excluded
  assert_false(has_path(paths, "xl/theme/theme1.xml"))
}

///|
/// Test that all included entries are valid UTF-8 text, not binary.
test "xlsx: all included entries are UTF-8 text" {
  let dir = xlsx_test_dir()
  let xlsx_path = dir + "/test_utf8.xlsx"
  let zip_data = build_xlsx_fixture()
  @fs.write_bytes_to_file(xlsx_path, fixed_to_bytes(zip_data)) catch {
    e => raise e
  }
  let spec = ArchiveSpec::{
    inner_includes: [
      "xl/worksheets/sheet*.xml",
      "xl/sharedStrings.xml",
      "xl/workbook.xml",
      "xl/comments*.xml",
      "xl/threadedComments/threadedComment*.xml",
      "xl/tables/table*.xml",
      "xl/pivotTables/pivotTable*.xml",
      "xl/pivotCache/pivotCacheDefinition*.xml",
      "xl/charts/chart*.xml",
      "xl/calcChain.xml",
      "xl/connections.xml",
      "xl/metadata.xml",
      "docProps/core.xml",
      "docProps/app.xml",
      "docProps/custom.xml",
    ],
    inner_excludes: [
      "_rels/*",
      "xl/_rels/*",
      "xl/worksheets/_rels/*",
      "[Content_Types].xml",
      "xl/styles.xml",
      "xl/theme/*",
    ],
  }
  let entries = expand_archive(xlsx_path, spec) catch { e => raise e }
  for entry in entries {
    // Every extracted entry should be text (XML), not binary
    assert_false(entry.is_binary)
    // Content must be non-empty
    assert_true(entry.content.length() > 0)
  }
}

///|
/// Test that virtual paths follow the "archive!/inner" convention.
test "xlsx: virtual paths use archive separator" {
  let dir = xlsx_test_dir()
  let xlsx_path = dir + "/test_vpath.xlsx"
  let zip_data = build_xlsx_fixture()
  @fs.write_bytes_to_file(xlsx_path, fixed_to_bytes(zip_data)) catch {
    e => raise e
  }
  let spec = ArchiveSpec::{
    inner_includes: [
      "xl/worksheets/sheet*.xml",
      "xl/sharedStrings.xml",
      "xl/workbook.xml",
      "xl/comments*.xml",
      "xl/threadedComments/threadedComment*.xml",
      "xl/tables/table*.xml",
      "xl/pivotTables/pivotTable*.xml",
      "xl/pivotCache/pivotCacheDefinition*.xml",
      "xl/charts/chart*.xml",
      "xl/calcChain.xml",
      "xl/connections.xml",
      "xl/metadata.xml",
      "docProps/core.xml",
      "docProps/app.xml",
      "docProps/custom.xml",
    ],
    inner_excludes: [
      "_rels/*",
      "xl/_rels/*",
      "xl/worksheets/_rels/*",
      "[Content_Types].xml",
      "xl/styles.xml",
      "xl/theme/*",
    ],
  }
  let entries = expand_archive(xlsx_path, spec) catch { e => raise e }
  for entry in entries {
    // Virtual path must start with the archive path
    let (archive_part, inner_opt) = parse_virtual_path(entry.virtual_path)
    assert_eq(archive_part, xlsx_path)
    // Inner path must be present (these are archive entries)
    assert_true(inner_opt is Some(_))
    // Archive source must reference the xlsx file
    assert_eq(entry.archive_source, Some(xlsx_path))
  }
}

///|
/// Test that specific text content from worksheets, shared strings, etc.
/// is present and correctly decoded in the extracted entries.
test "xlsx: content contains expected text" {
  let dir = xlsx_test_dir()
  let xlsx_path = dir + "/test_content.xlsx"
  let zip_data = build_xlsx_fixture()
  @fs.write_bytes_to_file(xlsx_path, fixed_to_bytes(zip_data)) catch {
    e => raise e
  }
  let spec = ArchiveSpec::{
    inner_includes: [
      "xl/worksheets/sheet*.xml",
      "xl/sharedStrings.xml",
      "xl/workbook.xml",
      "xl/comments*.xml",
      "xl/threadedComments/threadedComment*.xml",
      "xl/tables/table*.xml",
      "xl/pivotTables/pivotTable*.xml",
      "xl/pivotCache/pivotCacheDefinition*.xml",
      "xl/charts/chart*.xml",
      "xl/calcChain.xml",
      "xl/connections.xml",
      "xl/metadata.xml",
      "docProps/core.xml",
      "docProps/app.xml",
      "docProps/custom.xml",
    ],
    inner_excludes: [
      "_rels/*",
      "xl/_rels/*",
      "xl/worksheets/_rels/*",
      "[Content_Types].xml",
      "xl/styles.xml",
      "xl/theme/*",
    ],
  }
  let entries = expand_archive(xlsx_path, spec) catch { e => raise e }
  // Shared strings should contain our text values
  assert_true(has_text_content(entries, "xl/sharedStrings.xml"))
  // Workbook should contain sheet names
  assert_true(has_text_content(entries, "xl/workbook.xml"))
  // Comments should contain comment text
  assert_true(has_text_content(entries, "xl/comments1.xml"))
  // Threaded comments should contain comment text
  assert_true(
    has_text_content(
      entries, "xl/threadedComments/threadedComment1.xml",
    ),
  )
  // Chart should contain title
  assert_true(has_text_content(entries, "xl/charts/chart1.xml"))
  // Core properties should contain title and creator
  assert_true(has_text_content(entries, "docProps/core.xml"))
  // Verify specific content strings by finding entries
  for entry in entries {
    let ip = inner_path(entry.virtual_path)
    if ip == "xl/sharedStrings.xml" {
      assert_true(entry.content.contains("Revenue"))
      assert_true(entry.content.contains("Cost"))
      assert_true(entry.content.contains("Profit"))
      assert_true(entry.content.contains("Summary Sheet"))
    }
    if ip == "xl/workbook.xml" {
      assert_true(entry.content.contains("Financial Data"))
      assert_true(entry.content.contains("Summary"))
      assert_true(entry.content.contains("TotalRevenue"))
    }
    if ip == "xl/comments1.xml" {
      assert_true(
        entry.content.contains("quarterly revenue figures"),
      )
    }
    if ip == "xl/threadedComments/threadedComment1.xml" {
      assert_true(entry.content.contains("budget model"))
    }
    if ip == "xl/charts/chart1.xml" {
      assert_true(entry.content.contains("Revenue vs Cost"))
    }
    if ip == "docProps/core.xml" {
      assert_true(entry.content.contains("Q4 Financial Report"))
      assert_true(entry.content.contains("Finance Team"))
    }
    if ip == "docProps/app.xml" {
      assert_true(entry.content.contains("Acme Corp"))
    }
    if ip == "docProps/custom.xml" {
      assert_true(entry.content.contains("Department"))
      assert_true(entry.content.contains("Finance"))
    }
    if ip == "xl/tables/table1.xml" {
      assert_true(entry.content.contains("FinancialSummary"))
      assert_true(entry.content.contains("Revenue"))
    }
    if ip == "xl/connections.xml" {
      assert_true(entry.content.contains("reporting database"))
    }
  }
}

///|
/// Test the expected count of extracted entries matches all document-relevant parts.
test "xlsx: correct entry count" {
  let dir = xlsx_test_dir()
  let xlsx_path = dir + "/test_count.xlsx"
  let zip_data = build_xlsx_fixture()
  @fs.write_bytes_to_file(xlsx_path, fixed_to_bytes(zip_data)) catch {
    e => raise e
  }
  let spec = ArchiveSpec::{
    inner_includes: [
      "xl/worksheets/sheet*.xml",
      "xl/sharedStrings.xml",
      "xl/workbook.xml",
      "xl/comments*.xml",
      "xl/threadedComments/threadedComment*.xml",
      "xl/tables/table*.xml",
      "xl/pivotTables/pivotTable*.xml",
      "xl/pivotCache/pivotCacheDefinition*.xml",
      "xl/charts/chart*.xml",
      "xl/calcChain.xml",
      "xl/connections.xml",
      "xl/metadata.xml",
      "docProps/core.xml",
      "docProps/app.xml",
      "docProps/custom.xml",
    ],
    inner_excludes: [
      "_rels/*",
      "xl/_rels/*",
      "xl/worksheets/_rels/*",
      "[Content_Types].xml",
      "xl/styles.xml",
      "xl/theme/*",
    ],
  }
  let entries = expand_archive(xlsx_path, spec) catch { e => raise e }
  // 16 document-relevant parts:
  // sheet1, sheet2, sharedStrings, workbook, comments1,
  // threadedComment1, table1, pivotTable1, pivotCacheDefinition1,
  // chart1, calcChain, connections, metadata, core.xml, app.xml, custom.xml
  assert_eq(entries.length(), 16)
}
