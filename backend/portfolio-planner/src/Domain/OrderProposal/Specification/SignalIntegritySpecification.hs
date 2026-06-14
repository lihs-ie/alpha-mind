{- | SignalIntegritySpecification — MUST-17.
純粋関数。必須 4 フィールドが全て非空であることを確認する。
-}
module Domain.OrderProposal.Specification.SignalIntegritySpecification (
  isSatisfiedBy,
) where

import Data.Text (Text)
import Data.Text qualified as Text
import Domain.OrderProposal.ValueObjects (SignalSnapshot (..))

{- | MUST-17: signalVersion / modelVersion / featureVersion / storagePath のいずれかが
欠損（空文字）のとき False を返す。
純粋関数、外部 IO 非依存。
-}
isSatisfiedBy :: SignalSnapshot -> Bool
isSatisfiedBy snapshot =
  nonEmpty snapshot.signalVersion
    && nonEmpty snapshot.modelVersion
    && nonEmpty snapshot.featureVersion
    && nonEmpty snapshot.storagePath
 where
  nonEmpty :: Text -> Bool
  nonEmpty text = not (Text.null text)
