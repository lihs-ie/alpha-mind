{-# LANGUAGE FunctionalDependencies #-}

module Domain.OrderExecution.Specification (
  Specification (..),
) where

{- | Specification pattern: each specification type encodes a business rule
that can be checked against a subject value.
-}
class Specification spec subject | spec -> subject where
  isSatisfiedBy :: spec -> subject -> Bool
