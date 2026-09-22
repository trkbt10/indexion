// Explicit method promotion for trait impls (MoonBit warning 79,
// `implicit_impl_as_method`). Methods under "promoted" are called with dot
// syntax somewhere in this project; the rest are kept only as deprecated shims
// for the old implicit promotion and can be removed once it is gone.

// --- deprecated: hidden from the generated interface ---

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend BatchConfig with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend BatchConfig with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend BatchConfig with Eq::{equal}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend BatchResult with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend BatchResult with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend BatchResult with Eq::{equal}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend FileEntry with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend FileEntry with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend FileEntry with Eq::{equal}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend SimilarityMatch with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend SimilarityMatch with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend SimilarityMatch with Eq::{equal}
