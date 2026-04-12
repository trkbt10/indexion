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

pub fn clamp(value : Int, min_val : Int, max_val : Int) -> Int {
  if value < min_val {
    min_val
  } else if value > max_val {
    max_val
  } else {
    value
  }
}
