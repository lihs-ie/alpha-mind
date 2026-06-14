module UseCase.HypothesisOrchestration.FailureKnowledgeRegistrar (
  -- * Use case function
  registerFailure,
) where

import Data.Text (Text)
import Data.Time (UTCTime)
import Domain.HypothesisOrchestration.Error (DomainError (..))
import Domain.HypothesisOrchestration.FailureKnowledge (
  FailureKnowledge (..),
  FailureKnowledgeIdentifier,
  FailureKnowledgeRepository (..),
 )
import Domain.HypothesisOrchestration.ReasonCode (ReasonCode (..))

{- | UC-AO: FailureKnowledge エンティティを生成して永続化する。

* @markdownSummary@ が空文字列の場合は
  @Left (MissingRequiredFields ["markdownSummary"] RequestValidationFailed)@ を返す。
* 正常時は FailureKnowledge を @FailureKnowledgeRepository.persist@ で永続化し、
  @Right ()@ を返す。

識別子は呼び出し元が生成・注入する（ULID の生成は UseCase の責務ではなく presentation/infra 層）。
-}
registerFailure ::
  (FailureKnowledgeRepository m) =>
  FailureKnowledgeIdentifier ->
  ReasonCode ->
  Text ->
  Text ->
  UTCTime ->
  m (Either DomainError ())
registerFailure knowledgeIdentifier reasonCodeValue summaryText markdownSummaryText recordedAtTime
  | markdownSummaryText == "" =
      pure (Left (MissingRequiredFields ["markdownSummary"] RequestValidationFailed))
  | otherwise = do
      let knowledge =
            FailureKnowledge
              { identifier = knowledgeIdentifier
              , reasonCode = reasonCodeValue
              , summary = summaryText
              , markdownSummary = markdownSummaryText
              , similarityHash = ""
              , recordedAt = recordedAtTime
              }
      persist knowledge
      pure (Right ())
