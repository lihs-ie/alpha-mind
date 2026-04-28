{-# LANGUAGE OverloadedStrings #-}

module AuthInternalJwtSpec (spec) where

import Auth.InternalJwt
import Network.HTTP.Types (hAuthorization)
import Network.Wai.Internal (Request (..))
import Network.Wai.Test (defaultRequest)
import Test.Hspec (Spec, describe, it, shouldBe)

spec :: Spec
spec =
  describe "Auth.InternalJwt" $ do
    it "extracts bearer tokens" $
      extractBearerToken bearerRequest `shouldBe` Right "token-value"

    it "rejects missing Authorization headers" $
      extractBearerToken defaultRequest `shouldBe` Left TokenMissing

    it "rejects malformed Authorization headers" $
      extractBearerToken malformedRequest `shouldBe` Left (TokenMalformed "Bearer token is malformed")

    it "maps JWT errors to HTTP status codes" $ do
      jwtErrorToHttpStatus TokenMissing `shouldBe` 401
      jwtErrorToHttpStatus (TokenMalformed "bad") `shouldBe` 401
      jwtErrorToHttpStatus SignatureInvalid `shouldBe` 401
      jwtErrorToHttpStatus (AudienceMismatch "expected" "actual") `shouldBe` 403
      jwtErrorToHttpStatus (IssuerMismatch "issuer") `shouldBe` 403
      jwtErrorToHttpStatus (JwksFetchError "failed") `shouldBe` 500

bearerRequest :: Request
bearerRequest = defaultRequest{requestHeaders = [(hAuthorization, "Bearer token-value")]}

malformedRequest :: Request
malformedRequest = defaultRequest{requestHeaders = [(hAuthorization, "Basic token-value")]}
