///|
priv struct IndexSyncResult {
  candidates : Array[ReconcileCandidate]
  logical_reviews : Array[LogicalReviewTask]
  manifest : ReconcileManifest
  db : @vcdb.VectorDB
  reused_candidates : Int
  reused_logical_reviews : Int
}

///|
fn records_db_path(index_dir : String) -> String {
  index_dir + "/records.db"
}

///|
fn current_epoch_seconds() -> Int {
  (@env.now() / 1000UL).to_int()
}

///|
fn compute_review_state_hash(
  logical_reviews : Map[String, LogicalReviewEntry],
) -> String {
  let parts : Array[String] = []
  let keys : Array[String] = []
  for entry in logical_reviews {
    keys.push(entry.0)
  }
  let sorted_keys = sort_strings(keys)
  for key in sorted_keys {
    match logical_reviews.get(key) {
      Some(entry) => {
        parts.push(entry.review_key)
        parts.push(entry.digest)
        parts.push(entry.status)
        parts.push(
          match entry.verdict {
            Some(verdict) => verdict
            None => ""
          },
        )
        parts.push(entry.updated_at.to_string())
      }
      None => ()
    }
  }
  make_hash(parts)
}

///|
/// Allocate the next vector ID from the manifest counter.
pub fn ReconcileManifest::allocate_vector_id(
  self : ReconcileManifest,
) -> (ReconcileManifest, Int64) {
  let id = self.vector_id_counter
  (
    { ..self, updated_at: current_epoch_seconds(), vector_id_counter: id + 1L },
    id,
  )
}

///|
fn load_record_db(index_dir : String) -> @vcdb.VectorDB {
  let path = records_db_path(index_dir)
  if not(@fs.path_exists(path)) {
    return @vcdb.VectorDB::with_dim(1)
  }
  let bytes = @fs.read_file_to_bytes(path) catch {
    _ => return @vcdb.VectorDB::with_dim(1)
  }
  @vcdb.VectorDB::deserialize(bytes)
}

///|
fn save_record_db(index_dir : String, db : @vcdb.VectorDB) -> Unit {
  @config_paths.ensure_dir_recursive(index_dir)
  let path = records_db_path(index_dir)
  let bytes = db.serialize()
  @fs.write_bytes_to_file(path, bytes) catch {
    _ => ()
  }
}

///|
fn normalize_review_status(status : String) -> String {
  match lower_string(@common.trim_ascii_spaces(status)) {
    "accepted" | "approve" | "approved" => "accepted"
    "rejected" | "reject" => "rejected"
    "dismissed" => "dismissed"
    "off" | "disabled" => "disabled"
    _ => "pending"
  }
}

///|
fn timestamp_digest_part(info : TimestampInfo) -> String {
  let epoch = match info.epoch_seconds {
    Some(value) => value.to_string()
    None => ""
  }
  epoch + ":" + info.source + ":" + info.is_dirty.to_string()
}

///|
fn candidate_digest(candidate : ReconcileCandidate) -> String {
  let parts : Array[String] = [
    candidate.id,
    candidate.symbol_id,
    candidate.status,
    candidate.time_relation,
    candidate.mapping_confidence.to_string(),
    candidate.recommended_action,
    candidate.code_anchor.module_path,
    candidate.evidence.match_kind,
    candidate.evidence.reason,
    candidate.evidence.matched_terms.join("\u0001"),
    timestamp_digest_part(candidate.evidence.code_time),
    timestamp_digest_part(candidate.evidence.doc_time),
  ]
  match candidate.code_anchor.inline_doc {
    Some(doc) => parts.push(doc)
    None => parts.push("")
  }
  match candidate.doc_anchor {
    Some(anchor) => {
      parts.push(anchor.fragment_id)
      parts.push(anchor.path)
      parts.push(anchor.spec)
      parts.push(anchor.kind)
      parts.push(anchor.title)
      parts.push(anchor.preview)
    }
    None => {
      parts.push("")
      parts.push("")
      parts.push("")
      parts.push("")
      parts.push("")
      parts.push("")
    }
  }
  make_hash(parts)
}

///|
fn review_key_for_digest(digest : String) -> String {
  "review:" + digest
}

///|
fn candidate_record_attrs(candidate : ReconcileCandidate) -> @vcdb_core.Attrs {
  let attrs = @vcdb.empty_attrs()
  attrs.set("record_kind", @vcdb_core.AttrValue::String("candidate"))
  attrs.set("record_key", @vcdb_core.AttrValue::String(candidate.id))
  attrs.set("digest", @vcdb_core.AttrValue::String(candidate.mechanical_digest))
  attrs.set("symbol_id", @vcdb_core.AttrValue::String(candidate.symbol_id))
  attrs.set("status", @vcdb_core.AttrValue::String(candidate.status))
  attrs.set(
    "time_relation",
    @vcdb_core.AttrValue::String(candidate.time_relation),
  )
  attrs.set(
    "recommended_action",
    @vcdb_core.AttrValue::String(candidate.recommended_action),
  )
  attrs.set(
    "mapping_confidence",
    @vcdb_core.AttrValue::Int(candidate.mapping_confidence.to_int64()),
  )
  attrs.set(
    "logical_review_status",
    @vcdb_core.AttrValue::String(candidate.logical_review_status),
  )
  attrs.set(
    "needs_logical_review",
    @vcdb_core.AttrValue::Bool(candidate.needs_logical_review),
  )
  match candidate.logical_review_key {
    Some(value) =>
      attrs.set("logical_review_key", @vcdb_core.AttrValue::String(value))
    None => ()
  }
  attrs
}

///|
fn logical_review_attrs(entry : LogicalReviewEntry) -> @vcdb_core.Attrs {
  let attrs = @vcdb.empty_attrs()
  attrs.set("record_kind", @vcdb_core.AttrValue::String("logical_review"))
  attrs.set("record_key", @vcdb_core.AttrValue::String(entry.review_key))
  attrs.set("digest", @vcdb_core.AttrValue::String(entry.digest))
  attrs.set("candidate_id", @vcdb_core.AttrValue::String(entry.candidate_id))
  attrs.set("status", @vcdb_core.AttrValue::String(entry.status))
  attrs.set(
    "updated_at",
    @vcdb_core.AttrValue::Int(entry.updated_at.to_int64()),
  )
  match entry.verdict {
    Some(verdict) => attrs.set("verdict", @vcdb_core.AttrValue::String(verdict))
    None => ()
  }
  attrs
}

///|
fn upsert_db_record(
  db : @vcdb.VectorDB,
  vector_id : Int64,
  attrs : @vcdb_core.Attrs,
) -> Unit {
  ignore(db.upsert(@vcdb_core.VectorId::from_int64(vector_id), [1.0], attrs))
}

///|
fn ensure_record_slot(
  manifest : ReconcileManifest,
  record_key : String,
  record_kind : String,
) -> (ReconcileManifest, Int64) {
  match manifest.records.get(record_key) {
    Some(entry) => (manifest, entry.vector_id)
    None => {
      let (updated, vector_id) = manifest.allocate_vector_id()
      updated.records.set(record_key, {
        record_key,
        record_kind,
        digest: "",
        vector_id,
      })
      ({ ..updated, updated_at: current_epoch_seconds() }, vector_id)
    }
  }
}

///|
fn keep_record_keys(keys : Array[String]) -> Map[String, Bool] {
  let result : Map[String, Bool] = {}
  for key in keys {
    result.set(key, true)
  }
  result
}

///|
fn prune_index_state(
  manifest : ReconcileManifest,
  db : @vcdb.VectorDB,
  record_keys : Array[String],
  review_keys : Array[String],
  updated_at : Int,
) -> (ReconcileManifest, @vcdb.VectorDB) {
  let keep_records = keep_record_keys(record_keys)
  let stale_records : Array[String] = []
  for entry in manifest.records {
    if not(keep_records.contains(entry.0)) {
      stale_records.push(entry.0)
    }
  }
  for key in stale_records {
    match manifest.records.get(key) {
      Some(entry) =>
        ignore(db.remove(@vcdb_core.VectorId::from_int64(entry.vector_id)))
      None => ()
    }
    manifest.records.remove(key)
  }
  let keep_reviews = keep_record_keys(review_keys)
  let stale_reviews : Array[String] = []
  for entry in manifest.logical_reviews {
    if not(keep_reviews.contains(entry.0)) {
      stale_reviews.push(entry.0)
    }
  }
  for key in stale_reviews {
    manifest.logical_reviews.remove(key)
  }
  let review_state_hash = compute_review_state_hash(manifest.logical_reviews)
  ({ ..manifest, updated_at, review_state_hash }, db)
}

///|
fn load_review_decisions(path : String) -> Array[ReviewDecisionInput] {
  if path.length() == 0 {
    return []
  }
  let content = @fs.read_file_to_string(path) catch { _ => return [] }
  let json = @json.parse(content) catch { _ => return [] }
  let decisions : Array[ReviewDecisionInput] = @json.from_json(json) catch {
    _ => return []
  }
  decisions
}

///|
fn apply_review_decisions(
  manifest : ReconcileManifest,
  db : @vcdb.VectorDB,
  decisions : Array[ReviewDecisionInput],
  updated_at : Int,
) -> (ReconcileManifest, @vcdb.VectorDB) {
  for decision in decisions {
    match manifest.logical_reviews.get(decision.review_key) {
      Some(existing) => {
        let updated_entry = {
          ..existing,
          status: normalize_review_status(decision.status),
          verdict: decision.verdict,
          updated_at,
        }
        manifest.logical_reviews.set(decision.review_key, updated_entry)
        upsert_db_record(
          db,
          existing.vector_id,
          logical_review_attrs(updated_entry),
        )
      }
      None => ()
    }
  }
  let review_state_hash = compute_review_state_hash(manifest.logical_reviews)
  ({ ..manifest, updated_at, review_state_hash }, db)
}

///|
fn sync_candidates_with_index(
  candidates : Array[ReconcileCandidate],
  manifest : ReconcileManifest,
  db : @vcdb.VectorDB,
  logical_review_mode : String,
  updated_at : Int,
) -> IndexSyncResult {
  let mut working_manifest = manifest
  let enriched : Array[ReconcileCandidate] = []
  let logical_tasks : Array[LogicalReviewTask] = []
  let current_record_keys : Array[String] = []
  let current_review_keys : Array[String] = []
  let mut reused_candidates = 0
  let mut reused_logical_reviews = 0
  for candidate in candidates {
    let digest = candidate_digest(candidate)
    let candidate_reused = match working_manifest.records.get(candidate.id) {
      Some(entry) => entry.record_kind == "candidate" && entry.digest == digest
      None => false
    }
    if candidate_reused {
      reused_candidates += 1
    }
    let review_key = review_key_for_digest(digest)
    let existing_review = working_manifest.logical_reviews.get(review_key)
    let logical_enabled = logical_review_mode != "off"
    let logical_status = match existing_review {
      Some(entry) => entry.status
      None => if logical_enabled { "pending" } else { "disabled" }
    }
    let logical_reused = existing_review is Some(_)
    let logical_key = match existing_review {
      Some(_) => Some(review_key)
      None => if logical_enabled { Some(review_key) } else { None }
    }
    let needs_logical_review = logical_enabled && logical_status == "pending"
    let enriched_candidate = {
      ..candidate,
      mechanical_digest: digest,
      logical_review_key: logical_key,
      logical_review_status: logical_status,
      logical_review_reused: logical_reused,
      needs_logical_review,
    }
    let (manifest_after_candidate, candidate_vector_id) = ensure_record_slot(
      working_manifest,
      enriched_candidate.id,
      "candidate",
    )
    working_manifest = manifest_after_candidate
    working_manifest.records.set(enriched_candidate.id, {
      record_key: enriched_candidate.id,
      record_kind: "candidate",
      digest,
      vector_id: candidate_vector_id,
    })
    upsert_db_record(
      db,
      candidate_vector_id,
      candidate_record_attrs(enriched_candidate),
    )
    current_record_keys.push(enriched_candidate.id)

    match logical_key {
      Some(key) => {
        current_record_keys.push(key)
        current_review_keys.push(key)
        match existing_review {
          Some(entry) => {
            let persisted = { ..entry, updated_at, }
            working_manifest.logical_reviews.set(key, persisted)
            let (manifest_with_record, review_vector_id) = ensure_record_slot(
              working_manifest, key, "logical_review",
            )
            working_manifest = manifest_with_record
            working_manifest.records.set(key, {
              record_key: key,
              record_kind: "logical_review",
              digest: persisted.digest,
              vector_id: review_vector_id,
            })
            upsert_db_record(
              db,
              review_vector_id,
              logical_review_attrs(persisted),
            )
            if logical_enabled && persisted.status == "pending" {
              reused_logical_reviews += 1
              logical_tasks.push({
                review_key: key,
                candidate_id: enriched_candidate.id,
                digest: persisted.digest,
                status: persisted.status,
                reused: true,
                code_anchor: enriched_candidate.code_anchor,
                doc_anchor: enriched_candidate.doc_anchor,
                evidence: enriched_candidate.evidence,
                recommended_action: enriched_candidate.recommended_action,
              })
            }
          }
          None =>
            if logical_enabled {
              let (manifest_with_record, review_vector_id) = ensure_record_slot(
                working_manifest, key, "logical_review",
              )
              working_manifest = manifest_with_record
              let review_entry = {
                review_key: key,
                candidate_id: enriched_candidate.id,
                digest,
                status: "pending",
                verdict: None,
                updated_at,
                vector_id: review_vector_id,
              }
              working_manifest.logical_reviews.set(key, review_entry)
              working_manifest.records.set(key, {
                record_key: key,
                record_kind: "logical_review",
                digest,
                vector_id: review_vector_id,
              })
              upsert_db_record(
                db,
                review_vector_id,
                logical_review_attrs(review_entry),
              )
              logical_tasks.push({
                review_key: key,
                candidate_id: enriched_candidate.id,
                digest,
                status: "pending",
                reused: false,
                code_anchor: enriched_candidate.code_anchor,
                doc_anchor: enriched_candidate.doc_anchor,
                evidence: enriched_candidate.evidence,
                recommended_action: enriched_candidate.recommended_action,
              })
            }
        }
      }
      None => ()
    }

    enriched.push(enriched_candidate)
  }
  let (pruned_manifest, pruned_db) = prune_index_state(
    working_manifest, db, current_record_keys, current_review_keys, updated_at,
  )
  {
    candidates: enriched,
    logical_reviews: logical_tasks,
    manifest: pruned_manifest,
    db: pruned_db,
    reused_candidates,
    reused_logical_reviews,
  }
}
