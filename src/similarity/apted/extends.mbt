// Explicit method promotion for trait impls (MoonBit warning 79,
// `implicit_impl_as_method`). Methods under "promoted" are called with dot
// syntax somewhere in this project; the rest are kept only as deprecated shims
// for the old implicit promotion and can be removed once it is gone.

// --- deprecated: hidden from the generated interface ---

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend CostConfig with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend CostConfig with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend CostConfig with Eq::{equal}

///|
#deprecated("Use `Show::to_string` instead")
#doc(hidden)
pub extend CostConfig with Show::{to_string}

///|
#deprecated("Use `Show::output` instead")
#doc(hidden)
pub extend CostConfig with Show::{output}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend IndexedTree with Debug::{to_repr}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend NodeInfo with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend NodeInfo with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend NodeInfo with Eq::{equal}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend TSEDConfig with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend TSEDConfig with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend TSEDConfig with Eq::{equal}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend TreeNode with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend TreeNode with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend TreeNode with Eq::{equal}
