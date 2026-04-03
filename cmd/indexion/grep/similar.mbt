///|
/// Vector similarity search — find code similar to a natural language query.
/// Uses @text_embed.TfidfEmbeddingProvider (shared with digest).

///|
/// A function-level document for vector search.
priv struct FunctionDoc {
  file : String
  name : String
  line : Int
  text : String // function source text for embedding
}

///|
/// Run vector similarity search across the codebase.
pub fn run_similar_search(
  paths : Array[String],
  query_text : String,
  top_k : Int,
  config : GrepConfig,
) -> Unit {
  let registry = @kgf_features.load_registry(
    specs_dir=config.specs_dir,
    target_dirs=paths,
  )
  let reg = match registry {
    Some(r) => r
    None => {
      println("Error: No KGF specs found")
      return
    }
  }
  let files = collect_search_files(paths, config, reg)
  if files.length() == 0 {
    println("No files found")
    return
  }
  // Extract function-level documents from all files
  let docs : Array[FunctionDoc] = []
  for file in files {
    let (path, content) = file
    let tokens = match @kgf_features.tokenize_source(content, path, registry) {
      Some(t) => t
      None => continue
    }
    let functions = @kgf_features.extract_functions(tokens, path)
    let token_lines = build_token_lines(tokens)
    let lines = @common.split_lines(content)
    for func in functions {
      let start_line = if func.get_start() < token_lines.length() {
        token_lines[func.get_start()]
      } else {
        1
      }
      let end_line = if func.get_end() > 0 &&
        func.get_end() - 1 < token_lines.length() {
        token_lines[func.get_end() - 1]
      } else {
        lines.length()
      }
      // Extract function text for embedding
      let buf = StringBuilder::new()
      buf.write_string(func.get_name())
      buf.write_string(" ")
      let start_idx = start_line - 1
      let end_idx = if end_line > lines.length() { lines.length() } else { end_line }
      for i = start_idx; i < end_idx; i = i + 1 {
        if i < lines.length() {
          buf.write_string(lines[i])
          buf.write_string(" ")
        }
      }
      docs.push({
        file: path,
        name: func.get_name(),
        line: start_line,
        text: buf.to_string(),
      })
    }
  }
  if docs.length() == 0 {
    println("No functions found")
    return
  }
  // Build TF-IDF embedding provider from function corpus
  let dim = 256
  let provider = @text_embed.TfidfEmbeddingProvider::new(dim)
  let corpus_texts : Array[String] = []
  for doc in docs {
    corpus_texts.push(doc.text)
  }
  provider.build_vocabulary(corpus_texts)
  // Embed query
  let query_vector = provider.embed(query_text)
  // Embed all functions and compute similarity
  let scored : Array[(Int, Double)] = []
  for i, doc in docs {
    let doc_vector = provider.embed(doc.text)
    let sim = @text_embed.cosine_similarity_dense(query_vector, doc_vector)
    if sim > 0.0 {
      scored.push((i, sim))
    }
  }
  // Sort by similarity descending
  scored.sort_by(fn(a, b) {
    if b.1 > a.1 {
      1
    } else if b.1 < a.1 {
      -1
    } else {
      0
    }
  })
  // Output top-k results
  let limit = if top_k < scored.length() { top_k } else { scored.length() }
  for i = 0; i < limit; i = i + 1 {
    let (idx, sim) = scored[i]
    let doc = docs[idx]
    let score_str = @common.format_percent(sim)
    if config.files_only {
      println(doc.file)
    } else {
      println(
        doc.file +
        ":" +
        doc.line.to_string() +
        ": fn " +
        doc.name +
        "  (" +
        score_str +
        " similar)",
      )
    }
  }
  println("")
  println(
    limit.to_string() + " results from " + docs.length().to_string() +
    " functions",
  )
}
