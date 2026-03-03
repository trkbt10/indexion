// TF-IDF distance calculation utilities.
// Provides wrapper functions for TF-IDF based text similarity.

///|
/// Tokenize text for TF-IDF processing.
/// Combines word tokens and character bigrams for mixed language support.
pub fn tokenize_text_for_tfidf(text : String) -> Array[String] {
  @tokenizer.tokenize_for_tfidf(text)
}

///|
/// Calculate cosine similarity between two TF-IDF vectors.
/// Returns 1.0 for identical vectors, 0.0 for orthogonal vectors.
pub fn cosine_similarity(
  a : @tfidf.TfidfVector,
  b : @tfidf.TfidfVector,
) -> Double {
  @tfidf.cosine_similarity(a, b)
}

///|
/// Calculate cosine distance between two TF-IDF vectors.
/// Returns 0.0 for identical vectors, 1.0 for orthogonal vectors.
/// cosine_distance = 1 - cosine_similarity
pub fn cosine_distance(
  a : @tfidf.TfidfVector,
  b : @tfidf.TfidfVector,
) -> Double {
  @tfidf.cosine_distance(a, b)
}

///|
/// Calculate TF-IDF cosine distances between adjacent texts.
/// Returns an array of distances where distances[i] is the distance
/// between texts[i] and texts[i+1].
pub fn calculate_adjacent_tfidf_distance(
  texts : Array[String],
) -> Array[Double] {
  @tfidf.calculate_adjacent_tfidf_distance(texts)
}

///|
/// Build a TF-IDF vector from tokens.
pub fn build_tfidf_vector(
  tokens : Array[String],
  df : Map[String, Int],
  total_docs : Int,
) -> @tfidf.TfidfVector {
  @tfidf.build_tfidf_vector(tokens, df, total_docs)
}

///|
/// Build document frequency map from multiple tokenized documents.
pub fn build_document_frequency(
  docs : Array[Array[String]],
) -> Map[String, Int] {
  @tfidf.build_document_frequency(docs)
}

///|
/// Build term frequency map from a list of tokens.
pub fn build_term_frequency(tokens : Array[String]) -> Map[String, Int] {
  @tfidf.build_term_frequency(tokens)
}
