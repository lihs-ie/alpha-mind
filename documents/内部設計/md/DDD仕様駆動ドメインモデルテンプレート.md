# DDD仕様駆動ドメインモデル設計テンプレート

最終更新日: YYYY-MM-DD
対象Bounded Context: `<bounded-context>`
ドキュメント版: `v0.1.0`
作成者: `<name>`
レビュー状態: `draft/reviewed/approved`

## 1. 目的とスコープ

- 目的: `<このBounded Contextで解く業務課題>`
- スコープ内: `<対象ユースケース>`
- スコープ外: `<対象外ユースケース>`
- 関連要件: `<requirementsへの参照>`

## 2. 戦略設計（Strategic DDD）

### 2.1 Bounded Context定義

- Context名: `<name>`
- ミッション: `<この文脈で守る責務>`
- コア/支援/汎用サブドメイン区分: `<core/supporting/generic>`

### 2.2 Ubiquitous Language（用語集）

| 用語 | 定義 | 使用箇所 | 禁止/注意 |
|---|---|---|---|
| `<term>` | `<definition>` | `<code/doc/api>` | `<ambiguous term>` |

### 2.3 Context Map

| 相手Context | 関係 | インターフェース | 変換方針 |
|---|---|---|---|
| `<upstream/downstream>` | `Customer-Supplier / OHS+PL / ACL / Separate Ways` | `OpenAPI/AsyncAPI` | `<translation rules>` |


## 3. 仕様駆動（Specification-Driven）

### 3.1 ビジネスルール一覧（Rule）

| Rule ID | ルール | 優先度 | 集約境界内/外 |
|---|---|---|---|
| `RULE-001` | `<business rule>` | `must/should/could` | `inside/outside aggregate` |

### 3.2 受け入れ仕様（Gherkin）

```gherkin
Feature: <bounded-context feature>
  Rule: <business rule name>
    Example: <scenario name>
      Given <initial context>
      When <event or action>
      Then <observable outcome>
```

### 3.3 仕様トレーサビリティ

| Rule ID | Scenario | Aggregate | API/Event | Test ID |
|---|---|---|---|---|
| `RULE-001` | `SCN-001` | `<aggregate>` | `<openapi path / eventType>` | `TST-001` |

## 4. 戦術設計（Tactical DDD）

### 4.1 Aggregate設計

| Aggregate | Aggregate Root | 責務 | 一貫性境界（同一Tx） | 不変条件 |
|---|---|---|---|---|
| `<aggregate>` | `<root>` | `<responsibility>` | `<boundary>` | `<invariants>` |

#### Aggregate詳細: `<aggregate>`

- root: `<root>`
- 参照先集約: `<other aggregate>`（`identifier`参照のみ）
- 生成コマンド: `<command>`
- 更新コマンド: `<command>`
- 削除/無効化コマンド: `<command>`
- 不変条件:
1. `<invariant 1>`
2. `<invariant 2>`

#### 4.1.1 Aggregate Rootフィールド定義

| フィールド名 | 型 | 説明 | 保持数 |
|---|---|---|---|
| `identifier` | `<type>` | `<rootの識別子>` | `1` |
| `<field>` | `<type>` | `<description>` | `<cardinality: 1 / 0..1 / 1..n / 0..n / x..y>` |

#### 4.1.2 集約内要素の保持（Entity/Value Object）

| フィールド名 | 型 | 説明 | 保持数 |
|---|---|---|---|
| `<entities>` | `List<<Entity>>` | `<集約内エンティティ>` | `0..n` |
| `<valueObjects>` | `List<<ValueObject>>` | `<集約内値オブジェクト>` | `0..n` |
| `<singleValueObject>` | `<ValueObject>` | `<単一値オブジェクト>` | `0..1` |

### 4.2 Entity

| Entity | 識別子 | ライフサイクル | 主な振る舞い |
|---|---|---|---|
| `<entity>` | `identifier` | `<state model>` | `<methods>` |

#### Entity詳細: `<entity>`

| フィールド名 | 型 | 説明 | 保持数 |
|---|---|---|---|
| `identifier` | `<type>` | `<entityの識別子>` | `1` |
| `<field>` | `<type>` | `<description>` | `<cardinality: 1 / 0..1 / 1..n / 0..n / x..y>` |

### 4.3 Value Object

| Value Object | 属性 | 等価性 | 不変性 |
|---|---|---|---|
| `<vo>` | `<attributes>` | `<value equality>` | `immutable` |

#### Value Object詳細: `<vo>`

| フィールド名 | 型 | 説明 | 保持数 |
|---|---|---|---|
| `<field>` | `<type>` | `<description>` | `<cardinality: 1 / 0..1 / 1..n / 0..n / x..y>` |

### 4.4 Domain Service / Application Service

| Service | 種別 | 責務 | 置いてはいけないもの |
|---|---|---|---|
| `<name>` | `domain/application` | `<responsibility>` | `domain rule in application service` |

### 4.5 Repository / Factory / Specification

| パターン | 名称 | 用途 | I/F定義 |
|---|---|---|---|
| Repository | `<name>` | `<aggregate永続化>` | `<interface signature>` |
| Factory | `<name>` | `<複雑生成>` | `<factory method>` |
| Specification | `<name>` | `<合成可能ルール>` | `isSatisfiedBy(candidate)` |

#### 4.5.1 interface signature

| 役割 | 命名規則 | 用途 |
| - | - | - |
| 永続化 | Persist | 集約・エンティティを永続化する |
| 削除 | Terminate | 集約・エンティティを削除する |
| Identifierによる単一取得 | Find | 識別子を指定して集約・エンティティを単体で取得する |
| Identifier以外の要素による単一取得 | FindBy{XXX} | 識別子以外の要素を指定して集約・エンティティを単体で取得する |
| 複数取得 | Search | 検索条件（Criteria）を受け取り条件に合致する集約・エンティティを全て取得する |


## 5. 状態遷移と不変条件

### 5.1 状態遷移

| 現在状態 | コマンド | 次状態 | ガード条件 | 失敗時reasonCode |
|---|---|---|---|---|
| `<state>` | `<command>` | `<state>` | `<guard>` | `<reasonCode>` |

### 5.2 不変条件テーブル

| Invariant ID | 対象Aggregate | 条件 | 破壊時の扱い |
|---|---|---|---|
| `INV-001` | `<aggregate>` | `<must hold>` | `<reject/compensate>` |

## 6. ドメインイベント設計

### 6.1 Domain Event（境界内）

| eventType | 発行主体 | 発行タイミング | payload | 冪等キー |
|---|---|---|---|---|
| `<domain.event.occurred>` | `<aggregate root>` | `<after state change>` | `<fields>` | `identifier` |

### 6.2 Integration Event（境界外）

| eventType | 公開先 | 契約 | 整合性 | リトライ/DLQ |
|---|---|---|---|---|
| `<integration.event.occurred>` | `<other context>` | `AsyncAPI` | `eventual consistency` | `<policy>` |

## 7. API/イベント契約マッピング

| ユースケース | Command/Query | OpenAPI | AsyncAPI | 備考 |
|---|---|---|---|---|
| `<usecase>` | `<command or query>` | `<path>` | `<eventType>` | `<note>` |

## 8. 永続化と整合性

| 保存対象 | オーナー | 保存先 | トランザクション境界 | 監査項目 |
|---|---|---|---|---|
| `<aggregate>` | `<bounded context>` | `<db/collection>` | `<single aggregate tx>` | `trace, identifier, user` |

- 他集約更新は同一Txで行わない
- 集約間整合はイベントで実現する

## 9. テスト設計（仕様と同型）

| Test ID | 種別 | 対応Rule | 観測点 |
|---|---|---|---|
| `TST-001` | `acceptance/invariant/domain event` | `RULE-001` | `<observable outcome>` |

- 受け入れ: Gherkinの `Given/When/Then`
- ドメイン: 不変条件・状態遷移・イベント発行
- 契約: OpenAPI/AsyncAPI lint + schema検証

## 10. 実装規約（このプロジェクト向け）

- ドメイン設計（Aggregate/Entity/Value Object/Domain Event）にも `Identifier` 命名規約を適用する
- `Id` は使わず `identifier` を使う
- 当該関心ごとの識別子は `identifier`
- 他関心ごとの識別子は `{entity}`（例: `user`）
- 集約外参照はID参照のみ（オブジェクト参照禁止）

## 11. レビュー観点

- Bounded Context境界は明確か
- 用語がコード/API/ドキュメントで一致しているか
- 不変条件がAggregate Rootで担保されているか
- Application Serviceに業務ルールが漏れていないか
- 集約間更新が単一トランザクションに混入していないか
- Rule→Scenario→Model→Contract→Testのトレースが切れていないか

## 12. 参照（調査ソース）

- Martin Fowler: DDD Aggregate  
  https://martinfowler.com/bliki/DDD_Aggregate.html
- Martin Fowler: Evans Classification  
  https://martinfowler.com/bliki/EvansClassification.html
- Microsoft Learn: Use DDD tactical patterns  
  https://learn.microsoft.com/en-us/dotnet/architecture/microservices/microservice-ddd-cqrs-patterns/ddd-oriented-microservice
- Microsoft Learn: Design a DDD-oriented microservice domain model  
  https://learn.microsoft.com/en-us/dotnet/architecture/microservices/microservice-ddd-cqrs-patterns/microservice-domain-model
- Microsoft Learn: Domain events design and implementation  
  https://learn.microsoft.com/en-us/dotnet/architecture/microservices/microservice-ddd-cqrs-patterns/domain-events-design-implementation
- Cucumber docs: Gherkin reference  
  https://cucumber.io/docs/gherkin/reference
