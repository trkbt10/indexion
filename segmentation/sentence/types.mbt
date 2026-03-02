// Type definitions for sentence segmentation.

///|
/// A sentence extracted from text with position information.
pub struct Sentence {
  /// The text content of the sentence.
  text : String
  /// Start position (byte offset) in the original text.
  start : Int
  /// End position (byte offset) in the original text (exclusive).
  end : Int
} derive(Eq, Show)

///|
/// Create a new Sentence.
pub fn Sentence::new(text : String, start : Int, end : Int) -> Sentence {
  { text, start, end }
}

///|
/// Get the text content of the sentence.
pub fn Sentence::get_text(self : Sentence) -> String {
  self.text
}

///|
/// Get the start position.
pub fn Sentence::get_start(self : Sentence) -> Int {
  self.start
}

///|
/// Get the end position.
pub fn Sentence::get_end(self : Sentence) -> Int {
  self.end
}

///|
/// Get the length of the sentence text.
pub fn Sentence::length(self : Sentence) -> Int {
  self.text.length()
}
