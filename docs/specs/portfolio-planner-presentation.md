# Spec: portfolio-planner — Presentation Layer (Issue #40)

service: portfolio-planner
layer: presentation
issue: 40
risk: high-risk

## Must

- MUST-01: POST /pubsub/events エンドポイントが存在し、Pub/Sub push エンベロープを受信できる
- MUST-02: CloudEvent の payload から SignalSnapshot / StrategySnapshot / proposalSymbol / proposalSide を抽出し ProposeOrdersInput を構築できる
- MUST-03: proposeOrders ユースケースを presentation 層から呼び出せる（real entrypoint 経由で到達可能）
- MUST-04: 成功時に publishOrdersProposed を呼び出す
- MUST-05: 失敗時に publishOrdersProposalFailed を呼び出す
- MUST-06: 重複時（ProposeOrdersDuplicate）は 200 を返しイベントを発行しない
- MUST-07: スキーマ不正時（decodePubSubPush 失敗 / payload 抽出失敗）は 200 を返す（永続失敗 → 再配信不要）
- MUST-08: 一時障害時（ProposeOrdersFailed / PublishFailed）は 500 を返す（Pub/Sub が再配信）
- MUST-09: GET /healthz が 200 を返す（App.Bootstrap 経由）
- MUST-10: orderProposalIdentifier は presentation 層で ULID.getULID により生成し UseCase に渡す（UseCase は MonadIO 非依存を保つ）
- MUST-11: AppM は ReaderT AppEnv IO の newtype で、OrderProposalRepository / ProposalDispatchRepository / IdempotencyKeyRepository の 3 ポートを実装する
- MUST-12: buildAppEnv が必須環境変数（GCP_PROJECT_ID, PUBSUB_ORDERS_PROPOSED_TOPIC, PUBSUB_ORDERS_PROPOSAL_FAILED_TOPIC）を読み込む
- MUST-13: src/Main.hs が real entrypoint として buildAppEnv + runHttpService を呼び出す（スタブではない）
- MUST-14: processPubSubPushWith に injectable seam（usecase runner 引数）を持ち、test/ でのみテストダブルを使用する

## Should

- SHOULD-01: degradationFlag の文字列マッピング（NORMAL/WARN/BLOCK → DegradationFlag）が正確である
- SHOULD-02: proposalSide の文字列マッピング（BUY/SELL → Side）が正確である

## 受け入れ条件

- [ ] cabal build portfolio-planner が通る
- [ ] cabal test portfolio-planner で全テスト PASS
- [ ] hlint portfolio-planner/ で No hints
- [ ] fourmolu --mode check で差分なし
- [ ] src/Main.hs が buildAppEnv + runHttpService を使用している（スタブでない）
- [ ] src/ に mock/stub/fake/placeholder が存在しない

## Non-goal

- リスク承認判定（risk-guard のスコープ）
- 発注実行（execution のスコープ）
- 約定照合
- Firestore ポジション/設定取得（MVP スコープ外。UseCase が直接 ProposeOrdersInput で受け取る）

## Risk

level: high-risk
reason: real entrypoint DI 結線 + CI healthz smoke test が必要
