// Type definitions for segmentation utilities.

///|
/// Options for finding sentence boundaries.
pub struct FindBoundariesOptions {
  /// Use extended terminators that include closing brackets.
  /// Default: false
  include_closing_brackets : Bool
  /// When true, punctuation inside Japanese quotes is not treated as a boundary
  /// unless quote length exceeds quote_safe_max_length.
  /// Default: true
  respect_japanese_quotes : Bool
  /// Maximum protected quote length.
  /// Default: 240
  quote_safe_max_length : Int
} derive(Eq, Show)

///|
/// Create new FindBoundariesOptions with default values.
pub fn FindBoundariesOptions::new() -> FindBoundariesOptions {
  {
    include_closing_brackets: false,
    respect_japanese_quotes: true,
    quote_safe_max_length: default_quote_safe_max_length,
  }
}

///|
/// Create FindBoundariesOptions with all parameters specified.
pub fn FindBoundariesOptions::create(
  include_closing_brackets : Bool,
  respect_japanese_quotes : Bool,
  quote_safe_max_length : Int,
) -> FindBoundariesOptions {
  { include_closing_brackets, respect_japanese_quotes, quote_safe_max_length }
}

///|
/// Get include_closing_brackets option.
pub fn FindBoundariesOptions::get_include_closing_brackets(
  self : FindBoundariesOptions,
) -> Bool {
  self.include_closing_brackets
}

///|
/// Get respect_japanese_quotes option.
pub fn FindBoundariesOptions::get_respect_japanese_quotes(
  self : FindBoundariesOptions,
) -> Bool {
  self.respect_japanese_quotes
}

///|
/// Get quote_safe_max_length option.
pub fn FindBoundariesOptions::get_quote_safe_max_length(
  self : FindBoundariesOptions,
) -> Int {
  self.quote_safe_max_length
}

///|
/// Entry in the quote tracking stack.
pub struct QuoteStackEntry {
  /// The opening quote character.
  open : Char
  /// The position where the quote started.
  start : Int
} derive(Eq, Show)

///|
/// Create a new QuoteStackEntry.
pub fn QuoteStackEntry::new(open : Char, start : Int) -> QuoteStackEntry {
  { open, start }
}

///|
/// Get the opening quote character.
pub fn QuoteStackEntry::get_open(self : QuoteStackEntry) -> Char {
  self.open
}

///|
/// Get the start position.
pub fn QuoteStackEntry::get_start(self : QuoteStackEntry) -> Int {
  self.start
}

///|
/// Default maximum length protected from punctuation splitting inside Japanese quotes.
pub let default_quote_safe_max_length : Int = 240
