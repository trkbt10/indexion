///|
/// Symbol-kind filtering driven by the KGF `document_symbol_kinds` feature.
///
/// Language specs declare which symbol kinds belong in generated
/// documentation (e.g. functions and types but not parameters or fields).
/// This is the SoT for turning that feature into a lookup filter; callers
/// must not hardcode kind lists.

///|
/// Build a lowercased symbol-kind filter for a file set.
///
/// Detects the language from the first file whose extension matches a
/// spec's resolver sources, then reads that spec's
/// `document_symbol_kinds` feature. Returns `None` when no spec matches
/// or the matching spec does not declare the feature (callers should then
/// include all kinds).
pub fn document_symbol_kind_filter(
  files : Array[String],
  specs : Map[String, @kgf_types.KGFSpec],
) -> Map[String, Bool]? {
  for file in files {
    let ext = @config.extension(file)
    if ext.length() == 0 {
      continue
    }
    for entry in specs {
      let spec = entry.1
      for src_ext in spec.get_resolver().get_sources() {
        if src_ext == ext {
          match spec.get_feature(@kgf_types.FEATURE_DOCUMENT_SYMBOL_KINDS) {
            Some(kinds) => {
              let filter : Map[String, Bool] = Map([])
              for kind in kinds {
                filter.set(to_lower_str(kind), true)
              }
              return Some(filter)
            }
            None => return None
          }
        }
      }
    }
  }
  None
}
