// Explicit method promotion for trait impls (MoonBit warning 79,
// `implicit_impl_as_method`). Methods under "promoted" are called with dot
// syntax somewhere in this project; the rest are kept only as deprecated shims
// for the old implicit promotion and can be removed once it is gone.

// --- deprecated: hidden from the generated interface ---

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend Node with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend Node with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend Node with Eq::{equal}

///|
#deprecated("Use `Hash::hash` instead")
#doc(hidden)
pub extend Node with Hash::{hash}

///|
#deprecated("Use `Hash::hash_combine` instead")
#doc(hidden)
pub extend Node with Hash::{hash_combine}

///|
#deprecated("Use `Show::to_string` instead")
#doc(hidden)
pub extend Node with Show::{to_string}

///|
#deprecated("Use `Show::output` instead")
#doc(hidden)
pub extend Node with Show::{output}
