///|
fn round_ties_even_f32(v : Double) -> Int {
  @math.round_ties_even_f32(v)
}

///|
fn Type::f32bits_hex(v : Double) -> String {
  @math.Type::f32bits_hex(v)
}

///|
fn zero_arg_proxy() -> String {
  @util.get_default()
}

///|
fn multi_param(a : Int, b : String, c : Double) -> Bool {
  @checker.validate(a, b, c)
}
