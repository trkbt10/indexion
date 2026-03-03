// Tests for TF-IDF functions.

///|
test "build_term_frequency counts tokens correctly" {
  let tokens = ["hello", "world", "hello"]
  let tf = build_term_frequency(tokens)
  assert_eq(tf.get("hello").unwrap_or(0), 2)
  assert_eq(tf.get("world").unwrap_or(0), 1)
  assert_eq(tf.get("foo").unwrap_or(0), 0)
}

///|
test "build_term_frequency handles empty array" {
  let tokens : Array[String] = []
  let tf = build_term_frequency(tokens)
  assert_eq(tf.length(), 0)
}

///|
test "build_document_frequency counts documents correctly" {
  let docs = [["hello", "world"], ["hello", "foo"], ["bar", "baz"]]
  let df = build_document_frequency(docs)
  assert_eq(df.get("hello").unwrap_or(0), 2) // appears in 2 docs
  assert_eq(df.get("world").unwrap_or(0), 1)
  assert_eq(df.get("foo").unwrap_or(0), 1)
  assert_eq(df.get("bar").unwrap_or(0), 1)
}

///|
test "build_document_frequency handles duplicate tokens in doc" {
  let docs = [["hello", "hello", "hello"]]
  let df = build_document_frequency(docs)
  // Even though "hello" appears 3 times, it's in only 1 document
  assert_eq(df.get("hello").unwrap_or(0), 1)
}

///|
test "build_document_frequency handles empty docs" {
  let docs : Array[Array[String]] = []
  let df = build_document_frequency(docs)
  assert_eq(df.length(), 0)
}

///|
test "build_tfidf_vector creates vector from tokens" {
  let docs = [["hello", "world"], ["hello", "foo"]]
  let df = build_document_frequency(docs)
  let tokens = ["hello", "world"]
  let vector = build_tfidf_vector(tokens, df, 2)
  assert_true(vector.length() > 0)
  assert_true(vector.get("hello") > 0.0)
  assert_true(vector.get("world") > 0.0)
}

///|
test "build_tfidf_vector handles empty tokens" {
  let df : Map[String, Int] = {}
  let tokens : Array[String] = []
  let vector = build_tfidf_vector(tokens, df, 2)
  assert_true(vector.is_empty())
}

///|
test "TfidfVector new creates empty vector" {
  let vector = TfidfVector::new()
  assert_true(vector.is_empty())
  assert_eq(vector.length(), 0)
}

///|
test "TfidfVector set and get work correctly" {
  let vector = TfidfVector::new()
  vector.set("term", 0.5)
  assert_eq(vector.get("term"), 0.5)
  assert_eq(vector.get("other"), 0.0)
}

///|
test "cosine_similarity of identical vectors is 1" {
  let vector = TfidfVector::new()
  vector.set("a", 1.0)
  vector.set("b", 2.0)
  let similarity = cosine_similarity(vector, vector)
  // Should be very close to 1.0
  assert_true(similarity > 0.999)
}

///|
test "cosine_similarity of orthogonal vectors is 0" {
  let a = TfidfVector::new()
  a.set("x", 1.0)
  let b = TfidfVector::new()
  b.set("y", 1.0)
  let similarity = cosine_similarity(a, b)
  assert_eq(similarity, 0.0)
}

///|
test "cosine_similarity of empty vectors is 1" {
  let a = TfidfVector::new()
  let b = TfidfVector::new()
  let similarity = cosine_similarity(a, b)
  assert_eq(similarity, 1.0)
}

///|
test "cosine_similarity with one empty vector is 0" {
  let a = TfidfVector::new()
  a.set("x", 1.0)
  let b = TfidfVector::new()
  let similarity = cosine_similarity(a, b)
  assert_eq(similarity, 0.0)
}

///|
test "cosine_distance of identical vectors is 0" {
  let vector = TfidfVector::new()
  vector.set("a", 1.0)
  vector.set("b", 2.0)
  let distance = cosine_distance(vector, vector)
  // Should be very close to 0.0
  assert_true(distance < 0.001)
}

///|
test "cosine_distance of orthogonal vectors is 1" {
  let a = TfidfVector::new()
  a.set("x", 1.0)
  let b = TfidfVector::new()
  b.set("y", 1.0)
  let distance = cosine_distance(a, b)
  assert_eq(distance, 1.0)
}

///|
test "calculate_adjacent_tfidf_distance with similar texts" {
  let texts = ["hello world", "hello there", "goodbye world"]
  let distances = calculate_adjacent_tfidf_distance(texts)
  assert_eq(distances.length(), 2)
  // First two texts share "hello", second and third share "world"
  assert_true(distances[0] >= 0.0)
  assert_true(distances[0] <= 1.0)
  assert_true(distances[1] >= 0.0)
  assert_true(distances[1] <= 1.0)
}

///|
test "calculate_adjacent_tfidf_distance with identical texts" {
  let texts = ["hello world", "hello world"]
  let distances = calculate_adjacent_tfidf_distance(texts)
  assert_eq(distances.length(), 1)
  // Identical texts should have distance close to 0
  assert_true(distances[0] < 0.01)
}

///|
test "calculate_adjacent_tfidf_distance with single text" {
  let texts = ["hello world"]
  let distances = calculate_adjacent_tfidf_distance(texts)
  assert_eq(distances.length(), 0)
}

///|
test "calculate_adjacent_tfidf_distance with empty array" {
  let texts : Array[String] = []
  let distances = calculate_adjacent_tfidf_distance(texts)
  assert_eq(distances.length(), 0)
}

///|
test "calculate_adjacent_tfidf_distance with japanese text" {
  let texts = ["日本語テスト", "日本語サンプル", "英語テスト"]
  let distances = calculate_adjacent_tfidf_distance(texts)
  assert_eq(distances.length(), 2)
  // First two share "日本" and "本語" bigrams
  // Second and third are more different
  assert_true(distances[0] >= 0.0)
  assert_true(distances[0] <= 1.0)
}

///|
test "TfidfVector from_terms creates vector with terms" {
  let terms : Map[String, Double] = {}
  terms.set("a", 1.0)
  terms.set("b", 2.0)
  let vector = TfidfVector::from_terms(terms)
  assert_eq(vector.length(), 2)
  assert_eq(vector.get("a"), 1.0)
  assert_eq(vector.get("b"), 2.0)
}
