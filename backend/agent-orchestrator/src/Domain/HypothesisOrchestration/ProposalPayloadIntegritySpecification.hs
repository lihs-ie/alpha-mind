module Domain.HypothesisOrchestration.ProposalPayloadIntegritySpecification (
  -- * Specification (Must-28)
  ProposalPayloadIntegritySpecification (..),
  isSatisfiedBy,
) where

import Domain.HypothesisOrchestration.Aggregate (HypothesisProposal, ProposalStatus (..))

-- ---------------------------------------------------------------------
-- Specification (Must-28)
-- ---------------------------------------------------------------------

{- | Must-28: ProposalPayloadIntegritySpecification — status=proposed 時の必須属性充足を検証。
isSatisfiedBy が True を返すとき、集約は Proposed 状態遷移の前提条件を満たす。
-}
data ProposalPayloadIntegritySpecification = ProposalPayloadIntegritySpecification
  deriving stock (Eq, Show)

{- | Must-28: status=proposed 状態時に必須属性がすべて存在するかを yes/no で返す。
- symbol が Just 非空
- instrumentType が Just
- title が Just 非空
- sourceEvidence が非空リスト
- skillVersion が Just 非空
- instructionProfileVersion が Just 非空
-}
isSatisfiedBy :: ProposalPayloadIntegritySpecification -> HypothesisProposal -> Bool
isSatisfiedBy _ proposal =
  case proposal.status of
    Proposed ->
      let symbolOk = case proposal.symbol of
            Just sym -> sym /= ""
            Nothing -> False
          titleOk = case proposal.title of
            Just ttl -> ttl /= ""
            Nothing -> False
          evidenceOk = not (null proposal.sourceEvidence)
          skillVersionOk = case proposal.skillVersion of
            Just ver -> ver /= ""
            Nothing -> False
          profileVersionOk = case proposal.instructionProfileVersion of
            Just ver -> ver /= ""
            Nothing -> False
       in symbolOk && titleOk && evidenceOk && skillVersionOk && profileVersionOk
    _ -> True
