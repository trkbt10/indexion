///|
/// KGF tokenizer library for JS target.
/// Provides tokenize function callable from JavaScript.

///|
/// Tokenize source code using a KGF spec string.
/// Returns a JSON string: [{"kind":"...","text":"...","pos":N}, ...]
pub fn tokenize(spec_text : String, source : String) -> String {
  let spec = match @parser.parse_kgf(spec_text) {
    Some(s) => s
    None => return "[]"
  }
  let lexer = @lexer.Lexer::for_spec(spec)
  let toks = lexer.tokenize(source)
  let arr : Array[Json] = toks
    .iter()
    .map(fn(tok) {
      let obj : Map[String, Json] = {}
      obj["kind"] = tok.kind.to_json()
      obj["text"] = tok.text.to_json()
      obj["pos"] = tok.pos.to_json()
      Json::object(obj)
    })
    .collect()
  Json::array(arr).stringify()
}

///|
fn main {
  ()
}
