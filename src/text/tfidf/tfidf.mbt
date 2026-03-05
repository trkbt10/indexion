// TF-IDF calculation and cosine similarity functions.

///|
/// Build term frequency map from a list of tokens.
/// Returns a map from term to count.
pub fn build_term_frequency(tokens : Array[String]) -> Map[String, Int] {
  let frequency : Map[String, Int] = {}
  for token in tokens {
    let current = frequency.get(token).unwrap_or(0)
    frequency.set(token, current + 1)
  }
  frequency
}

///|
/// Build document frequency map from multiple tokenized documents.
/// Returns a map from term to the number of documents containing that term.
pub fn build_document_frequency(
  docs : Array[Array[String]],
) -> Map[String, Int] {
  let document_frequency : Map[String, Int] = {}
  for tokens in docs {
    // Get unique tokens in this document
    let unique_tokens : Map[String, Bool] = {}
    for token in tokens {
      unique_tokens.set(token, true)
    }
    // Increment document frequency for each unique token
    for entry in unique_tokens {
      let current = document_frequency.get(entry.0).unwrap_or(0)
      document_frequency.set(entry.0, current + 1)
    }
  }
  document_frequency
}

///|
/// Build a TF-IDF vector from tokens, document frequency, and total document count.
/// TF(term, doc) = count(term) / total_tokens
/// IDF(term) = log((1 + total_docs) / (1 + df)) + 1
pub fn build_tfidf_vector(
  tokens : Array[String],
  df : Map[String, Int],
  total_docs : Int,
) -> TfidfVector {
  if tokens.length() == 0 {
    return TfidfVector::new()
  }
  let tf = build_term_frequency(tokens)
  let vector = TfidfVector::new()
  let total_tokens = tokens.length().to_double()
  for entry in tf {
    let term = entry.0
    let count = entry.1
    let normalized_tf = count.to_double() / total_tokens
    let term_df = df.get(term).unwrap_or(0)
    // IDF = log((1 + total_docs) / (1 + df)) + 1
    let idf = @math.ln(
        (1.0 + total_docs.to_double()) / (1.0 + term_df.to_double()),
      ) +
      1.0
    vector.set(term, normalized_tf * idf)
  }
  vector
}

///|
/// Calculate the square root using Newton's method.
fn sqrt(x : Double) -> Double {
  if x <= 0.0 {
    return 0.0
  }
  let mut guess = x / 2.0
  for i = 0; i < 20; i = i + 1 {
    ignore(i)
    guess = (guess + x / guess) / 2.0
  }
  guess
}

///|
/// Calculate the L2 norm of a TF-IDF vector.
fn vector_norm(vector : TfidfVector) -> Double {
  let mut sum = 0.0
  for entry in vector.iter() {
    let value = entry.1
    sum = sum + value * value
  }
  sqrt(sum)
}

///|
/// Calculate cosine similarity between two TF-IDF vectors.
/// Returns 1.0 for identical vectors, 0.0 for orthogonal vectors.
/// If both vectors are empty, returns 1.0.
/// If only one vector is empty, returns 0.0.
pub fn cosine_similarity(a : TfidfVector, b : TfidfVector) -> Double {
  // Both empty -> identical
  if a.is_empty() && b.is_empty() {
    return 1.0
  }
  // One empty -> no similarity
  if a.is_empty() || b.is_empty() {
    return 0.0
  }
  // Iterate over the smaller vector for efficiency
  let (small, large) = if a.length() <= b.length() { (a, b) } else { (b, a) }
  let mut dot = 0.0
  for entry in small.iter() {
    let key = entry.0
    let value = entry.1
    let other = large.get(key)
    dot = dot + value * other
  }
  let norm_a = vector_norm(a)
  let norm_b = vector_norm(b)
  if norm_a == 0.0 || norm_b == 0.0 {
    return 0.0
  }
  dot / (norm_a * norm_b)
}

///|
/// Calculate cosine distance between two TF-IDF vectors.
/// Returns 0.0 for identical vectors, 1.0 for orthogonal vectors.
/// cosine_distance = 1 - cosine_similarity
pub fn cosine_distance(a : TfidfVector, b : TfidfVector) -> Double {
  let similarity = cosine_similarity(a, b)
  let distance = 1.0 - similarity
  // Clamp to [0, 1] to handle floating point errors
  if distance < 0.0 {
    0.0
  } else if distance > 1.0 {
    1.0
  } else {
    distance
  }
}

///|
/// Calculate TF-IDF cosine distances between adjacent texts.
/// Returns an array of distances where distances[i] is the distance
/// between texts[i] and texts[i+1].
pub fn calculate_adjacent_tfidf_distance(
  texts : Array[String],
) -> Array[Double] {
  if texts.length() < 2 {
    return []
  }
  // Tokenize all texts
  let tokenized : Array[Array[String]] = []
  for text in texts {
    tokenized.push(@tokenizer.tokenize_for_tfidf(text))
  }
  // Build document frequency from all documents
  let document_frequency = build_document_frequency(tokenized)
  let total_docs = tokenized.length()
  // Build TF-IDF vectors
  let vectors : Array[TfidfVector] = []
  for tokens in tokenized {
    vectors.push(build_tfidf_vector(tokens, document_frequency, total_docs))
  }
  // Calculate distances between adjacent vectors
  let distances : Array[Double] = []
  for i = 0; i < vectors.length() - 1; i = i + 1 {
    let current = vectors[i]
    let next = vectors[i + 1]
    distances.push(cosine_distance(current, next))
  }
  distances
}

///|
/// Precomputed TF-IDF vectors for batch similarity calculation.
/// This allows efficient pairwise comparison without re-tokenizing.
pub struct TfidfBatch {
  /// TF-IDF vectors for each document.
  vectors : Array[TfidfVector]
}

///|
/// Create a TfidfBatch from an array of texts.
/// Tokenizes each text once and builds TF-IDF vectors using shared document frequency.
pub fn TfidfBatch::from_texts(texts : Array[String]) -> TfidfBatch {
  if texts.length() == 0 {
    return { vectors: [] }
  }
  // Tokenize all texts once
  let tokenized : Array[Array[String]] = []
  for text in texts {
    tokenized.push(@tokenizer.tokenize_for_tfidf(text))
  }
  // Build document frequency from all documents
  let document_frequency = build_document_frequency(tokenized)
  let total_docs = tokenized.length()
  // Build TF-IDF vectors
  let vectors : Array[TfidfVector] = []
  for tokens in tokenized {
    vectors.push(build_tfidf_vector(tokens, document_frequency, total_docs))
  }
  { vectors, }
}

///|
/// Get the number of documents in the batch.
pub fn TfidfBatch::length(self : TfidfBatch) -> Int {
  self.vectors.length()
}

///|
/// Calculate similarity between two documents by index.
/// Returns 1.0 for identical, 0.0 for completely different.
pub fn TfidfBatch::similarity(self : TfidfBatch, i : Int, j : Int) -> Double {
  if i < 0 || j < 0 || i >= self.vectors.length() || j >= self.vectors.length() {
    return 0.0
  }
  if i == j {
    return 1.0
  }
  cosine_similarity(self.vectors[i], self.vectors[j])
}

///|
/// Calculate all pairwise similarities above a threshold.
/// Returns array of (i, j, similarity) tuples where i < j and similarity >= threshold.
pub fn TfidfBatch::all_pairs_above_threshold(
  self : TfidfBatch,
  threshold : Double,
) -> Array[(Int, Int, Double)] {
  let results : Array[(Int, Int, Double)] = []
  let n = self.vectors.length()
  for i = 0; i < n; i = i + 1 {
    for j = i + 1; j < n; j = j + 1 {
      let sim = cosine_similarity(self.vectors[i], self.vectors[j])
      if sim >= threshold {
        results.push((i, j, sim))
      }
    }
  }
  results
}
