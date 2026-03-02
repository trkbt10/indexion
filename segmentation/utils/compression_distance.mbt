// Compression-based distance calculation utilities.
// Implements Normalized Compression Distance (NCD) for measuring semantic similarity.
// Based on "Low-Resource Text Classification: A Parameter-Free Classification Method with Compressors"
//
// NCD(x, y) = (C(xy) - min(C(x), C(y))) / max(C(x), C(y))
// - C(x): compressed size of text x
// - Value range: 0 (identical) to ~1 (completely different)

// LZ77-style compression parameters
///|
let lz77_window_size : Int = 256

///|
let lz77_min_match_length : Int = 3

///|
let lz77_max_match_length : Int = 258

///|
/// Convert a character to UTF-8 bytes and append to buffer.
fn char_to_utf8(buf : Array[Byte], c : Char) -> Unit {
  let code = c.to_int()
  if code < 0x80 {
    // ASCII
    buf.push(code.to_byte())
  } else if code < 0x800 {
    // 2-byte UTF-8
    buf.push((0xC0 | (code >> 6)).to_byte())
    buf.push((0x80 | (code & 0x3F)).to_byte())
  } else if code < 0x10000 {
    // 3-byte UTF-8
    buf.push((0xE0 | (code >> 12)).to_byte())
    buf.push((0x80 | ((code >> 6) & 0x3F)).to_byte())
    buf.push((0x80 | (code & 0x3F)).to_byte())
  } else {
    // 4-byte UTF-8
    buf.push((0xF0 | (code >> 18)).to_byte())
    buf.push((0x80 | ((code >> 12) & 0x3F)).to_byte())
    buf.push((0x80 | ((code >> 6) & 0x3F)).to_byte())
    buf.push((0x80 | (code & 0x3F)).to_byte())
  }
}

///|
/// Convert string to UTF-8 bytes.
fn string_to_utf8(text : String) -> Array[Byte] {
  let chars = text.to_array()
  let buf : Array[Byte] = []
  for c in chars {
    char_to_utf8(buf, c)
  }
  buf
}

///|
/// Find the longest match in the search window for LZ77 compression.
/// Returns (offset, length) where offset is the distance back in the buffer
/// and length is the match length. Returns (0, 0) if no match found.
fn find_longest_match(
  data : Array[Byte],
  pos : Int,
  window_size : Int,
  min_match : Int,
  max_match : Int,
) -> (Int, Int) {
  let data_len = data.length()
  if pos + min_match > data_len {
    return (0, 0)
  }
  let search_start = if pos > window_size { pos - window_size } else { 0 }
  let mut best_offset = 0
  let mut best_length = 0
  // Search for matches in the window
  for i = search_start; i < pos; i = i + 1 {
    let mut match_len = 0
    let max_possible = if pos + max_match < data_len {
      max_match
    } else {
      data_len - pos
    }
    // Count matching bytes
    while match_len < max_possible &&
          data[i + match_len] == data[pos + match_len] {
      match_len = match_len + 1
    }
    if match_len >= min_match && match_len > best_length {
      best_offset = pos - i
      best_length = match_len
    }
  }
  (best_offset, best_length)
}

///|
/// Compress text using LZ77-style algorithm.
/// This is a simplified implementation that captures text similarity effectively.
/// The output format:
/// - Literal byte: 0x00 followed by the byte
/// - Back reference: 0x01 followed by 2-byte offset and 1-byte length
pub fn compress(text : String) -> Bytes {
  let data = string_to_utf8(text)
  let data_len = data.length()
  if data_len == 0 {
    return Bytes::from_array([])
  }
  let output : Array[Byte] = []
  let mut pos = 0
  while pos < data_len {
    let (offset, length) = find_longest_match(
      data, pos, lz77_window_size, lz77_min_match_length, lz77_max_match_length,
    )
    if length >= lz77_min_match_length {
      // Emit back reference: marker (1 byte) + offset (2 bytes) + length (1 byte)
      output.push(b'\x01')
      output.push((offset >> 8).to_byte())
      output.push((offset & 0xFF).to_byte())
      output.push(length.to_byte())
      pos = pos + length
    } else {
      // Emit literal: marker (1 byte) + byte (1 byte)
      output.push(b'\x00')
      output.push(data[pos])
      pos = pos + 1
    }
  }
  Bytes::from_array(output)
}

///|
/// Get the compressed size of text in bytes.
pub fn compressed_size(text : String) -> Int {
  compress(text).length()
}

///|
/// Calculate Normalized Compression Distance between two texts.
/// NCD(x, y) = (C(xy) - min(C(x), C(y))) / max(C(x), C(y))
///
/// Uses LZ77-style compression to measure text similarity.
/// Similar texts compress better together (lower NCD), while different texts
/// do not benefit from concatenation (higher NCD).
///
/// Returns NCD value between 0 (identical) and ~1 (completely different).
pub fn ncd(a : String, b : String) -> Double {
  // Handle edge cases
  if a.length() == 0 && b.length() == 0 {
    return 0.0
  }
  if a.length() == 0 || b.length() == 0 {
    return 1.0
  }

  let c_a = compressed_size(a)
  let c_b = compressed_size(b)
  let c_ab = compressed_size(a + b)

  let min_c = if c_a < c_b { c_a } else { c_b }
  let max_c = if c_a > c_b { c_a } else { c_b }

  // Avoid division by zero
  if max_c == 0 {
    return 0.0
  }

  (c_ab.to_double() - min_c.to_double()) / max_c.to_double()
}

///|
/// Calculate NCD values for sliding window of adjacent texts.
/// For texts [a, b, c, d], calculates:
/// - ncd(a, b)
/// - ncd(b, c)
/// - ncd(c, d)
///
/// Returns array of NCD values (length = texts.length - 1).
pub fn calculate_adjacent_ncd(texts : Array[String]) -> Array[Double] {
  if texts.length() < 2 {
    return []
  }

  let results : Array[Double] = []
  for i = 0; i < texts.length() - 1; i = i + 1 {
    results.push(ncd(texts[i], texts[i + 1]))
  }
  results
}

///|
/// Find local maxima indices where values exceed the threshold.
/// A local maximum is a value that is greater than or equal to both its neighbors.
///
/// This is useful for finding potential segment boundaries in NCD/divergence values.
pub fn find_local_maxima(
  values : Array[Double],
  threshold : Double,
) -> Array[Int] {
  let maxima : Array[Int] = []

  if values.length() < 3 {
    // For very short arrays, check each value against threshold
    for i = 0; i < values.length(); i = i + 1 {
      if values[i] >= threshold {
        maxima.push(i)
      }
    }
    return maxima
  }

  // Check edges
  // First element: compare with second
  if values[0] >= threshold && values[0] >= values[1] {
    maxima.push(0)
  }

  // Middle elements: compare with both neighbors
  for i = 1; i < values.length() - 1; i = i + 1 {
    if values[i] >= threshold &&
      values[i] >= values[i - 1] &&
      values[i] >= values[i + 1] {
      maxima.push(i)
    }
  }

  // Last element: compare with second-to-last
  let last_idx = values.length() - 1
  if values[last_idx] >= threshold && values[last_idx] >= values[last_idx - 1] {
    maxima.push(last_idx)
  }

  maxima
}

///|
/// Normalize an array of values using Min-Max normalization.
/// Returns values in range [0, 1].
/// If all values are the same, returns 0.5 for all.
pub fn min_max_normalize(values : Array[Double]) -> Array[Double] {
  if values.length() == 0 {
    return []
  }

  // Find min and max
  let mut min_val = values[0]
  let mut max_val = values[0]
  for i = 1; i < values.length(); i = i + 1 {
    if values[i] < min_val {
      min_val = values[i]
    }
    if values[i] > max_val {
      max_val = values[i]
    }
  }

  // Handle case where all values are the same
  if max_val == min_val {
    let result : Array[Double] = []
    for _ in values {
      result.push(0.5)
    }
    return result
  }

  // Normalize
  let range = max_val - min_val
  let result : Array[Double] = []
  for value in values {
    result.push((value - min_val) / range)
  }
  result
}
