///|
fn transform(v : Double) -> Int {
  let rounded = @math.round_ties_even_f32(v)
  rounded + 1
}

///|
fn validated(v : Double) -> Int {
  if v > 0.0 {
    @math.round_ties_even_f32(v)
  } else {
    0
  }
}

///|
fn with_expr_arg(v : Double) -> Int {
  @math.round_ties_even_f32(v + 1.0)
}

///|
fn real_logic(a : Int, b : Int) -> Int {
  a + b
}
