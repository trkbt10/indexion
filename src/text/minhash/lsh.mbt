// Locality-Sensitive Hashing (LSH) for approximate nearest neighbor search.
//
// LSH partitions MinHash signatures into bands. If any band matches between
// two documents, they become candidates. This achieves sub-quadratic
// candidate generation while providing probabilistic guarantees:
//
//   P(candidate) = 1 - (1 - J^r)^b
//
// where J = true Jaccard similarity, r = rows per band, b = number of bands.
//
// Reference: Leskovec, Rajaraman, Ullman "Mining of Massive Datasets" Ch. 3

///|
/// LSH index for approximate nearest neighbor search.
pub struct LSHIndex {
  /// Number of bands for LSH banding.
  bands : Int
  /// Number of rows per band (num_hashes / bands).
  rows_per_band : Int
  /// Buckets: band_index → hash → list of document indices.
  buckets : Array[Map[Int, Array[Int]]]
  /// Stored signatures for Jaccard re-scoring.
  signatures : Array[MinHashSignature]
}

///|
/// Create an LSH index configured for a target Jaccard threshold.
/// Automatically selects (bands, rows_per_band) to maximize detection
/// probability at the given threshold while keeping false positives low.
///
/// The total number of hash values used = bands × rows_per_band ≤ num_hashes.
pub fn LSHIndex::new(target_threshold : Double) -> LSHIndex {
  let (bands, rows_per_band) = select_band_params(target_threshold)
  { bands, rows_per_band, buckets: init_buckets(bands), signatures: [] }
}

///|
/// Initialize empty bucket maps for each band.
fn init_buckets(n : Int) -> Array[Map[Int, Array[Int]]] {
  let arr : Array[Map[Int, Array[Int]]] = []
  for i = 0; i < n; i = i + 1 {
    ignore(i)
    arr.push(Map([]))
  }
  arr
}

///|
/// Insert a document's MinHash signature into the LSH index.
/// Returns the document's index in the index.
pub fn LSHIndex::insert(self : LSHIndex, signature : MinHashSignature) -> Int {
  let doc_id = self.signatures.length()
  self.signatures.push(signature)
  let values = signature.get_values()
  for band = 0; band < self.bands; band = band + 1 {
    let band_hash = hash_band(values, band, self.rows_per_band)
    match self.buckets[band].get(band_hash) {
      Some(list) => list.push(doc_id)
      None => self.buckets[band].set(band_hash, [doc_id])
    }
  }
  doc_id
}

///|
/// Query for candidate pairs: all (i, j) where i < j that share
/// at least one LSH bucket. Returns deduplicated pairs.
pub fn LSHIndex::candidate_pairs(self : LSHIndex) -> Array[(Int, Int)] {
  let seen : Map[String, Bool] = {}
  let pairs : Array[(Int, Int)] = []
  for band = 0; band < self.bands; band = band + 1 {
    for entry in self.buckets[band] {
      let docs = entry.1
      if docs.length() < 2 {
        continue
      }
      for i = 0; i < docs.length(); i = i + 1 {
        for j = i + 1; j < docs.length(); j = j + 1 {
          let lo = if docs[i] < docs[j] { docs[i] } else { docs[j] }
          let hi = if docs[i] < docs[j] { docs[j] } else { docs[i] }
          let key = lo.to_string() + ":" + hi.to_string()
          if !seen.contains(key) {
            seen.set(key, true)
            pairs.push((lo, hi))
          }
        }
      }
    }
  }
  pairs
}

///|
/// Query for candidate pairs with MinHash Jaccard re-scoring.
/// Returns (i, j, estimated_jaccard) tuples where jaccard >= threshold.
pub fn LSHIndex::candidate_pairs_above_threshold(
  self : LSHIndex,
  threshold : Double,
) -> Array[(Int, Int, Double)] {
  let candidates = self.candidate_pairs()
  let results : Array[(Int, Int, Double)] = []
  for pair in candidates {
    let (i, j) = pair
    let jaccard = self.signatures[i].jaccard(self.signatures[j])
    if jaccard >= threshold {
      results.push((i, j, jaccard))
    }
  }
  results
}

///|
/// Get the number of documents in the index.
pub fn LSHIndex::length(self : LSHIndex) -> Int {
  self.signatures.length()
}

///|
/// Hash a band (a contiguous slice of the signature) to a single int.
/// Uses a simple polynomial hash over the rows in the band.
fn hash_band(values : Array[Int], band : Int, rows_per_band : Int) -> Int {
  let start = band * rows_per_band
  let mut hash = 0x811c9dc5 // FNV offset basis
  for i = 0; i < rows_per_band; i = i + 1 {
    let idx = start + i
    if idx < values.length() {
      hash = hash.lxor(values[idx])
      hash = hash * 0x01000193 // FNV prime
    }
  }
  hash.land(0x7FFFFFFF)
}

///|
/// Select (bands, rows_per_band) that best approximate the target threshold.
///
/// The S-curve inflection point is at t ≈ (1/b)^(1/r).
/// We search all valid (b, r) factorizations of num_hashes and pick
/// the one whose inflection point is closest to the target.
fn select_band_params(threshold : Double) -> (Int, Int) {
  let n = 128 // num_hashes
  let mut best_bands = 16
  let mut best_rows = 8
  let mut best_diff = 1.0
  // Try all factor pairs (b, r) where b * r <= n
  let mut b = 1
  while b <= n {
    let r = n / b
    if r < 1 {
      b += 1
      continue
    }
    // Inflection point: t ≈ (1/b)^(1/r)
    let inflection = @math.exp(-@math.ln(b.to_double()) / r.to_double())
    let diff = if inflection > threshold {
      inflection - threshold
    } else {
      threshold - inflection
    }
    if diff < best_diff {
      best_diff = diff
      best_bands = b
      best_rows = r
    }
    b += 1
  }
  (best_bands, best_rows)
}
