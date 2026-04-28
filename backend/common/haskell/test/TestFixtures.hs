{-# LANGUAGE OverloadedStrings #-}

module TestFixtures (
  sampleIdentifier,
  sampleTrace,
  sampleTime,
)
where

import Data.Time (UTCTime (..), fromGregorian, secondsToDiffTime)
import Data.ULID (ULID)

sampleIdentifier :: ULID
sampleIdentifier = read "01ARZ3NDEKTSV4RRFFQ69G5FAV"

sampleTrace :: ULID
sampleTrace = read "01BRZ3NDEKTSV4RRFFQ69G5FAV"

sampleTime :: UTCTime
sampleTime = UTCTime (fromGregorian 2026 3 7) (secondsToDiffTime 45296)
