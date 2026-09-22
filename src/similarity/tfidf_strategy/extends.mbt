// Explicit method promotion for trait impls (MoonBit warning 79,
// `implicit_impl_as_method`). Methods under "promoted" are called with dot
// syntax somewhere in this project; the rest are kept only as deprecated shims
// for the old implicit promotion and can be removed once it is gone.

// --- promoted: kept as regular methods (blessed public API) ---

///|
pub extend TfidfStrategy with @types.SimilarityStrategy::{
  name,
  distance,
  similarity,
}

// --- deprecated: hidden from the generated interface ---

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend TfidfStrategy with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend TfidfStrategy with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend TfidfStrategy with Eq::{equal}
