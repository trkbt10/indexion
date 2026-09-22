// Explicit method promotion for trait impls (MoonBit warning 79,
// `implicit_impl_as_method`). Methods under "promoted" are called with dot
// syntax somewhere in this project; the rest are kept only as deprecated shims
// for the old implicit promotion and can be removed once it is gone.

// --- deprecated: hidden from the generated interface ---

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend Arch with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend Arch with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend Arch with Eq::{equal}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend Platform with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend Platform with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend Platform with Eq::{equal}
