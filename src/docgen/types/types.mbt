// Type definitions for README dynamic build system.
// Ported from react-editor-ui/scripts/build-readme.ts

///|
/// Documentation extracted from source file comments.
/// Represents a component or module with its documentation.
pub struct ComponentDoc {
  /// Name of the component/module.
  name : String
  /// File tag from @file comment (optional).
  file_tag : String?
  /// Description from @description comment (optional).
  description : String?
  /// Example code from @example comment (optional).
  example : String?
} derive(Eq, Show)

///|
/// Create a new ComponentDoc with required name.
pub fn ComponentDoc::new(name : String) -> ComponentDoc {
  { name, file_tag: None, description: None, example: None }
}

///|
/// Create a ComponentDoc with all fields.
pub fn ComponentDoc::make(
  name : String,
  file_tag : String?,
  description : String?,
  example : String?,
) -> ComponentDoc {
  { name, file_tag, description, example }
}

///|
/// Get the name.
pub fn ComponentDoc::get_name(self : ComponentDoc) -> String {
  self.name
}

///|
/// Get the file tag.
pub fn ComponentDoc::get_file_tag(self : ComponentDoc) -> String? {
  self.file_tag
}

///|
/// Get the description.
pub fn ComponentDoc::get_description(self : ComponentDoc) -> String? {
  self.description
}

///|
/// Get the example.
pub fn ComponentDoc::get_example(self : ComponentDoc) -> String? {
  self.example
}

///|
/// Information about a design token (CSS variable).
pub struct TokenInfo {
  /// Name of the token.
  name : String
  /// CSS variable name (e.g., "--rei-spacing").
  css_var : String
  /// Description of the token's purpose.
  description : String
  /// Default value if any.
  default_value : String?
} derive(Eq, Show)

///|
/// Create a new TokenInfo.
pub fn TokenInfo::new(
  name : String,
  css_var : String,
  description : String,
) -> TokenInfo {
  { name, css_var, description, default_value: None }
}

///|
/// Create a TokenInfo with default value.
pub fn TokenInfo::with_default(
  name : String,
  css_var : String,
  description : String,
  default_value : String,
) -> TokenInfo {
  { name, css_var, description, default_value: Some(default_value) }
}

///|
/// Get the name.
pub fn TokenInfo::get_name(self : TokenInfo) -> String {
  self.name
}

///|
/// Get the CSS variable.
pub fn TokenInfo::get_css_var(self : TokenInfo) -> String {
  self.css_var
}

///|
/// Get the description.
pub fn TokenInfo::get_description(self : TokenInfo) -> String {
  self.description
}

///|
/// Get the default value.
pub fn TokenInfo::get_default_value(self : TokenInfo) -> String? {
  self.default_value
}

///|
/// A group of related tokens.
pub struct TokenGroup {
  /// Name of the token group (e.g., "Spacing", "Colors").
  name : String
  /// Description of the group's purpose.
  description : String
  /// Tokens in this group.
  tokens : Array[TokenInfo]
} derive(Eq, Show)

///|
/// Create a new TokenGroup.
pub fn TokenGroup::new(name : String, description : String) -> TokenGroup {
  { name, description, tokens: [] }
}

///|
/// Create a TokenGroup with tokens.
pub fn TokenGroup::with_tokens(
  name : String,
  description : String,
  tokens : Array[TokenInfo],
) -> TokenGroup {
  { name, description, tokens }
}

///|
/// Get the name.
pub fn TokenGroup::get_name(self : TokenGroup) -> String {
  self.name
}

///|
/// Get the description.
pub fn TokenGroup::get_description(self : TokenGroup) -> String {
  self.description
}

///|
/// Get the tokens.
pub fn TokenGroup::get_tokens(self : TokenGroup) -> Array[TokenInfo] {
  self.tokens
}

///|
/// Add a token to the group.
pub fn TokenGroup::add_token(self : TokenGroup, token : TokenInfo) -> Unit {
  self.tokens.push(token)
}
