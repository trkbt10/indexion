(ns task-manager.core
  "Task management system with basic CRUD operations."
  (:require [clojure.string :as str]))

(defn create-task
  "Create a new task with the given title and optional description.
   Returns the created task map."
  [title & {:keys [description priority] :or {description "" priority :normal}}]
  {:id (java.util.UUID/randomUUID)
   :title title
   :description description
   :priority priority
   :status :pending
   :created-at (java.time.Instant/now)})

(defn complete-task
  "Mark a task as completed."
  [task]
  (assoc task :status :completed))

(defn filter-by-status
  "Filter tasks by their status keyword."
  [tasks status]
  (filter #(= (:status %) status) tasks))
