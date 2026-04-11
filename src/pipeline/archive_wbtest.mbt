///|
/// SoT guarantee tests: SupportedFile.path is always a real filesystem path.
/// Archive files (pptx/docx/xlsx) must never produce virtual paths in
/// SupportedFile — only in @common.collect_files display_name.

///|
/// Build a minimal PPTX fixture in memory and write to disk.
fn build_test_pptx(path : String) -> Unit raise Error {
  let files : Array[(String, FixedArray[Byte])] = []
  files.push(
    (
      "ppt/slides/slide1.xml",
      @fzip.str_to_u8(
        "<?xml version=\"1.0\"?><p:sld xmlns:p=\"http://schemas.openxmlformats.org/presentationml/2006/main\" xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\"><p:cSld><p:spTree><p:sp><p:txBody><a:p><a:r><a:t>Test Content</a:t></a:r></a:p></p:txBody></p:sp></p:spTree></p:cSld></p:sld>",
      ),
    ),
  )
  files.push(
    (
      "docProps/core.xml",
      @fzip.str_to_u8(
        "<?xml version=\"1.0\"?><cp:coreProperties xmlns:cp=\"http://schemas.openxmlformats.org/package/2006/metadata/core-properties\"><dc:title xmlns:dc=\"http://purl.org/dc/elements/1.1/\">Test</dc:title></cp:coreProperties>",
      ),
    ),
  )
  files.push(
    (
      "[Content_Types].xml",
      @fzip.str_to_u8("<?xml version=\"1.0\"?><Types/>"),
    ),
  )
  let zip_data = @fzip.zip_sync(files)
  let bytes_arr : Array[Byte] = Array::new(capacity=zip_data.length())
  for i in 0..<zip_data.length() {
    bytes_arr.push(zip_data[i])
  }
  @fs.write_bytes_to_file(path, Bytes::from_array(bytes_arr))
}

///|
/// SoT: load_supported_file_info never returns virtual paths for archives.
/// The path must be the real archive file, not an inner entry.
test "load_supported_file_info: archive path is always real, never virtual" {
  let test_dir = "/tmp/indexion-pipeline-archive-test-" + @env.now().to_string()
  @config.ensure_dir_recursive(test_dir)
  let pptx_path = test_dir + "/test.pptx"
  build_test_pptx!(pptx_path)
  let registry = @kgf_features.load_registry_or_empty(target_dir=test_dir)
  let results = load_supported_file_info([pptx_path], registry)
  // Must return exactly 1 entry (the archive itself, not inner XMLs)
  assert_eq!(results.length(), 1)
  let file = results[0]
  // Path must be the real archive path, not a virtual path
  assert_eq!(file.path, pptx_path)
  // Path must NOT contain the virtual path separator
  assert_false!(file.path.contains("!/"))
  // Content must contain text from inner XML files
  assert_true!(file.content.contains("Test Content"))
  assert_true!(file.content.contains("Test"))
  // Content type must be "document" (concatenated archive text)
  assert_eq!(file.content_type, Some("document"))
  // Path must be a real file that exists on disk
  assert_true!(@fs.is_file(file.path))
}

///|
/// SoT: collect_supported_file_info inherits the same guarantee.
test "collect_supported_file_info: archive paths are always real" {
  let test_dir = "/tmp/indexion-pipeline-archive-test2-" + @env.now().to_string()
  @config.ensure_dir_recursive(test_dir)
  let pptx_path = test_dir + "/doc.pptx"
  build_test_pptx!(pptx_path)
  let registry = @kgf_features.load_registry_or_empty(target_dir=test_dir)
  let opts = DiscoverOptions::new(root_dir=test_dir)
  let results = collect_supported_file_info([test_dir], opts, registry)
  // Every returned SupportedFile.path must be a real path
  for file in results {
    assert_false!(file.path.contains("!/"))
    assert_true!(@fs.path_exists(file.path))
  }
}
