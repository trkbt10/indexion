// Explicit method promotion for trait impls (MoonBit warning 79,
// `implicit_impl_as_method`). `TargetSnapshot` is private to this package, so
// the promotion stays package-local.

///|
extend TargetSnapshot with ToJson::{to_json}
