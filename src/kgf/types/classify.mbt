///|
/// ClassifyModel represents a trained classification model persisted in
/// a KGF `=== classify` section.
///
/// This is NOT a hand-authored vocabulary list. The weights are computed
/// from a document corpus by a training process (e.g., `indexion classify train`)
/// and serialized into the KGF spec for later inference.
///
/// ## Model structure
///
/// A model consists of:
/// - **Metadata**: model type, training parameters, corpus statistics
/// - **Classes**: named classification categories, each with:
///   - A prior log-probability (base rate from training corpus)
///   - A vocabulary of terms with conditional log-probabilities P(term|class)
///
/// ## Inference
///
/// Given a text to classify, a consumer:
/// 1. Tokenizes the text into terms
/// 2. For each class, sums the prior + Σ log P(term|class) for observed terms
/// 3. The class with the highest posterior score wins
///
/// The model is agnostic to what the classes represent — normative vs. meta,
/// requirement vs. boilerplate, etc. Class semantics are determined by the
/// KGF spec author and the training corpus.
pub struct ClassifyModel {
  /// Model metadata (model_type, corpus_size, etc.)
  metadata : Map[String, String]
  /// Classification classes: name → class definition
  classes : Map[String, ClassifyClass]
}

///|
/// A single classification class with its prior and vocabulary.
pub struct ClassifyClass {
  /// Log-probability prior for this class: ln(P(class))
  /// Computed from the fraction of training documents in this class.
  prior : Double
  /// Vocabulary: term → conditional log-probability ln(P(term|class))
  /// Terms not in this map receive a smoothed default probability.
  vocab : Map[String, Double]
}

///|
pub fn ClassifyModel::new(
  metadata : Map[String, String],
  classes : Map[String, ClassifyClass],
) -> ClassifyModel {
  { metadata, classes }
}

///|
pub fn ClassifyModel::get_metadata(self : ClassifyModel) -> Map[String, String] {
  self.metadata
}

///|
/// Returns a metadata value by key, or None.
pub fn ClassifyModel::get_meta(self : ClassifyModel, key : String) -> String? {
  self.metadata.get(key)
}

///|
/// Returns all class names.
pub fn ClassifyModel::get_class_names(self : ClassifyModel) -> Array[String] {
  let names : Array[String] = []
  for entry in self.classes {
    names.push(entry.0)
  }
  names
}

///|
/// Returns a class definition by name.
pub fn ClassifyModel::get_class(
  self : ClassifyModel,
  name : String,
) -> ClassifyClass? {
  self.classes.get(name)
}

///|
/// Returns true if this model has no classes.
pub fn ClassifyModel::is_empty(self : ClassifyModel) -> Bool {
  self.classes.is_empty()
}

///|
/// Classify a tokenized text by computing posterior scores for each class.
/// Returns an array of (class_name, score) pairs sorted by descending score.
///
/// The score for each class is: prior + Σ vocab[term] for observed terms.
/// Terms not in the class vocabulary contribute 0 (equivalent to uniform
/// smoothing at the training-time default).
pub fn ClassifyModel::classify(
  self : ClassifyModel,
  tokens : Array[String],
) -> Array[(String, Double)] {
  let scores : Array[(String, Double)] = []
  for entry in self.classes {
    let class_name = entry.0
    let class_def = entry.1
    let mut score = class_def.prior
    for token in tokens {
      score += class_def.vocab.get(token).unwrap_or(0.0)
    }
    scores.push((class_name, score))
  }
  scores.sort_by(fn(a, b) {
    if a.1 > b.1 {
      -1
    } else if a.1 < b.1 {
      1
    } else {
      0
    }
  })
  scores
}

///|
/// Returns the predicted class name (highest posterior score).
/// Returns None if the model has no classes.
pub fn ClassifyModel::predict(
  self : ClassifyModel,
  tokens : Array[String],
) -> String? {
  let scores = self.classify(tokens)
  if scores.length() > 0 {
    Some(scores[0].0)
  } else {
    None
  }
}

///|
pub fn ClassifyClass::new(
  prior : Double,
  vocab : Map[String, Double],
) -> ClassifyClass {
  { prior, vocab }
}

///|
pub fn ClassifyClass::get_prior(self : ClassifyClass) -> Double {
  self.prior
}

///|
pub fn ClassifyClass::get_vocab(self : ClassifyClass) -> Map[String, Double] {
  self.vocab
}

///|
/// Returns the conditional log-probability of a term in this class.
/// Returns 0.0 for unknown terms (smoothed default).
pub fn ClassifyClass::term_weight(
  self : ClassifyClass,
  term : String,
) -> Double {
  self.vocab.get(term).unwrap_or(0.0)
}
