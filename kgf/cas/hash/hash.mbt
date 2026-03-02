// SHA-256 hashing utilities for Content-Addressable Storage.
// Uses SHA-256 truncated to 32 hex characters (128 bits).

///|
/// SHA-256 constants (first 32 bits of fractional parts of cube roots of first 64 primes).
let sha256_k : FixedArray[UInt] = [
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1,
  0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
  0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786,
  0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
  0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147,
  0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
  0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b,
  0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
  0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a,
  0x5b9cca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
  0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
]

///|
/// Initial hash values (first 32 bits of fractional parts of square roots of first 8 primes).
let sha256_h_init : FixedArray[UInt] = [
  0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c,
  0x1f83d9ab, 0x5be0cd19,
]

///|
/// Right rotate a 32-bit unsigned integer.
fn rotr(n : Int, x : UInt) -> UInt {
  (x >> n) | (x << (32 - n))
}

///|
/// SHA-256 compression function.
fn sha256_block(h : FixedArray[UInt], w : FixedArray[UInt]) -> Unit {
  let mut a = h[0]
  let mut b = h[1]
  let mut c = h[2]
  let mut d = h[3]
  let mut e = h[4]
  let mut f = h[5]
  let mut g = h[6]
  let mut hh = h[7]
  for i = 0; i < 64; i = i + 1 {
    let s1 = rotr(6, e) ^ rotr(11, e) ^ rotr(25, e)
    let ch = (e & f) ^ ((e ^ 0xFFFFFFFF) & g)
    let temp1 = hh + s1 + ch + sha256_k[i] + w[i]
    let s0 = rotr(2, a) ^ rotr(13, a) ^ rotr(22, a)
    let maj = (a & b) ^ (a & c) ^ (b & c)
    let temp2 = s0 + maj
    hh = g
    g = f
    f = e
    e = d + temp1
    d = c
    c = b
    b = a
    a = temp1 + temp2
  }
  h[0] = h[0] + a
  h[1] = h[1] + b
  h[2] = h[2] + c
  h[3] = h[3] + d
  h[4] = h[4] + e
  h[5] = h[5] + f
  h[6] = h[6] + g
  h[7] = h[7] + hh
}

///|
/// Convert string to UTF-8 bytes.
fn string_to_bytes(s : String) -> Array[Byte] {
  let bytes : Array[Byte] = []
  for i = 0; i < s.length(); i = i + 1 {
    let c = s[i].to_int()
    if c < 0x80 {
      bytes.push(c.to_byte())
    } else if c < 0x800 {
      bytes.push((0xC0 | (c >> 6)).to_byte())
      bytes.push((0x80 | (c & 0x3F)).to_byte())
    } else if c < 0x10000 {
      bytes.push((0xE0 | (c >> 12)).to_byte())
      bytes.push((0x80 | ((c >> 6) & 0x3F)).to_byte())
      bytes.push((0x80 | (c & 0x3F)).to_byte())
    } else {
      bytes.push((0xF0 | (c >> 18)).to_byte())
      bytes.push((0x80 | ((c >> 12) & 0x3F)).to_byte())
      bytes.push((0x80 | ((c >> 6) & 0x3F)).to_byte())
      bytes.push((0x80 | (c & 0x3F)).to_byte())
    }
  }
  bytes
}

///|
/// Pure MoonBit SHA-256 implementation.
fn sha256(data : Array[Byte]) -> String {
  let h : FixedArray[UInt] = FixedArray::make(8, 0U)
  for i = 0; i < 8; i = i + 1 {
    h[i] = sha256_h_init[i]
  }
  let len = data.length()
  let bit_len = len * 8

  // Calculate padding length
  let pad_len = if len % 64 < 56 { 56 - len % 64 } else { 120 - len % 64 }
  let total_len = len + pad_len + 8

  // Create padded data
  let padded : Array[Byte] = Array::make(total_len, b'\x00')
  for i = 0; i < len; i = i + 1 {
    padded[i] = data[i]
  }
  padded[len] = b'\x80'

  // Append length as 64-bit big-endian
  padded[total_len - 8] = ((bit_len >> 56) & 0xFF).to_byte()
  padded[total_len - 7] = ((bit_len >> 48) & 0xFF).to_byte()
  padded[total_len - 6] = ((bit_len >> 40) & 0xFF).to_byte()
  padded[total_len - 5] = ((bit_len >> 32) & 0xFF).to_byte()
  padded[total_len - 4] = ((bit_len >> 24) & 0xFF).to_byte()
  padded[total_len - 3] = ((bit_len >> 16) & 0xFF).to_byte()
  padded[total_len - 2] = ((bit_len >> 8) & 0xFF).to_byte()
  padded[total_len - 1] = (bit_len & 0xFF).to_byte()

  // Process each 64-byte block
  let w : FixedArray[UInt] = FixedArray::make(64, 0U)
  let mut offset = 0
  while offset < total_len {
    // Prepare message schedule
    for i = 0; i < 16; i = i + 1 {
      let idx = offset + i * 4
      w[i] = (padded[idx].to_int().reinterpret_as_uint() << 24) |
        (padded[idx + 1].to_int().reinterpret_as_uint() << 16) |
        (padded[idx + 2].to_int().reinterpret_as_uint() << 8) |
        padded[idx + 3].to_int().reinterpret_as_uint()
    }
    for i = 16; i < 64; i = i + 1 {
      let s0 = rotr(7, w[i - 15]) ^ rotr(18, w[i - 15]) ^ (w[i - 15] >> 3)
      let s1 = rotr(17, w[i - 2]) ^ rotr(19, w[i - 2]) ^ (w[i - 2] >> 10)
      w[i] = w[i - 16] + s0 + w[i - 7] + s1
    }
    sha256_block(h, w)
    offset = offset + 64
  }

  // Convert to hex string
  let hex_chars : Array[Char] = [
    '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e',
    'f',
  ]
  let result = StringBuilder::new()
  for i = 0; i < 8; i = i + 1 {
    let v = h[i]
    for j = 7; j >= 0; j = j - 1 {
      let nibble = ((v >> (j * 4)) & 0xF).reinterpret_as_int()
      result.write_char(hex_chars[nibble])
    }
  }
  result.to_string()
}

///|
/// Compute SHA-256 hash of content, truncated to 32 hex characters.
pub fn compute_hash(content : String) -> @types.ContentHash {
  let bytes = string_to_bytes(content)
  let full_hash = sha256(bytes)
  // Take first 32 characters for truncated hash
  let truncated = StringBuilder::new()
  for i = 0; i < 32 && i < full_hash.length(); i = i + 1 {
    truncated.write_char(full_hash[i].to_int().unsafe_to_char())
  }
  @types.ContentHash::from_string(truncated.to_string())
}

///|
/// Compute hash of a KGF spec for cache invalidation.
/// When spec changes, all chunks need to be regenerated.
pub fn compute_spec_hash(spec_content : String) -> @types.ContentHash {
  compute_hash(spec_content)
}

///|
/// Compute hash for a module chunk based on its contents.
/// Used to generate the chunk's content-addressed ID.
pub fn compute_chunk_hash(
  module_id : String,
  source_hash : @types.ContentHash,
  spec_hash : @types.ContentHash
) -> @types.ContentHash {
  let combined = module_id +
    "\u0000" +
    source_hash.to_string() +
    "\u0000" +
    spec_hash.to_string() +
    "\u0000"
  compute_hash(combined)
}

///|
/// Validate that a string looks like a valid ContentHash (32 hex characters).
pub fn is_valid_hash(hash : String) -> Bool {
  if hash.length() != 32 {
    return false
  }
  for i = 0; i < hash.length(); i = i + 1 {
    let c = hash[i]
    let valid = (c >= '0' && c <= '9') ||
      (c >= 'a' && c <= 'f') ||
      (c >= 'A' && c <= 'F')
    if not(valid) {
      return false
    }
  }
  true
}

///|
/// Create a ContentHash from a string (with validation).
/// Returns None if the string is not a valid hash format.
pub fn as_content_hash(hash : String) -> @types.ContentHash? {
  if is_valid_hash(hash) {
    Some(@types.ContentHash::from_string(hash))
  } else {
    None
  }
}
