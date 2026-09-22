// Explicit method promotion for trait impls (MoonBit warning 79,
// `implicit_impl_as_method`). Methods under "promoted" are called with dot
// syntax somewhere in this project; the rest are kept only as deprecated shims
// for the old implicit promotion and can be removed once it is gone.

// --- deprecated: hidden from the generated interface ---

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend AnalysisResult with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend AnalysisResult with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend AnalysisResult with Eq::{equal}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend DetectedLang with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend DetectedLang with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend DetectedLang with Eq::{equal}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend DocSymbol with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend DocSymbol with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend DocSymbol with Eq::{equal}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend FileInfo with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend FileInfo with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend FileInfo with Eq::{equal}
