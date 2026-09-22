// Explicit method promotion for trait impls (MoonBit warning 79,
// `implicit_impl_as_method`). Methods under "promoted" are called with dot
// syntax somewhere in this project; the rest are kept only as deprecated shims
// for the old implicit promotion and can be removed once it is gone.

// --- promoted: kept as regular methods (blessed public API) ---

///|
pub extend IdentityAuditReport with ToJson::{to_json}

///|
pub extend NameDivergence with ToJson::{to_json}

// --- deprecated: hidden from the generated interface ---

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend IdentityAuditCandidate with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend IdentityAuditCandidate with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend IdentityAuditCandidate with Eq::{equal}

///|
#deprecated("Use `ToJson::to_json` instead")
#doc(hidden)
pub extend IdentityAuditCandidate with ToJson::{to_json}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend IdentityAuditConfig with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend IdentityAuditConfig with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend IdentityAuditConfig with Eq::{equal}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend IdentityAuditReport with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend IdentityAuditReport with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend IdentityAuditReport with Eq::{equal}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend IdentityAuditSummary with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend IdentityAuditSummary with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend IdentityAuditSummary with Eq::{equal}

///|
#deprecated("Use `ToJson::to_json` instead")
#doc(hidden)
pub extend IdentityAuditSummary with ToJson::{to_json}

///|
#deprecated("Use `ToJson::to_json` instead")
#doc(hidden)
pub extend Name with ToJson::{to_json}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend NameAction with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend NameAction with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend NameAction with Eq::{equal}

///|
#deprecated("Use `ToJson::to_json` instead")
#doc(hidden)
pub extend NameAction with ToJson::{to_json}

///|
#deprecated("Use `ToJson::to_json` instead")
#doc(hidden)
pub extend NamedEntity with ToJson::{to_json}
