{- | Factory for constructing 'OrderRiskAssessment' from integration event payloads.

Must-20: single factory entry point; production code only — no test doubles.
-}
module Domain.RiskAssessment.Factory (
  OrdersProposedPayload (..),
  fromOrdersProposed,
) where

import Data.Text (Text)
import Data.Time (UTCTime)
import Data.ULID (ULID)
import Domain.RiskAssessment (Trace (..))
import Domain.RiskAssessment.Aggregate (
  CompliancePolicy (..),
  OrderProposal (..),
  OrderRiskAssessment,
  OrderRiskAssessmentIdentifier (..),
  RiskExposure (..),
  RiskLimits (..),
  Side (..),
  acceptOrderProposal,
 )
import Domain.RiskAssessment.Error (DomainError (..))

-- | Payload from an @orders.proposed@ integration event.
data OrdersProposedPayload = OrdersProposedPayload
  { identifier :: ULID
  -- ^ Event identifier, used as the order identifier.
  , symbol :: Text
  , side :: Text
  -- ^ @"BUY"@ or @"SELL"@.
  , qty :: Double
  , trace :: ULID
  }
  deriving stock (Eq, Show)

{- | Factory: construct an 'OrderRiskAssessment' from an @orders.proposed@ payload.

Returns 'DomainError' when the payload contains an invalid @side@ value.
-}
fromOrdersProposed ::
  OrdersProposedPayload ->
  -- | Kill switch state.
  Bool ->
  RiskLimits ->
  CompliancePolicy ->
  RiskExposure ->
  UTCTime ->
  Either DomainError OrderRiskAssessment
fromOrdersProposed payload killSwitchEnabled riskLimits compliancePolicy riskExposure now =
  case parseSide payload.side of
    Nothing ->
      Left (MissingRequiredFields ("invalid side: " <> payload.side))
    Just sideValue ->
      let assessmentIdentifier = OrderRiskAssessmentIdentifier payload.identifier
          traceValue = Trace payload.trace
          proposal =
            OrderProposal
              { identifier = assessmentIdentifier
              , symbol = payload.symbol
              , side = sideValue
              , qty = payload.qty
              }
       in Right
            ( acceptOrderProposal
                assessmentIdentifier
                proposal
                traceValue
                killSwitchEnabled
                riskLimits
                compliancePolicy
                riskExposure
                now
            )

parseSide :: Text -> Maybe Side
parseSide "BUY" = Just Buy
parseSide "SELL" = Just Sell
parseSide _ = Nothing
