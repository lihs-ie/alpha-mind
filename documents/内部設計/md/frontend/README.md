# frontend モデリング設計一覧

最終更新日: 2026-03-01

## 1. 目的

- フロントエンド（`frontend-sol`）のドメインモデリング設計を集約する。
- 既存の詳細ドメインモデル設計（1〜12章構成）と同じフォーマットで管理する。

## 2. ドキュメント

- `内部設計/md/frontend/frontend-sol_ドメインモデル設計.md`
- `内部設計/md/frontend/hypothesis-lab-frontend_ドメインモデル設計.md`

## 3. 設計方針

- BFFを上流の公開言語（OpenAPI）として扱い、ACLで画面モデルへ投影する。
- オニオンアーキテクチャ（Domain/Application/Interface/Infrastructure）を厳守する。
- 識別子は `identifier` 命名を使用し、`Id` は使用しない。
