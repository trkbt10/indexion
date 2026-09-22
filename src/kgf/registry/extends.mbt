// Explicit method promotion for trait impls (MoonBit warning 79,
// `implicit_impl_as_method`). Methods under "promoted" are called with dot
// syntax somewhere in this project; the rest are kept only as deprecated shims
// for the old implicit promotion and can be removed once it is gone.
//
// `ExtendsError` is only ever compared and printed through the trait methods,
// so every promotion here is deprecated.

// --- deprecated: hidden from the generated interface ---

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend ExtendsError with Debug::{to_repr}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend ExtendsError with Eq::{equal}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend ExtendsError with Eq::{not_equal}
