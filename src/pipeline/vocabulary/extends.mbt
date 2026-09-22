// Explicit method promotion for trait impls (MoonBit warning 79,
// `implicit_impl_as_method`). Methods under "promoted" are called with dot
// syntax somewhere in this project; the rest are kept only as deprecated shims
// for the old implicit promotion and can be removed once it is gone.

// --- deprecated: hidden from the generated interface ---

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend DivergenceResult with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend DivergenceResult with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend DivergenceResult with Eq::{equal}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend GapConfig with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend GapConfig with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend GapConfig with Eq::{equal}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend GapTerm with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend GapTerm with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend GapTerm with Eq::{equal}
