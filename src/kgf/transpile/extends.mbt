// Explicit method promotion for trait impls (MoonBit warning 79,
// `implicit_impl_as_method`). Methods under "promoted" are called with dot
// syntax somewhere in this project; the rest are kept only as deprecated shims
// for the old implicit promotion and can be removed once it is gone.

// --- deprecated: hidden from the generated interface ---

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend CollectInnerAs with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend CollectInnerAs with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend CollectInnerAs with Eq::{equal}

///|
#deprecated("Use `FromJson::from_json` instead")
#doc(hidden)
pub extend CollectInnerAs with FromJson::{from_json}

///|
#deprecated("Use `ToJson::to_json` instead")
#doc(hidden)
pub extend CollectInnerAs with ToJson::{to_json}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend ConditionalLift with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend ConditionalLift with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend ConditionalLift with Eq::{equal}

///|
#deprecated("Use `FromJson::from_json` instead")
#doc(hidden)
pub extend ConditionalLift with FromJson::{from_json}

///|
#deprecated("Use `ToJson::to_json` instead")
#doc(hidden)
pub extend ConditionalLift with ToJson::{to_json}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend ExtractText with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend ExtractText with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend ExtractText with Eq::{equal}

///|
#deprecated("Use `FromJson::from_json` instead")
#doc(hidden)
pub extend ExtractText with FromJson::{from_json}

///|
#deprecated("Use `ToJson::to_json` instead")
#doc(hidden)
pub extend ExtractText with ToJson::{to_json}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend LanguageSpec with Debug::{to_repr}

///|
#deprecated("Use `FromJson::from_json` instead")
#doc(hidden)
pub extend LanguageSpec with FromJson::{from_json}

///|
#deprecated("Use `ToJson::to_json` instead")
#doc(hidden)
pub extend LanguageSpec with ToJson::{to_json}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend LiftSpec with Debug::{to_repr}

///|
#deprecated("Use `FromJson::from_json` instead")
#doc(hidden)
pub extend LiftSpec with FromJson::{from_json}

///|
#deprecated("Use `ToJson::to_json` instead")
#doc(hidden)
pub extend LiftSpec with ToJson::{to_json}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend LowerSpec with Debug::{to_repr}

///|
#deprecated("Use `FromJson::from_json` instead")
#doc(hidden)
pub extend LowerSpec with FromJson::{from_json}

///|
#deprecated("Use `ToJson::to_json` instead")
#doc(hidden)
pub extend LowerSpec with ToJson::{to_json}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend RegexReplace with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend RegexReplace with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend RegexReplace with Eq::{equal}

///|
#deprecated("Use `FromJson::from_json` instead")
#doc(hidden)
pub extend RegexReplace with FromJson::{from_json}

///|
#deprecated("Use `ToJson::to_json` instead")
#doc(hidden)
pub extend RegexReplace with ToJson::{to_json}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend StructuralRule with Debug::{to_repr}

///|
#deprecated("Use `FromJson::from_json` instead")
#doc(hidden)
pub extend StructuralRule with FromJson::{from_json}

///|
#deprecated("Use `ToJson::to_json` instead")
#doc(hidden)
pub extend StructuralRule with ToJson::{to_json}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend TextReplace with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend TextReplace with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend TextReplace with Eq::{equal}

///|
#deprecated("Use `FromJson::from_json` instead")
#doc(hidden)
pub extend TextReplace with FromJson::{from_json}

///|
#deprecated("Use `ToJson::to_json` instead")
#doc(hidden)
pub extend TextReplace with ToJson::{to_json}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend TextReplacePair with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend TextReplacePair with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend TextReplacePair with Eq::{equal}

///|
#deprecated("Use `FromJson::from_json` instead")
#doc(hidden)
pub extend TextReplacePair with FromJson::{from_json}

///|
#deprecated("Use `ToJson::to_json` instead")
#doc(hidden)
pub extend TextReplacePair with ToJson::{to_json}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend TranspileLimits with Debug::{to_repr}

///|
#deprecated("Use `FromJson::from_json` instead")
#doc(hidden)
pub extend TranspileLimits with FromJson::{from_json}

///|
#deprecated("Use `ToJson::to_json` instead")
#doc(hidden)
pub extend TranspileLimits with ToJson::{to_json}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend TypeWrap with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend TypeWrap with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend TypeWrap with Eq::{equal}

///|
#deprecated("Use `FromJson::from_json` instead")
#doc(hidden)
pub extend TypeWrap with FromJson::{from_json}

///|
#deprecated("Use `ToJson::to_json` instead")
#doc(hidden)
pub extend TypeWrap with ToJson::{to_json}
