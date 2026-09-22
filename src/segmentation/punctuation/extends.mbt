// Explicit method promotion for trait impls (MoonBit warning 79,
// `implicit_impl_as_method`). Methods under "promoted" are called with dot
// syntax somewhere in this project; the rest are kept only as deprecated shims
// for the old implicit promotion and can be removed once it is gone.

// --- deprecated: hidden from the generated interface ---

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend PunctuationConfig with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend PunctuationConfig with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend PunctuationConfig with Eq::{equal}

///|
#deprecated("Use `Show::to_string` instead")
#doc(hidden)
pub extend PunctuationConfig with Show::{to_string}

///|
#deprecated("Use `Show::output` instead")
#doc(hidden)
pub extend PunctuationConfig with Show::{output}

///|
#deprecated("Use `SegmentationStrategy::name` instead")
#doc(hidden)
pub extend PunctuationStrategy with @types.SegmentationStrategy::{name}

///|
#deprecated("Use `SegmentationStrategy::segment` instead")
#doc(hidden)
pub extend PunctuationStrategy with @types.SegmentationStrategy::{segment}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend PunctuationStrategy with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend PunctuationStrategy with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend PunctuationStrategy with Eq::{equal}
