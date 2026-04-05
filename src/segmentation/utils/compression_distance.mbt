// Compression-based distance calculation utilities.
// Implements Normalized Compression Distance (NCD) for measuring semantic similarity.
// Based on "Low-Resource Text Classification: A Parameter-Free Classification Method with Compressors"
//
// NCD(x, y) = (C(xy) - min(C(x), C(y))) / max(C(x), C(y))
// - C(x): compressed size of text x
// - Value range: 0 (identical) to ~1 (completely different)

// LZ77-style compression parameters

///|
/// 8KB window — large enough to capture long-range repetitions in code/text,
/// which is essential for NCD sensitivity (Cilibrasi & Vitányi 2005).
let lz77_window_size : Int = 8192

///|
let lz77_min_match_length : Int = 3

///|
let lz77_max_match_length : Int = 258

///|
/// Hash table size for trigram hash chain (power of 2 for fast modulo).
let hash_table_size : Int = 4096

///|
/// Maximum number of hash chain entries to follow per position.
/// Limits worst-case search time while still finding good matches.
let max_chain_length : Int = 64

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
/// Hash a 3-byte trigram into a table index.
fn trigram_hash(a : Byte, b : Byte, c : Byte) -> Int {
  // Simple but effective hash for byte trigrams
  let h = a.to_int() * 31 * 31 + b.to_int() * 31 + c.to_int()
  h.land(hash_table_size - 1)
}

///|
/// Compress text using LZ77-style algorithm with hash chain acceleration.
/// Uses an 8KB sliding window with trigram hash chains to find matches efficiently.
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
  // Hash chain: head[hash] = most recent position with that trigram hash
  // prev[pos] = previous position in chain with same hash
  let head = Array::make(hash_table_size, -1)
  let prev = Array::make(data_len, -1)
  let mut pos = 0
  while pos < data_len {
    if pos + lz77_min_match_length > data_len {
      // Not enough bytes for a match, emit literal
      output.push(b'\x00')
      output.push(data[pos])
      pos += 1
      continue
    }
    let h = trigram_hash(data[pos], data[pos + 1], data[pos + 2])
    let mut best_offset = 0
    let mut best_length = 0
    let search_limit = if pos > lz77_window_size {
      pos - lz77_window_size
    } else {
      0
    }
    // Walk the hash chain
    let mut chain_pos = head[h]
    let mut chain_count = 0
    while chain_pos >= search_limit && chain_count < max_chain_length {
      // Verify the match and extend
      let max_possible = if pos + lz77_max_match_length < data_len {
        lz77_max_match_length
      } else {
        data_len - pos
      }
      let mut match_len = 0
      while match_len < max_possible &&
            data[chain_pos + match_len] == data[pos + match_len] {
        match_len += 1
      }
      if match_len >= lz77_min_match_length && match_len > best_length {
        best_offset = pos - chain_pos
        best_length = match_len
        if best_length == lz77_max_match_length {
          break // Can't do better
        }
      }
      chain_count += 1
      chain_pos = prev[chain_pos]
      if chain_pos < 0 {
        break
      }
    }
    // Update hash chain for current position
    prev[pos] = head[h]
    head[h] = pos
    if best_length >= lz77_min_match_length {
      // Emit back reference: marker (1 byte) + offset (2 bytes) + length (1 byte)
      output.push(b'\x01')
      output.push((best_offset >> 8).to_byte())
      output.push((best_offset & 0xFF).to_byte())
      output.push(best_length.to_byte())
      // Insert skipped positions into hash chain
      for k = 1; k < best_length; k = k + 1 {
        let skip_pos = pos + k
        if skip_pos + 2 < data_len {
          let skip_h = trigram_hash(
            data[skip_pos],
            data[skip_pos + 1],
            data[skip_pos + 2],
          )
          prev[skip_pos] = head[skip_h]
          head[skip_h] = skip_pos
        }
      }
      pos += best_length
    } else {
      // Emit literal: marker (1 byte) + byte (1 byte)
      output.push(b'\x00')
      output.push(data[pos])
      pos += 1
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
/// Normalize an array of values using Min-Max normalization.
/// Returns values in range [0, 1].
/// If all values are the same, returns 0.5 for all.
///
/// WARNING: Min-Max is sensitive to outliers. Prefer `robust_normalize`
/// for signals that may contain extreme values.
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

///|
/// Normalize an array of values using robust z-score (median + MAD).
/// Resistant to outliers unlike Min-Max normalization.
/// Output is shifted to [0, 1] range via sigmoid-like clamping.
/// If MAD is zero (all values equal or nearly so), returns 0.5 for all.
pub fn robust_normalize(values : Array[Double]) -> Array[Double] {
  if values.length() == 0 {
    return []
  }
  let n = values.length()
  // Compute median
  let sorted = values.copy()
  sorted.sort_by(fn(a, b) { a.compare(b) })
  let median = if n % 2 == 1 {
    sorted[n / 2]
  } else {
    (sorted[n / 2 - 1] + sorted[n / 2]) / 2.0
  }
  // Compute MAD (Median Absolute Deviation)
  let abs_devs : Array[Double] = []
  for v in values {
    let d = v - median
    abs_devs.push(if d < 0.0 { -d } else { d })
  }
  abs_devs.sort_by(fn(a, b) { a.compare(b) })
  let mad = if n % 2 == 1 {
    abs_devs[n / 2]
  } else {
    (abs_devs[n / 2 - 1] + abs_devs[n / 2]) / 2.0
  }
  // If MAD is zero, all values are effectively the same
  if mad < 1.0e-12 {
    let result : Array[Double] = []
    for _ in values {
      result.push(0.5)
    }
    return result
  }
  // Robust z-score, then map to [0, 1] via min-max of the z-scores
  // This preserves relative ordering while being outlier-resistant
  let z_scores : Array[Double] = []
  for v in values {
    z_scores.push((v - median) / mad)
  }
  // Map z-scores to [0, 1] using min-max on the z-scores themselves
  // Since the z-scores are already robust, min-max here is safe
  let mut z_min = z_scores[0]
  let mut z_max = z_scores[0]
  for i = 1; i < z_scores.length(); i = i + 1 {
    if z_scores[i] < z_min {
      z_min = z_scores[i]
    }
    if z_scores[i] > z_max {
      z_max = z_scores[i]
    }
  }
  let z_range = z_max - z_min
  if z_range < 1.0e-12 {
    let result : Array[Double] = []
    for _ in values {
      result.push(0.5)
    }
    return result
  }
  let result : Array[Double] = []
  for z in z_scores {
    result.push((z - z_min) / z_range)
  }
  result
}

///|
/// Reciprocal Rank Fusion (RRF) for combining multiple ranked signal arrays.
/// Each input array is ranked independently, then fused via:
///   score(i) = sum_j( 1 / (k + rank_j(i)) )
/// where k is a smoothing constant (typically 60).
/// Returns fused scores normalized to [0, 1].
///
/// All input arrays must have the same length. Higher values = higher rank.
pub fn reciprocal_rank_fusion(
  signals : Array[Array[Double]],
  k : Double,
) -> Array[Double] {
  if signals.length() == 0 {
    return []
  }
  let n = signals[0].length()
  if n == 0 {
    return []
  }
  // Compute ranks for each signal (higher value = higher rank = lower rank number)
  let fused = Array::make(n, 0.0)
  for signal in signals {
    // Create index array and sort by signal value descending
    let indices : Array[(Int, Double)] = []
    for i = 0; i < signal.length(); i = i + 1 {
      indices.push((i, signal[i]))
    }
    indices.sort_by(fn(a, b) { b.1.compare(a.1) })
    // Assign RRF contribution by rank (rank 1 = highest value)
    for rank = 0; rank < indices.length(); rank = rank + 1 {
      let idx = indices[rank].0
      fused[idx] = fused[idx] + 1.0 / (k + (rank + 1).to_double())
    }
  }
  // Normalize to [0, 1]
  let mut max_score = 0.0
  let mut min_score = fused[0]
  for v in fused {
    if v > max_score {
      max_score = v
    }
    if v < min_score {
      min_score = v
    }
  }
  let range = max_score - min_score
  if range < 1.0e-12 {
    return Array::make(n, 0.5)
  }
  let result : Array[Double] = []
  for v in fused {
    result.push((v - min_score) / range)
  }
  result
}
