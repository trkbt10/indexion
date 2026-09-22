// Explicit method promotion for trait impls (MoonBit warning 79,
// `implicit_impl_as_method`). Methods under "promoted" are called with dot
// syntax somewhere in this project; the rest are kept only as deprecated shims
// for the old implicit promotion and can be removed once it is gone.

// --- promoted: kept as regular methods (blessed public API) ---

///|
pub extend VocabularyReport with ToJson::{to_json}

// --- deprecated: hidden from the generated interface ---

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend VocabularyConfig with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend VocabularyConfig with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend VocabularyConfig with Eq::{equal}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend VocabularyFileSummary with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend VocabularyFileSummary with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend VocabularyFileSummary with Eq::{equal}

///|
#deprecated("Use `FromJson::from_json` instead")
#doc(hidden)
pub extend VocabularyFileSummary with FromJson::{from_json}

///|
#deprecated("Use `ToJson::to_json` instead")
#doc(hidden)
pub extend VocabularyFileSummary with ToJson::{to_json}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend VocabularyIssueAssessment with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend VocabularyIssueAssessment with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend VocabularyIssueAssessment with Eq::{equal}

///|
#deprecated("Use `FromJson::from_json` instead")
#doc(hidden)
pub extend VocabularyIssueAssessment with FromJson::{from_json}

///|
#deprecated("Use `ToJson::to_json` instead")
#doc(hidden)
pub extend VocabularyIssueAssessment with ToJson::{to_json}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend VocabularyReport with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend VocabularyReport with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend VocabularyReport with Eq::{equal}

///|
#deprecated("Use `FromJson::from_json` instead")
#doc(hidden)
pub extend VocabularyReport with FromJson::{from_json}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend VocabularyTerm with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend VocabularyTerm with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend VocabularyTerm with Eq::{equal}

///|
#deprecated("Use `FromJson::from_json` instead")
#doc(hidden)
pub extend VocabularyTerm with FromJson::{from_json}

///|
#deprecated("Use `ToJson::to_json` instead")
#doc(hidden)
pub extend VocabularyTerm with ToJson::{to_json}
