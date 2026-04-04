///|
/// # Inline Search
///
/// Lightweight vector similarity search without vcdb.
/// Builds TF-IDF vocabulary in-memory, computes cosine similarity directly.
/// Used by `grep --semantic=similar:` for quick one-shot searches.

///|
/// Search documents by natural language query using TF-IDF cosine similarity.
/// No persistent index — builds vocabulary on the fly and scores all documents.
pub fn inline_search(
  documents : Array[SearchDocument],
  query : String,
  top_k : Int,
  dim? : Int = 256,
) -> Array[SearchHit] {
  if documents.is_empty() {
    return []
  }
  let provider = @text_embed.TfidfEmbeddingProvider::new(dim)
  let corpus : Array[String] = []
  for doc in documents {
    corpus.push(doc.text)
  }
  provider.build_vocabulary(corpus)
  let query_vector = provider.embed(query)
  let scored : Array[(Int, Double)] = []
  for i, doc in documents {
    let doc_vector = provider.embed(doc.text)
    let sim = @text_embed.cosine_similarity_dense(query_vector, doc_vector)
    if sim > 0.0 {
      scored.push((i, sim))
    }
  }
  scored.sort_by(fn(a, b) {
    if b.1 > a.1 {
      1
    } else if b.1 < a.1 {
      -1
    } else {
      0
    }
  })
  let limit = if top_k < scored.length() { top_k } else { scored.length() }
  let results : Array[SearchHit] = []
  for i in 0..<limit {
    let (idx, sim) = scored[i]
    results.push({ document: documents[idx], score: sim })
  }
  results
}
