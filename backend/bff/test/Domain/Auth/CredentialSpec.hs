module Domain.Auth.CredentialSpec (spec) where

import Data.Either (isLeft, isRight)
import Domain.Auth.Credential (
  AuthCredential (..),
  EmailAddress (..),
  PlainPassword (..),
  mkAuthCredential,
 )
import Test.Hspec (Spec, describe, it, shouldBe, shouldSatisfy)

spec :: Spec
spec = describe "Domain.Auth.Credential" $ do
  describe "mkAuthCredential" $ do
    it "accepts valid email and password" $ do
      let result = mkAuthCredential "user@example.com" "secret123"
      result `shouldSatisfy` isRight

    it "rejects email without @" $ do
      let result = mkAuthCredential "notanemail" "secret123"
      result `shouldSatisfy` isLeft

    it "rejects empty password" $ do
      let result = mkAuthCredential "user@example.com" ""
      result `shouldSatisfy` isLeft

    it "stores the correct email" $ do
      let result = mkAuthCredential "admin@example.com" "pass"
      case result of
        Left errorValue -> fail ("Expected Right, got Left: " <> show errorValue)
        Right credential ->
          credential.email.unEmailAddress `shouldBe` "admin@example.com"

    it "stores the correct password" $ do
      let result = mkAuthCredential "user@example.com" "mypassword"
      case result of
        Left errorValue -> fail ("Expected Right, got Left: " <> show errorValue)
        Right credential ->
          credential.password.unPlainPassword `shouldBe` "mypassword"
