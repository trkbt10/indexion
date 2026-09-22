// Explicit method promotion for trait impls (MoonBit warning 79,
// `implicit_impl_as_method`). Methods under "promoted" are called with dot
// syntax somewhere in this project; the rest are kept only as deprecated shims
// for the old implicit promotion and can be removed once it is gone.

// --- promoted: kept as regular methods (blessed public API) ---

///|
pub extend AgentOrientMap with ToJson::{to_json}

///|
pub extend AgentOrientReport with ToJson::{to_json}

// --- deprecated: hidden from the generated interface ---

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend AgentOrientConfig with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend AgentOrientConfig with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend AgentOrientConfig with Eq::{equal}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend AgentOrientEvidence with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend AgentOrientEvidence with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend AgentOrientEvidence with Eq::{equal}

///|
#deprecated("Use `ToJson::to_json` instead")
#doc(hidden)
pub extend AgentOrientEvidence with ToJson::{to_json}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend AgentOrientItem with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend AgentOrientItem with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend AgentOrientItem with Eq::{equal}

///|
#deprecated("Use `ToJson::to_json` instead")
#doc(hidden)
pub extend AgentOrientItem with ToJson::{to_json}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend AgentOrientMap with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend AgentOrientMap with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend AgentOrientMap with Eq::{equal}

///|
#deprecated("Use `FromJson::from_json` instead")
#doc(hidden)
pub extend AgentOrientMap with FromJson::{from_json}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend AgentOrientMapFile with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend AgentOrientMapFile with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend AgentOrientMapFile with Eq::{equal}

///|
#deprecated("Use `FromJson::from_json` instead")
#doc(hidden)
pub extend AgentOrientMapFile with FromJson::{from_json}

///|
#deprecated("Use `ToJson::to_json` instead")
#doc(hidden)
pub extend AgentOrientMapFile with ToJson::{to_json}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend AgentOrientMapOwner with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend AgentOrientMapOwner with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend AgentOrientMapOwner with Eq::{equal}

///|
#deprecated("Use `FromJson::from_json` instead")
#doc(hidden)
pub extend AgentOrientMapOwner with FromJson::{from_json}

///|
#deprecated("Use `ToJson::to_json` instead")
#doc(hidden)
pub extend AgentOrientMapOwner with ToJson::{to_json}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend AgentOrientMapStatus with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend AgentOrientMapStatus with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend AgentOrientMapStatus with Eq::{equal}

///|
#deprecated("Use `FromJson::from_json` instead")
#doc(hidden)
pub extend AgentOrientMapStatus with FromJson::{from_json}

///|
#deprecated("Use `ToJson::to_json` instead")
#doc(hidden)
pub extend AgentOrientMapStatus with ToJson::{to_json}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend AgentOrientQuizItem with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend AgentOrientQuizItem with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend AgentOrientQuizItem with Eq::{equal}

///|
#deprecated("Use `ToJson::to_json` instead")
#doc(hidden)
pub extend AgentOrientQuizItem with ToJson::{to_json}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend AgentOrientReport with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend AgentOrientReport with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend AgentOrientReport with Eq::{equal}
