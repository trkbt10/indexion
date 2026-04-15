///|
/// Train a Naive Bayes classification model from labeled document sections.
///
/// The training process:
/// 1. Interprets each document using the KGF spec to extract sections
/// 2. Uses `document_section_role` facts as class labels
/// 3. Sections without a role label are assigned to the default class
/// 4. Computes Naive Bayes conditional log-probabilities with Laplace smoothing
/// 5. Returns a `ClassifyModel` ready for persistence in `=== classify`
///
/// ## Label mapping
///
/// KGF `document_section_role` values map directly to class names.
/// For example, role="meta" → class "meta", role="reference" → class "reference".
/// Unlabeled sections get the `default_class` label (typically "normative").

///|
/// Training corpus entry: a single labeled section.
priv struct TrainingSample {
  tokens : Array[String]
  label : String
}

///|
/// Train a classify model from document files.
///
/// Parameters:
/// - `files`: Array of (path, content) pairs for training documents
/// - `spec`: The KGF spec to use for document interpretation
/// - `registry`: KGF registry for section extraction
/// - `default_class`: Label for sections without a `document_section_role`
///
/// Returns a trained ClassifyModel, or None if no training data was found.
pub fn train(
  files : Array[(String, String)],
  spec : @kgf_types.KGFSpec,
  registry : @registry.KGFRegistry,
  default_class : String,
  min_weight~ : Double = 0.0,
) -> @kgf_types.ClassifyModel? {
  let samples = collect_samples(files, spec, registry, default_class)
  if samples.length() == 0 {
    return None
  }
  Some(fit_naive_bayes(samples, files.length(), min_weight))
}

///|
/// Collect labeled training samples from documents.
fn collect_samples(
  files : Array[(String, String)],
  spec : @kgf_types.KGFSpec,
  registry : @registry.KGFRegistry,
  default_class : String,
) -> Array[TrainingSample] {
  let samples : Array[TrainingSample] = []
  for file in files {
    let path = file.0
    let content = file.1
    // Interpret document to get facts (including document_section_role)
    let interpreted = @doc_structure.interpret_document(content, path, spec)
    // Extract role labels by line
    let roles : Map[Int, String] = {}
    for fact in interpreted.facts {
      if fact.kind != "document_section_role" {
        continue
      }
      let line = json_int(fact.payload, "line")
      let role = json_str(fact.payload, "role")
      if line > 0 && role.length() > 0 {
        roles.set(line, role)
      }
    }
    // Extract sections and pair with labels
    let sections = @doc_structure.load_document_sections(
      content,
      path,
      Some(registry),
    )
    for section in sections {
      let title = section.title.trim().to_string()
      if title.length() == 0 {
        continue
      }
      let label = roles.get(section.line).unwrap_or(default_class)
      let tokens = tokenize_for_training(section.content)
      if tokens.length() > 0 {
        samples.push({ tokens, label })
      }
    }
  }
  samples
}

///|
/// Fit a Naive Bayes model from labeled samples.
///
/// Uses Laplace smoothing (add-1) to handle unseen terms.
/// All weights are stored as log-probabilities.
fn fit_naive_bayes(
  samples : Array[TrainingSample],
  corpus_file_count : Int,
  min_weight : Double,
) -> @kgf_types.ClassifyModel {
  // Count documents per class
  let class_counts : Map[String, Int] = {}
  for sample in samples {
    let count = class_counts.get(sample.label).unwrap_or(0)
    class_counts.set(sample.label, count + 1)
  }
  let total_samples = samples.length()
  // Count term occurrences per class and total terms per class
  let class_term_counts : Map[String, Map[String, Int]] = {}
  let class_total_terms : Map[String, Int] = {}
  for sample in samples {
    let term_counts = match class_term_counts.get(sample.label) {
      Some(existing) => existing
      None => {
        let m : Map[String, Int] = {}
        class_term_counts.set(sample.label, m)
        m
      }
    }
    let mut total = class_total_terms.get(sample.label).unwrap_or(0)
    for token in sample.tokens {
      let count = term_counts.get(token).unwrap_or(0)
      term_counts.set(token, count + 1)
      total += 1
    }
    class_total_terms.set(sample.label, total)
  }
  // Build global vocabulary
  let global_vocab : Map[String, Bool] = {}
  for entry in class_term_counts {
    for term_entry in entry.1 {
      global_vocab.set(term_entry.0, true)
    }
  }
  let vocab_size = global_vocab.size()
  // Compute model parameters
  let classes : Map[String, @kgf_types.ClassifyClass] = {}
  for entry in class_counts {
    let class_name = entry.0
    let class_count = entry.1
    // Prior: ln(P(class)) = ln(class_count / total_samples)
    let prior = ln(class_count.to_double() / total_samples.to_double())
    // Conditional probabilities with Laplace smoothing:
    // P(term|class) = (count(term, class) + 1) / (total_terms_in_class + vocab_size)
    let term_counts = class_term_counts.get(class_name).unwrap_or({})
    let total_terms = class_total_terms.get(class_name).unwrap_or(0)
    let denominator = total_terms.to_double() + vocab_size.to_double()
    let vocab : Map[String, Double] = {}
    // Only store terms that appear in this class (sparse representation)
    // Terms not stored get implicit weight = ln(1 / denominator) at inference
    // which is the Laplace-smoothed probability for unseen terms.
    // We store the DIFFERENCE from this baseline so inference just adds vocab[term].
    let baseline = ln(1.0 / denominator)
    for term_entry in term_counts {
      let term = term_entry.0
      let count = term_entry.1
      let log_prob = ln((count.to_double() + 1.0) / denominator)
      // Store delta from baseline so that missing terms contribute 0
      let delta = log_prob - baseline
      if delta > min_weight && delta.abs() > 0.0001 {
        vocab.set(term, delta)
      }
    }
    classes.set(class_name, @kgf_types.ClassifyClass::new(prior, vocab))
  }
  // Build metadata
  let metadata : Map[String, String] = {}
  metadata.set("model_type", "naive_bayes")
  metadata.set("smoothing", "laplace")
  metadata.set("corpus_files", corpus_file_count.to_string())
  metadata.set("corpus_sections", total_samples.to_string())
  metadata.set("vocabulary_size", vocab_size.to_string())
  let class_names : Array[String] = []
  for entry in class_counts {
    class_names.push(entry.0)
  }
  class_names.sort()
  metadata.set("classes", class_names.join(","))
  @kgf_types.ClassifyModel::new(metadata, classes)
}

///|
/// Serialize a ClassifyModel to the `=== classify` KGF section format.
pub fn serialize_classify_section(model : @kgf_types.ClassifyModel) -> String {
  let buf = StringBuilder::new()
  // Metadata
  let meta = model.get_metadata()
  let meta_keys : Array[String] = []
  for entry in meta {
    meta_keys.push(entry.0)
  }
  meta_keys.sort()
  for key in meta_keys {
    let value = meta.get(key).unwrap_or("")
    buf.write_string(key)
    buf.write_string(" = ")
    buf.write_string(value)
    buf.write_char('\n')
  }
  // Classes
  let class_names = model.get_class_names()
  class_names.sort()
  for class_name in class_names {
    let cls = model.get_class(class_name).unwrap()
    buf.write_char('\n')
    buf.write_char('@')
    buf.write_string(class_name)
    buf.write_string(" prior=")
    buf.write_string(format_double(cls.get_prior(), 6))
    buf.write_char('\n')
    // Sort vocab by weight descending (most discriminative first)
    let vocab = cls.get_vocab()
    let entries : Array[(String, Double)] = []
    for entry in vocab {
      entries.push((entry.0, entry.1))
    }
    entries.sort_by(fn(a, b) {
      if a.1 > b.1 {
        -1
      } else if a.1 < b.1 {
        1
      } else {
        a.0.compare(b.0)
      }
    })
    for entry in entries {
      buf.write_string("  ")
      buf.write_string(entry.0)
      buf.write_char('=')
      buf.write_string(format_double(entry.1, 6))
      buf.write_char('\n')
    }
  }
  buf.to_string()
}

///|
/// Tokenize text into lowercase words for training.
/// Extracts words of 2+ characters, lowercased.
fn tokenize_for_training(text : String) -> Array[String] {
  let words : Array[String] = []
  let buf = StringBuilder::new()
  for c in text {
    if (c >= 'a' && c <= 'z') ||
      (c >= 'A' && c <= 'Z') ||
      (c >= '0' && c <= '9') {
      let lower : Char = if c >= 'A' && c <= 'Z' {
        Char::from_int(c.to_int() + 32)
      } else {
        c
      }
      buf.write_char(lower)
    } else {
      let word = buf.to_string()
      if word.length() >= 2 {
        words.push(word)
      }
      buf.reset()
    }
  }
  let word = buf.to_string()
  if word.length() >= 2 {
    words.push(word)
  }
  words
}

///|
/// Natural logarithm.
fn ln(x : Double) -> Double {
  if x <= 0.0 {
    return -1000.0 // Avoid -infinity, use large negative
  }
  @math.ln(x)
}

///|
/// Format a Double with fixed decimal places.
fn format_double(value : Double, decimals : Int) -> String {
  let is_negative = value < 0.0
  let abs_val = if is_negative { -value } else { value }
  let mut multiplier = 1.0
  for i = 0; i < decimals; i = i + 1 {
    multiplier *= 10.0
  }
  let rounded = (abs_val * multiplier + 0.5).to_int()
  let integer_part = rounded / multiplier.to_int()
  let decimal_part = rounded % multiplier.to_int()
  let buf = StringBuilder::new()
  if is_negative {
    buf.write_char('-')
  }
  buf.write_string(integer_part.to_string())
  buf.write_char('.')
  // Pad decimal part with leading zeros
  let dec_str = decimal_part.to_string()
  for i = dec_str.length(); i < decimals; i = i + 1 {
    buf.write_char('0')
  }
  buf.write_string(dec_str)
  buf.to_string()
}

///|
/// Extract an integer from a JSON payload.
fn json_int(payload : Map[String, Json], key : String) -> Int {
  match payload.get(key) {
    Some(Number(value, ..)) => value.to_int()
    _ => 0
  }
}

///|
/// Extract a string from a JSON payload.
fn json_str(payload : Map[String, Json], key : String) -> String {
  match payload.get(key) {
    Some(String(value)) => value
    _ => ""
  }
}
