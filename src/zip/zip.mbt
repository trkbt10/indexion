///|
/// ZIP archive reading module.
/// Wraps hustcer/fzip to provide path-based ZIP operations
/// with glob filtering for selective entry extraction.

///|
/// Metadata for a single entry inside a ZIP archive.
pub struct ZipEntry {
  /// Entry path within the archive (e.g. "ppt/slides/slide1.xml")
  name : String
  /// Compressed size in bytes
  compressed_size : Int
  /// Uncompressed size in bytes
  original_size : Int
  /// Compression method (0 = stored, 8 = deflate)
  compression : Int
}

///|
/// A file extracted from a ZIP archive.
pub struct ZipFile {
  /// Entry path within the archive
  name : String
  /// Raw bytes of the uncompressed content
  data : FixedArray[Byte]
}

///|
/// Read a ZIP file from disk and return raw bytes.
fn read_zip_bytes(path : String) -> FixedArray[Byte] raise Error {
  @fs.read_file_to_bytes(path) |> bytes_to_fixed_array()
}

///|
/// Convert Bytes to FixedArray[Byte].
fn bytes_to_fixed_array(b : Bytes) -> FixedArray[Byte] {
  let len = b.length()
  let arr = FixedArray::make(len, b'\x00')
  for i in 0..<len {
    arr[i] = b[i]
  }
  arr
}

///|
/// List all entries in a ZIP archive without extracting.
pub fn list_entries(path : String) -> Array[ZipEntry] raise Error {
  let data = read_zip_bytes(path)
  let infos = @fzip.unzip_list(data)
  let entries : Array[ZipEntry] = []
  for info in infos {
    entries.push(
      {
        name: info.name,
        compressed_size: info.size,
        original_size: info.original_size,
        compression: info.compression,
      },
    )
  }
  entries
}

///|
/// Extract all entries from a ZIP archive.
pub fn extract_all(path : String) -> Array[ZipFile] raise Error {
  let data = read_zip_bytes(path)
  let pairs = @fzip.unzip_sync(data)
  let files : Array[ZipFile] = []
  for pair in pairs {
    files.push({ name: pair.0, data: pair.1 })
  }
  files
}

///|
/// Extract only entries matching the given glob include/exclude patterns.
/// If includes is empty, all entries are included.
/// Excludes are applied after includes.
pub fn extract_filtered(
  path : String,
  includes~ : Array[String] = [],
  excludes~ : Array[String] = [],
) -> Array[ZipFile] raise Error {
  let data = read_zip_bytes(path)
  let pairs = @fzip.unzip_sync(data)
  let files : Array[ZipFile] = []
  for pair in pairs {
    let name = pair.0
    if should_include_entry(name, includes, excludes) {
      files.push({ name, data: pair.1 })
    }
  }
  files
}

///|
/// List entries matching the given glob include/exclude patterns.
pub fn list_filtered(
  path : String,
  includes~ : Array[String] = [],
  excludes~ : Array[String] = [],
) -> Array[ZipEntry] raise Error {
  let data = read_zip_bytes(path)
  let infos = @fzip.unzip_list(data)
  let entries : Array[ZipEntry] = []
  for info in infos {
    if should_include_entry(info.name, includes, excludes) {
      entries.push(
        {
          name: info.name,
          compressed_size: info.size,
          original_size: info.original_size,
          compression: info.compression,
        },
      )
    }
  }
  entries
}

///|
/// Check if a ZIP entry name should be included based on glob patterns.
fn should_include_entry(
  name : String,
  includes : Array[String],
  excludes : Array[String],
) -> Bool {
  // If includes are specified, name must match at least one
  if includes.length() > 0 {
    let mut matched = false
    for pattern in includes {
      if @glob.glob_match(name, pattern) {
        matched = true
        break
      }
    }
    if !matched {
      return false
    }
  }
  // Excludes reject even if included
  for pattern in excludes {
    if @glob.glob_match(name, pattern) {
      return false
    }
  }
  true
}

///|
/// Decode extracted bytes as a UTF-8 string.
/// Returns None if the bytes are not valid UTF-8.
pub fn decode_utf8(data : FixedArray[Byte]) -> String? {
  let buf = StringBuilder::new()
  let len = data.length()
  let mut i = 0
  while i < len {
    let b0 = data[i].to_int()
    if b0 < 0x80 {
      buf.write_char(b0.unsafe_to_char())
      i += 1
    } else if b0 < 0xC0 {
      return None
    } else if b0 < 0xE0 {
      if i + 1 >= len {
        return None
      }
      let b1 = data[i + 1].to_int()
      if (b1 & 0xC0) != 0x80 {
        return None
      }
      let cp = ((b0 & 0x1F) << 6) | (b1 & 0x3F)
      buf.write_char(cp.unsafe_to_char())
      i += 2
    } else if b0 < 0xF0 {
      if i + 2 >= len {
        return None
      }
      let b1 = data[i + 1].to_int()
      let b2 = data[i + 2].to_int()
      if (b1 & 0xC0) != 0x80 || (b2 & 0xC0) != 0x80 {
        return None
      }
      let cp = ((b0 & 0x0F) << 12) | ((b1 & 0x3F) << 6) | (b2 & 0x3F)
      buf.write_char(cp.unsafe_to_char())
      i += 3
    } else if b0 < 0xF8 {
      if i + 3 >= len {
        return None
      }
      let b1 = data[i + 1].to_int()
      let b2 = data[i + 2].to_int()
      let b3 = data[i + 3].to_int()
      if (b1 & 0xC0) != 0x80 || (b2 & 0xC0) != 0x80 || (b3 & 0xC0) != 0x80 {
        return None
      }
      let cp = ((b0 & 0x07) << 18) |
        ((b1 & 0x3F) << 12) |
        ((b2 & 0x3F) << 6) |
        (b3 & 0x3F)
      buf.write_char(cp.unsafe_to_char())
      i += 4
    } else {
      return None
    }
  }
  Some(buf.to_string())
}

///|
/// Encode bytes to base64 string.
/// Used for binary content (images etc.) that needs to be passed
/// through KGF text-based processing pipeline.
pub fn encode_base64(data : FixedArray[Byte]) -> String {
  let alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
  let len = data.length()
  let buf = StringBuilder::new()
  fn b64char(idx : Int) -> Char {
    alphabet[idx].to_int().unsafe_to_char()
  }

  let mut i = 0
  while i + 2 < len {
    let b0 = data[i].to_int()
    let b1 = data[i + 1].to_int()
    let b2 = data[i + 2].to_int()
    let n = (b0 << 16) | (b1 << 8) | b2
    buf.write_char(b64char((n >> 18) & 0x3F))
    buf.write_char(b64char((n >> 12) & 0x3F))
    buf.write_char(b64char((n >> 6) & 0x3F))
    buf.write_char(b64char(n & 0x3F))
    i += 3
  }
  let remaining = len - i
  if remaining == 2 {
    let b0 = data[i].to_int()
    let b1 = data[i + 1].to_int()
    let n = (b0 << 16) | (b1 << 8)
    buf.write_char(b64char((n >> 18) & 0x3F))
    buf.write_char(b64char((n >> 12) & 0x3F))
    buf.write_char(b64char((n >> 6) & 0x3F))
    buf.write_char('=')
  } else if remaining == 1 {
    let b0 = data[i].to_int()
    let n = b0 << 16
    buf.write_char(b64char((n >> 18) & 0x3F))
    buf.write_char(b64char((n >> 12) & 0x3F))
    buf.write_char('=')
    buf.write_char('=')
  }
  buf.to_string()
}
