pub fn sum(arr : Array[Int]) -> Int {
  let mut total = 0
  for v in arr {
    total += v
  }
  total
}

pub fn average(arr : Array[Int]) -> Double {
  if arr.length() == 0 {
    return 0.0
  }
  sum(arr).to_double() / arr.length().to_double()
}

pub fn clamp(value : Int, lo : Int, hi : Int) -> Int {
  if value < lo {
    lo
  } else if value > hi {
    hi
  } else {
    value
  }
}
