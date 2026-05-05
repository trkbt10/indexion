///|
/// Text formatting: data to display string.
/// SoT for data-to-text transformations.

///|
/// Format a Double (0.0-1.0) as a percentage string (e.g. "75%").
/// Uses rounding: 0.755 → "76%".
pub fn format_percent(v : Double) -> String {
  let pct = (v * 100.0 + 0.5).to_int()
  pct.to_string() + "%"
}
