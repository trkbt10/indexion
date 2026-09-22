// Explicit method promotion for trait impls (MoonBit warning 79,
// `implicit_impl_as_method`). Methods under "promoted" are called with dot
// syntax somewhere in this project; the rest are kept only as deprecated shims
// for the old implicit promotion and can be removed once it is gone.

// --- deprecated: hidden from the generated interface ---

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend ModulePathStyle with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend ModulePathStyle with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend ModulePathStyle with Eq::{equal}

///|
#deprecated("Use `Show::to_string` instead")
#doc(hidden)
pub extend ModulePathStyle with Show::{to_string}

///|
#deprecated("Use `Show::output` instead")
#doc(hidden)
pub extend ModulePathStyle with Show::{output}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend ResolutionStats with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend ResolutionStats with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend ResolutionStats with Eq::{equal}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend ResolveStepType with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend ResolveStepType with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend ResolveStepType with Eq::{equal}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend LayoutSpec with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend LayoutSpec with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend LayoutSpec with Eq::{equal}
