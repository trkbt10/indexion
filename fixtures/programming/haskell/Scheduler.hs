{-# LANGUAGE ScopedTypeVariables #-}

-- | Scheduling primitives for the task pipeline.
--
-- This module builds on "TaskStore" and adds priority ordering,
-- retry policies and a small typeclass for pluggable clocks.
module Data.Task.Scheduler
  ( Priority(..)
  , RetryPolicy(..)
  , Clock(..)
  , Slot
  , schedule
  , nextSlot
  , describePolicy
  ) where

import Data.List (sortOn)
import Data.Maybe (fromMaybe, mapMaybe)
import qualified Data.Map.Strict as Map
import Control.Monad.State (State, get, put)

-- | How urgently a task should run.
data Priority
  = Low
  | Normal
  | High
  deriving (Show, Eq, Ord)

-- | Retry behaviour attached to a scheduled task.
data RetryPolicy = RetryPolicy
  { retryLimit   :: Int
  , retryBackoff :: Double
  } deriving (Show, Eq)

-- | A slot is a millisecond offset from the epoch.
newtype Slot = Slot Int
  deriving (Show, Eq, Ord)

-- | Convenient alias for a priority-indexed bucket of names.
type Buckets = Map.Map Priority [String]

-- | Anything that can report the current time.
class Clock c where
  -- | Current time, in milliseconds.
  now :: c -> Int
  -- | Sleep for the given number of milliseconds.
  sleepFor :: c -> Int -> Int

-- | Orders tasks so that high priority names come first.
--
-- Ties keep their original relative order, because 'sortOn' is stable.
schedule :: [(String, Priority)] -> [String]
schedule = map fst . sortOn (negate . fromEnum . snd)

-- | Computes the slot following @s@, spaced by the policy backoff.
nextSlot :: RetryPolicy -> Slot -> Slot
nextSlot policy (Slot s) =
  let step = ceiling (retryBackoff policy * 1000.0)
  in Slot (s + max 1 step)

-- | Renders a policy as a human readable string.
--
-- The escape sequences below exercise the string lexer: "quote \" and
-- backslash \\ inside a literal", plus a char literal '\n'.
describePolicy :: RetryPolicy -> String
describePolicy p =
  "retry up to " ++ show (retryLimit p) ++ " times, backoff \"" ++ show (retryBackoff p) ++ "\"" ++ ['\n']

-- | Groups names into buckets keyed by priority.
bucketize :: [(String, Priority)] -> Buckets
bucketize = foldr insert Map.empty
  where
    insert (name, prio) acc = Map.insertWith (++) prio [name] acc

{- | A block-form Haddock comment attached to a helper.

   It spans several lines and contains a -- that must not end it.
-}
pendingNames :: Buckets -> [String]
pendingNames buckets = fromMaybe [] (Map.lookup High buckets)
