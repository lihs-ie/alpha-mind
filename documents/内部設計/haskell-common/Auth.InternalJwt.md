# Auth.InternalJwt 詳細設計

最終更新日: 2026-03-13

## 1. 目的

- Cloud Run 間の private HTTP 通信で使う Google 署名 ID token を検証する共通 middleware を提供する。
- 参照: `外部設計/security/認証認可設計.md` §6（サービス間認可）

## 2. 責務

- `Authorization: Bearer <token>` の抽出
- JWK 取得と署名検証
- `aud`, `iss`, `exp`, `iat` 検証
- 検証済み principal を request context（Vault）へ格納

## 3. 公開型・関数

```haskell
-- 設定
data InternalJwtConfig = InternalJwtConfig
  { expectedAudience :: Text          -- Cloud Run service URL
  , allowedIssuers   :: NonEmpty Text  -- Google OIDC issuers
  , jwksUrl          :: Text           -- JWKS endpoint
  , clockSkewSeconds :: Int            -- exp/iat 許容ずれ（秒）
  }

-- 検証済み principal（サービス間通信用）
data VerifiedPrincipal = VerifiedPrincipal
  { subject  :: Text       -- sub: service account email
  , issuer   :: Text       -- iss: token 発行者
  , audience :: Text       -- aud: 対象サービス URL
  , issuedAt :: UTCTime    -- iat
  , expiresAt :: UTCTime   -- exp
  }

-- エラー型
data JwtError
  = TokenMissing                   -- Authorization header 欠損
  | TokenMalformed Text            -- Bearer prefix 不正 / decode 失敗
  | SignatureInvalid               -- JWK による署名検証失敗
  | TokenExpired UTCTime UTCTime   -- exp < now（exp, now を保持）
  | AudienceMismatch Text Text     -- expected, actual
  | IssuerMismatch Text            -- actual issuer
  | JwksFetchError Text            -- JWKS endpoint 取得失敗
  deriving stock (Show, Eq)

-- HTTP ステータスへのマッピング
jwtErrorToHttpStatus :: JwtError -> Int
-- TokenMissing, TokenMalformed, SignatureInvalid, TokenExpired → 401
-- AudienceMismatch, IssuerMismatch → 403
-- JwksFetchError → 500

-- Vault key
verifiedPrincipalKey :: Vault.Key VerifiedPrincipal

-- 公開関数
internalJwtMiddleware :: InternalJwtConfig -> IORef JwksCache -> Middleware
verifyInternalJwt :: InternalJwtConfig -> IORef JwksCache -> Text -> IO (Either JwtError VerifiedPrincipal)
extractBearerToken :: Request -> Either JwtError Text
```

## 4. 入力

- `Authorization` header（`Bearer <token>` 形式）
- `InternalJwtConfig`

## 5. 出力

- 成功: `VerifiedPrincipal`（request vault に格納）
- 失敗:

| JwtError | HTTP Status | reasonCode | 説明 |
|---|---|---|---|
| `TokenMissing` | 401 | `AUTH_TOKEN_MISSING` | Authorization header なし |
| `TokenMalformed` | 401 | `AUTH_TOKEN_MALFORMED` | Bearer prefix 不正 / JWT decode 失敗 |
| `SignatureInvalid` | 401 | `AUTH_SIGNATURE_INVALID` | 署名検証失敗 |
| `TokenExpired` | 401 | `AUTH_TOKEN_EXPIRED` | 有効期限切れ |
| `AudienceMismatch` | 403 | `AUTH_AUDIENCE_MISMATCH` | aud 不一致 |
| `IssuerMismatch` | 403 | `AUTH_ISSUER_MISMATCH` | iss 不一致 |
| `JwksFetchError` | 500 | `INTERNAL_JWKS_FETCH_ERROR` | JWKS 取得失敗 |

レスポンス形式: RFC 9457 Problem Details（`認証認可設計.md` §7 準拠）

```json
{
  "type": "about:blank",
  "title": "Unauthorized",
  "status": 401,
  "detail": "Bearer token is missing",
  "reasonCode": "AUTH_TOKEN_MISSING",
  "retryable": false
}
```

## 6. 処理内容

1. `Authorization` header から `Bearer <token>` を抽出
2. JWK set をキャッシュ付きで取得（§6.1 参照）
3. `jose-jwt` で署名検証（RS256）
4. claims 検証（§6.2 参照）
5. `VerifiedPrincipal` を構築し request vault へ格納

### 6.1 JWK キャッシュ戦略

```haskell
data JwksCache = JwksCache
  { cachedAt :: UTCTime
  , jwkSet   :: JWKSet
  }
```

- **保持方法**: `IORef (Maybe JwksCache)`
- **TTL**: 10 分（`InternalJwtConfig` では設定不可。固定値）
- **cache hit**: `now - cachedAt < 600秒` なら既存の `jwkSet` を使用
- **cache miss**: JWKS endpoint に GET → 成功時にキャッシュ更新
- **並行リクエスト**: stampede protection なし（MVP では許容。リクエスト頻度が低いため）
- **取得失敗時**: 有効なキャッシュがあれば fallback 使用。キャッシュなしなら `JwksFetchError` を返す

### 6.2 claims 検証仕様

| claim | 検証ルール | 失敗時 |
|---|---|---|
| `aud` | `== expectedAudience` | `AudienceMismatch` |
| `iss` | `∈ allowedIssuers` | `IssuerMismatch` |
| `exp` | `exp + clockSkewSeconds >= now` | `TokenExpired` |
| `iat` | `iat - clockSkewSeconds <= now` | `TokenMalformed "issued in the future"` |

**clock skew**: デフォルト 60 秒（`認証認可設計.md` §4.2「許容時刻ずれ: 60秒」に準拠）

### 6.3 Vault による principal 受け渡し

```haskell
import Data.Vault.Lazy qualified as Vault

-- モジュールレベルで unsafePerformIO で生成（wai の標準パターン）
verifiedPrincipalKey :: Vault.Key VerifiedPrincipal
verifiedPrincipalKey = unsafePerformIO Vault.newKey
{-# NOINLINE verifiedPrincipalKey #-}

-- middleware 内で格納
let vault' = Vault.insert verifiedPrincipalKey principal (Network.Wai.vault req)
    req'   = req { Network.Wai.vault = vault' }

-- 下流ハンドラで取得
getPrincipal :: Request -> Maybe VerifiedPrincipal
getPrincipal req = Vault.lookup verifiedPrincipalKey (Network.Wai.vault req)
```

## 7. 外部リソース

- Google OIDC JWKS endpoint: `https://www.googleapis.com/oauth2/v3/certs`
- Google OIDC issuer（`allowedIssuers` に設定する値）:
  - `https://accounts.google.com`（正規）
  - `accounts.google.com`（互換。Google ID token が返す場合がある）
- `expectedAudience` には各 Cloud Run service の URL を設定する
  - 例: `https://svc-bff-xxxxx-an.a.run.app`
  - 環境変数 `INTERNAL_JWT_AUDIENCE` から取得する想定

## 8. 使用ライブラリ

| パッケージ | バージョン | 用途 |
|---|---|---|
| `jose-jwt` | `0.10.0` | JWT decode / JWK 署名検証 |
| `http-client` | `0.7.19` | JWKS endpoint への HTTP GET |
| `http-client-tls` | `0.3.6.4` | HTTPS 接続 |
| `wai` | `3.2.4` | Middleware / Request / Vault |
| `vault` | `0.3.1.5` | request context（principal 格納） |
| `aeson` | `2.2.3.0` | JWKS JSON パース |
| `http-types` | `0.12.4` | HTTP status codes |

### 8.1 import 例

```haskell
import Data.IORef (IORef, readIORef, writeIORef)
import Data.Text (Text)
import Data.Text.Encoding (decodeUtf8, encodeUtf8)
import Data.Time (UTCTime, getCurrentTime, diffUTCTime)
import Data.Vault.Lazy qualified as Vault
import Network.HTTP.Client (Manager, httpLbs, parseRequest, responseBody)
import Network.HTTP.Types (status401, status403, status500)
import Network.Wai (Middleware, Request, vault, requestHeaders)
import Jose.Jwt qualified as JWT
```

## 9. 実装ルール

- JWK cache TTL は 10 分（固定）
- `aud` / `iss` 不一致は `403`
- token 欠損 / 署名不正 / 有効期限切れは `401`
- JWKS 取得失敗は `500`（有効キャッシュがあれば fallback）
- エラーレスポンスは `application/problem+json`（RFC 9457）
- すべてのログに `trace`, `service` を含める（共通設計 §6 準拠）

## 10. テスト観点

| # | シナリオ | 期待結果 | 検証対象 |
|---|---------|---------|---------|
| 1 | Authorization header なし | 401 `AUTH_TOKEN_MISSING` | `extractBearerToken` |
| 2 | `Bearer` prefix なし（例: `Basic xxx`） | 401 `AUTH_TOKEN_MALFORMED` | `extractBearerToken` |
| 3 | 署名不正の JWT | 401 `AUTH_SIGNATURE_INVALID` | `verifyInternalJwt` |
| 4 | `exp` 切れの JWT | 401 `AUTH_TOKEN_EXPIRED` | claims 検証 |
| 5 | `iat` が未来の JWT | 401 `AUTH_TOKEN_MALFORMED` | claims 検証 |
| 6 | `aud` 不一致 | 403 `AUTH_AUDIENCE_MISMATCH` | claims 検証 |
| 7 | `iss` 不一致 | 403 `AUTH_ISSUER_MISMATCH` | claims 検証 |
| 8 | 有効な JWT | 200 + Vault に `VerifiedPrincipal` | middleware 全体 |
| 9 | JWKS 取得失敗（キャッシュあり） | 正常処理（fallback） | JWK キャッシュ |
| 10 | JWKS 取得失敗（キャッシュなし） | 500 `INTERNAL_JWKS_FETCH_ERROR` | JWK キャッシュ |

## 11. 実装ヒント

- 最初は `verifyInternalJwt` を pure に近い形で切り出し、middleware はその wrapper にする。
- JWKS キャッシュは `IORef (Maybe JwksCache)` で十分。最初から複雑な cache library は不要。
- token 抽出、JWK 取得、claims 検証を 3 関数に分けるとデバッグしやすい。

## 12. 実装ロードマップ

### Step 1. 型定義 + Bearer token 抽出

作成ファイル: `src/Auth/InternalJwt.hs`

```haskell
-- JwtError, VerifiedPrincipal, InternalJwtConfig を定義
-- extractBearerToken :: Request -> Either JwtError Text
```

テスト: header あり/なし/形式不正の 3 パターン

### Step 2. claims 検証（pure 関数）

```haskell
validateClaims :: InternalJwtConfig -> UTCTime -> JwtClaims -> Either JwtError VerifiedPrincipal
-- 内部で validateAudience, validateIssuer, validateExpiry, validateIssuedAt を呼ぶ
```

テスト: 各 claim の正常/異常パターン

### Step 3. JWK 取得 + キャッシュ

```haskell
fetchJwkSet :: Manager -> InternalJwtConfig -> IORef (Maybe JwksCache) -> IO (Either JwtError JwkSet)
```

テスト: cache hit / cache miss / fetch 失敗 + fallback

#### 実装ヒント

処理フローは以下の 3 段階:

1. **キャッシュ確認**: `readIORef cacheRef` で `Maybe JwksCache` を取得
2. **TTL 判定**: キャッシュが有効か（`now - cachedAt < 600秒`）を判定
3. **取得 or 再利用**: 無効/未キャッシュなら HTTP GET、有効ならそのまま返す

```haskell
fetchJwkSet :: Manager -> InternalJwtConfig -> IORef (Maybe JwksCache) -> IO (Either JwtError JwkSet)
fetchJwkSet manager config cacheRef = do
  now <- getCurrentTime
  cached <- readIORef cacheRef
  case cached of
    -- cache hit: TTL 内なら既存の jwkSet を返す
    Just cache
      | diffUTCTime now (cachedAt cache) < jwksCacheTTL ->
          pure (Right (jwkSet cache))
    -- cache miss or expired: JWKS endpoint に GET
    _ -> do
      result <- fetchFromEndpoint manager (jwksUrl config)
      case result of
        Right newJwkSet -> do
          -- 成功: キャッシュを更新して返す
          writeIORef cacheRef (Just (JwksCache now newJwkSet))
          pure (Right newJwkSet)
        Left err ->
          -- 失敗: 有効なキャッシュがあれば fallback、なければエラー
          case cached of
            Just fallbackCache -> pure (Right (jwkSet fallbackCache))
            Nothing -> pure (Left err)

-- TTL 定数（10 分 = 600 秒）
jwksCacheTTL :: NominalDiffTime
jwksCacheTTL = 600
```

#### HTTP GET 部分の補助関数

```haskell
fetchFromEndpoint :: Manager -> Text -> IO (Either JwtError JwkSet)
fetchFromEndpoint manager url = do
  -- 1. parseRequest で URL → Request を作成
  --    Text → String に変換が必要（Data.Text.unpack）
  -- 2. httpLbs manager request でレスポンス取得
  -- 3. responseBody を aeson の eitherDecode でパース
  --    JwkSet は aeson の FromJSON インスタンスを持つ
  -- 4. パース失敗 → Left (JwksFetchError reason)
  --    HTTP例外 → try で捕捉して Left (JwksFetchError reason)
```

#### 必要な import

```haskell
import Data.IORef (readIORef, writeIORef)
import Data.Time (getCurrentTime, diffUTCTime)
import Network.HTTP.Client (httpLbs, parseRequest, responseBody)
import Data.Aeson (eitherDecode)
import Control.Exception (try, SomeException)
```

#### ガード構文の補足

`Just cache | 条件 ->` はパターンマッチ内のガードで、
「`Just cache` にマッチ **かつ** 条件が `True`」のときだけこの分岐に入る。

### Step 4. `verifyInternalJwt` を組み立てる

- Step 1〜3 を合成
- `401` と `403` の原因を `JwtError` で区別できることを確認

```haskell
verifyInternalJwt :: InternalJwtConfig -> IORef (Maybe JwksCache) -> Manager -> Text -> IO (Either JwtError VerifiedPrincipal)
verifyInternalJwt config cacheRef manager token = do
  -- 1. JWK set をキャッシュ付きで取得
  jwksResult <- fetchJwkSet manager config cacheRef
  case jwksResult of
    Left err -> pure (Left err)
    Right jwkSet -> do
      -- 2. jose-jwt で署名検証（RS256）
      --    Jose.Jwt.decode を使用し JwkSet と token から JwtContent を取得
      --    署名検証失敗 → Left SignatureInvalid
      now <- getCurrentTime
      -- 3. デコード結果から claims を抽出
      --    Jose.Jwt.decodeClaims でヘッダーと claims をパース
      --    パース失敗 → Left (TokenMalformed reason)
      -- 4. validateClaims で claims 検証
      --    validateClaims config now claims
      --    失敗 → Left (対応する JwtError)
      -- 5. 成功 → Right VerifiedPrincipal
      undefined -- TODO: 実装
```

#### 実装ヒント

1. **IO と Either の合成**: `verifyInternalJwt` は `IO (Either ...)` を返す。
   `fetchJwkSet` は IO、`validateClaims` は純粋な Either を返すため、
   IO の中で Either の結果を `case` で分岐する必要がある。
   ネストが深くなる場合は `ExceptT JwtError IO` モナド変換子を使うと
   `do` 記法で平坦に書ける:

   ```haskell
   import Control.Monad.Trans.Except (ExceptT(..), runExceptT)

   verifyInternalJwt config cacheRef manager token = runExceptT $ do
     jwkSet <- ExceptT $ fetchJwkSet manager config cacheRef
     jwtContent <- ExceptT $ pure $ decodeAndVerify jwkSet token
     now <- liftIO getCurrentTime
     claims <- ExceptT $ pure $ extractClaims jwtContent
     ExceptT $ pure $ validateClaims config now claims
   ```

2. **jose-jwt の decode 関数**:
   - `Jose.Jwt.decode :: JWKSet -> Maybe JwtEncoding -> ByteString -> IO (Either JwtError JwtContent)`
   - 第2引数 `Just (JwsEncoding RS256)` で RS256 のみ許可
   - token は `Text` → `encodeUtf8` で `ByteString` に変換してから渡す

3. **JwtContent からの claims 抽出**:
   - `Jose.Jwt.decodeClaims :: ByteString -> Either JwtError (JwsHeader, JwtClaims)`
   - decode 成功後の payload を `decodeClaims` に渡して `JwtClaims` を取得

4. **エラーマッピング**:
   - jose-jwt のエラー型と自前の `JwtError` 型は異なるため変換関数が必要
   - `Jose.Jwt.JwtError` → `Shared.JWT.JWTError` への変換を用意する

### Step 5. middleware にする

```haskell
internalJwtMiddleware :: InternalJwtConfig -> IORef (Maybe JwksCache) -> Manager -> Middleware
internalJwtMiddleware config cacheRef manager app req sendResponse = do
  case extractBearerToken req of
    Left err -> sendResponse (errorResponse err)
    Right token -> do
      result <- verifyInternalJwt config cacheRef manager token
      case result of
        Left err -> sendResponse (errorResponse err)
        Right principal ->
          let req' = req { vault = Vault.insert verifiedPrincipalKey principal (vault req) }
          in app req' sendResponse
```

### 完了条件

- §10 のテスト観点 10 項目がすべて通過する
- `HttpServiceOptions.middlewareStack` に組み込んで既存 API に巻ける
- エラーレスポンスが Problem Details 形式で返る
