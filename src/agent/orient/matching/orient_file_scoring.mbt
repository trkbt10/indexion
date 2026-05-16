///|
/// Score source file briefs against orientation task terms for report evidence.
pub fn orientation_score(
  task : String,
  summary : String,
  task_terms : Array[String],
  overlap : Int,
) -> Double {
  let docs = [
    @tokenizer.tokenize_for_tfidf(task),
    @tokenizer.tokenize_for_tfidf(summary),
  ]
  let batch = @tfidf.BM25Batch::from_tokens(docs)
  let lexical = if task_terms.is_empty() {
    0.0
  } else {
    overlap.to_double() / task_terms.length().to_double()
  }
  let score = lexical + batch.similarity(0, 1) * 0.1
  if score > 1.0 {
    1.0
  } else {
    score
  }
}

///|
pub fn score_briefs(
  briefs : Array[LocalFileBrief],
  task_terms : Array[String],
  task : String,
) -> Array[LocalFileBrief] {
  let result : Array[LocalFileBrief] = []
  for brief in briefs {
    let structural_matched = matched_terms_in_tokens(
      task_terms,
      brief.structural_terms,
    )
    let matched = if structural_matched.length() > 0 {
      structural_matched
    } else {
      matched_terms_in_tokens(task_terms, brief.summary_terms)
    }
    result.push({
      ..brief,
      score: orientation_score(
        task,
        brief.structural_summary,
        task_terms,
        matched.length(),
      ),
      matched_terms: matched,
    })
  }
  result
}
