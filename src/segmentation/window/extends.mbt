// Explicit method promotion for trait impls (MoonBit warning 79,
// `implicit_impl_as_method`). Methods under "promoted" are called with dot
// syntax somewhere in this project; the rest are kept only as deprecated shims
// for the old implicit promotion and can be removed once it is gone.

// --- deprecated: hidden from the generated interface ---

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend AdaptiveConfig with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend AdaptiveConfig with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend AdaptiveConfig with Eq::{equal}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend HybridAdaptiveConfig with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend HybridAdaptiveConfig with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend HybridAdaptiveConfig with Eq::{equal}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend SegmentConfig with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend SegmentConfig with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend SegmentConfig with Eq::{equal}

///|
#deprecated("Use `SegmentationStrategy::name` instead")
#doc(hidden)
pub extend WindowStrategy with @types.SegmentationStrategy::{name}

///|
#deprecated("Use `SegmentationStrategy::segment` instead")
#doc(hidden)
pub extend WindowStrategy with @types.SegmentationStrategy::{segment}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend WindowStrategy with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend WindowStrategy with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend WindowStrategy with Eq::{equal}
