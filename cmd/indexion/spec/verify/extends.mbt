// Explicit method promotion for trait impls (MoonBit warning 79,
// `implicit_impl_as_method`). Methods under "promoted" are called with dot
// syntax somewhere in this project; the rest are kept only as deprecated shims
// for the old implicit promotion and can be removed once it is gone.

// --- promoted: kept as regular methods (blessed public API) ---

///|
pub extend VerifyReport with ToJson::{to_json}

// --- deprecated: hidden from the generated interface ---

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend ImplEvidence with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend ImplEvidence with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend ImplEvidence with Eq::{equal}

///|
#deprecated("Use `FromJson::from_json` instead")
#doc(hidden)
pub extend ImplEvidence with FromJson::{from_json}

///|
#deprecated("Use `ToJson::to_json` instead")
#doc(hidden)
pub extend ImplEvidence with ToJson::{to_json}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend SpecSymbol with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend SpecSymbol with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend SpecSymbol with Eq::{equal}

///|
#deprecated("Use `FromJson::from_json` instead")
#doc(hidden)
pub extend SpecSymbol with FromJson::{from_json}

///|
#deprecated("Use `ToJson::to_json` instead")
#doc(hidden)
pub extend SpecSymbol with ToJson::{to_json}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend VerifyConfig with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend VerifyConfig with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend VerifyConfig with Eq::{equal}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend VerifyItem with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend VerifyItem with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend VerifyItem with Eq::{equal}

///|
#deprecated("Use `FromJson::from_json` instead")
#doc(hidden)
pub extend VerifyItem with FromJson::{from_json}

///|
#deprecated("Use `ToJson::to_json` instead")
#doc(hidden)
pub extend VerifyItem with ToJson::{to_json}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend VerifyReport with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend VerifyReport with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend VerifyReport with Eq::{equal}

///|
#deprecated("Use `FromJson::from_json` instead")
#doc(hidden)
pub extend VerifyReport with FromJson::{from_json}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend VerifyReportConfig with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend VerifyReportConfig with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend VerifyReportConfig with Eq::{equal}

///|
#deprecated("Use `FromJson::from_json` instead")
#doc(hidden)
pub extend VerifyReportConfig with FromJson::{from_json}

///|
#deprecated("Use `ToJson::to_json` instead")
#doc(hidden)
pub extend VerifyReportConfig with ToJson::{to_json}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend VerifySummary with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend VerifySummary with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend VerifySummary with Eq::{equal}

///|
#deprecated("Use `FromJson::from_json` instead")
#doc(hidden)
pub extend VerifySummary with FromJson::{from_json}

///|
#deprecated("Use `ToJson::to_json` instead")
#doc(hidden)
pub extend VerifySummary with ToJson::{to_json}
