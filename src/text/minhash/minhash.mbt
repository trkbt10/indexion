// MinHash signature generation and Jaccard similarity estimation.
//
// MinHash is a locality-sensitive hashing technique that provides
// an unbiased estimator of the Jaccard similarity between two sets.
// Each hash function maps the set to a single minimum hash value;
// the probability that two sets agree on a MinHash equals their Jaccard index.
//
// Reference: Broder (1997) "On the resemblance and containment of documents"

///|
/// Number of hash functions in a MinHash signature.
/// Higher values give more accurate Jaccard estimates.
/// Error ≈ 1/√num_hashes, so 128 → ~8.8% error.
let num_hashes : Int = 128

///|
/// A MinHash signature: a fixed-length array of minimum hash values.
pub struct MinHashSignature {
  /// Minimum hash values, one per hash function.
  values : Array[Int]
}

///|
/// Create a MinHash signature from a set of tokens.
/// Uses the formula h_i(x) = (a_i * hash(x) + b_i) mod p
/// where p is a large prime and (a_i, b_i) are per-hash-function constants.
pub fn MinHashSignature::from_tokens(
  tokens : Array[String],
) -> MinHashSignature {
  let values = Array::make(num_hashes, 2147483647) // Int max
  if tokens.length() == 0 {
    return { values, }
  }
  // Deduplicate tokens into a set
  let unique : Map[String, Bool] = Map([])
  for token in tokens {
    unique.set(token, true)
  }
  // For each unique token, compute all hash functions and keep minimums
  for entry in unique {
    let token = entry.0
    let base_hash = fnv1a_hash(token)
    for i = 0; i < num_hashes; i = i + 1 {
      let h = universal_hash(base_hash, i)
      if h < values[i] {
        values[i] = h
      }
    }
  }
  { values, }
}

///|
/// Estimate Jaccard similarity from two MinHash signatures.
/// Returns the fraction of hash functions that agree (in [0, 1]).
pub fn MinHashSignature::jaccard(
  self : MinHashSignature,
  other : MinHashSignature,
) -> Double {
  let n = self.values.length()
  let mut agree = 0
  for i = 0; i < n; i = i + 1 {
    if self.values[i] == other.values[i] {
      agree += 1
    }
  }
  agree.to_double() / n.to_double()
}

///|
/// Get the signature values for LSH banding.
pub fn MinHashSignature::get_values(self : MinHashSignature) -> Array[Int] {
  self.values
}

///|
/// FNV-1a hash for strings, producing a non-negative 32-bit hash.
fn fnv1a_hash(s : String) -> Int {
  let chars = s.to_array()
  // FNV offset basis (32-bit)
  let mut hash = 0x811c9dc5
  for c in chars {
    let code = c.to_int()
    // Process each byte of the character
    // XOR with byte, then multiply by FNV prime
    hash = hash.lxor(code.land(0xFF))
    hash = hash * 0x01000193
    if code > 0xFF {
      hash = hash.lxor((code / 256).land(0xFF))
      hash = hash * 0x01000193
    }
    if code > 0xFFFF {
      hash = hash.lxor((code / 65536).land(0xFF))
      hash = hash * 0x01000193
    }
  }
  // Ensure non-negative
  hash.land(0x7FFFFFFF)
}

///|
/// Universal hash function family: h_i(x) = (a_i * x + b_i) mod p
/// Uses a Mersenne prime p = 2^31 - 1 for fast modular arithmetic.
/// Coefficients are derived deterministically from the hash function index.
fn universal_hash(base_hash : Int, index : Int) -> Int {
  // Mersenne prime 2^31 - 1
  let p = 2147483647
  // Derive a_i and b_i deterministically from index
  // a must be non-zero; b can be zero
  let a = (index * 1103515245 + 12345).land(0x7FFFFFFF)
  let a_nonzero = if a == 0 { 1 } else { a }
  let b = (index * 1664525 + 1013904223).land(0x7FFFFFFF)
  // Compute (a * x + b) mod p using 64-bit arithmetic to avoid overflow
  let ax = a_nonzero.to_int64() * base_hash.to_int64()
  let axb = ax + b.to_int64()
  // Mersenne prime modulo: x mod (2^31-1) = (x & p) + (x >> 31), repeat if needed
  // Mersenne prime modulo using bit operations
  // For non-negative values, lsr(31) is equivalent to division by 2^31
  let r = axb.land(0x7FFFFFFFL) +
    (axb.reinterpret_as_uint64() >> 31).reinterpret_as_int64()
  let result = if r >= p.to_int64() { r - p.to_int64() } else { r }
  result.to_int()
}
