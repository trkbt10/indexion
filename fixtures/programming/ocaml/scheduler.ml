(** Scheduling primitives built on top of the task store.

    This module exposes a priority queue, a retry policy record and a
    small object-oriented clock abstraction. *)

open Printf
open Task_store

module StringMap = Map.Make (String)

(** How urgently a task should run. *)
type priority =
  | Low  (** Run whenever there is spare capacity. *)
  | Normal
  | High  (** Run before anything else. *)

(** Retry behaviour attached to a scheduled task. *)
type retry_policy = {
  limit : int;  (** Maximum number of attempts. *)
  backoff : float;
  mutable attempts : int;
}

(** A slot is a millisecond offset from the epoch. *)
type slot = Slot of int

exception Overloaded of string

(** Converts a priority to its numeric weight. *)
let weight_of = function
  | Low -> 0
  | Normal -> 1
  | High -> 2

(** Orders tasks so that high priority names come first. *)
let schedule (tasks : (string * priority) list) : string list =
  let cmp (_, a) (_, b) = compare (weight_of b) (weight_of a) in
  List.map fst (List.stable_sort cmp tasks)

(** Computes the slot following [s], spaced by the policy backoff. *)
let next_slot policy (Slot s) =
  let step = int_of_float (policy.backoff *. 1000.0) in
  Slot (s + max 1 step)

(** Renders a policy as a human readable string.

    Exercises the string lexer: "a quote \" and a backslash \\ inside",
    plus a char literal '\n'. *)
let describe_policy p =
  sprintf "retry up to %d times, backoff %.2f" p.limit p.backoff

(** Groups names into buckets keyed by priority name. *)
let bucketize tasks =
  let insert acc (name, prio) =
    let key = match prio with Low -> "low" | Normal -> "normal" | High -> "high" in
    StringMap.add key name acc
  in
  List.fold_left insert StringMap.empty tasks

(** A clock reports the current time and can sleep. *)
class virtual clock = object
  (** Current time, in milliseconds. *)
  method virtual now : int

  (** Sleeps for the given number of milliseconds. *)
  method sleep_for ms = ms
end

(** Signature of a pluggable scheduling backend. *)
module type BACKEND = sig
  (** The backend's opaque handle. *)
  type t

  (** Creates a backend. *)
  val create : unit -> t

  (** Submits a named task. *)
  val submit : t -> string -> priority -> unit
end
