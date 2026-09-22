// Explicit method promotion for trait impls (MoonBit warning 79,
// `implicit_impl_as_method`). Methods under "promoted" are called with dot
// syntax somewhere in this project; the rest are kept only as deprecated shims
// for the old implicit promotion and can be removed once it is gone.

// --- deprecated: hidden from the generated interface ---

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend SegmentPoint with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend SegmentPoint with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend SegmentPoint with Eq::{equal}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend SegmentType with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend SegmentType with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend SegmentType with Eq::{equal}

///|
#deprecated("Use `Show::to_string` instead")
#doc(hidden)
pub extend SegmentType with Show::{to_string}

///|
#deprecated("Use `Show::output` instead")
#doc(hidden)
pub extend SegmentType with Show::{output}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend Sentence with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend Sentence with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend Sentence with Eq::{equal}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend TextSegment with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend TextSegment with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend TextSegment with Eq::{equal}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend WindowDivergence with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend WindowDivergence with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend WindowDivergence with Eq::{equal}
