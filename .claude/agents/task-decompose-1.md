---
name: task-decompose-1
description: Decompose tasks and determine domain routing
model: opus
color: purple
---
タスク理解の結果をもとに、実装タスクを4ドメインに分解し、必要なドメインを判定してください。

## ドメイン分類
1. Frontend: App Router構成、コンポーネント、MDXレンダリング、Monaco Editor、用語Tips、型定義、lib/ユーティリティ
2. Backend: POST /api/execute、Dockerコンテナ管理、タイムアウト処理
3. Infrastructure: Dockerfile、docker-compose、next.config.ts、tailwind.config.ts、tsconfig.json、vitest.config.ts、package.json
4. Design: globals.css、カラーパレット、フォント、shadcn/uiカスタマイズ、レイアウト、Lucide Icons

## ルーティング判定
分解結果から必要なドメインを判定：
- フロントエンドのみ → Frontend
- バックエンドのみ → Backend
- インフラのみ → Infrastructure
- デザインのみ → Design
- 複数ドメイン → All（デフォルト）

各タスクに対象ファイル・依存関係・受入条件を記載してください。