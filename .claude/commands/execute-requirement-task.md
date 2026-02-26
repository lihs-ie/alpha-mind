---
description: execute-requirement-task
---
```mermaid
flowchart TD
    start_node_default([Start])
    prompt_input_requirement[対応する要件定義をユーザーに確認する]
    agent_pr_preparation[agent-pr-preparation]
    agent_implementation_clarification[agent-implementation-clarification]
    agent_rust_implementation[agent-rust-implementation]
    perf_gate_check{perf-gate:<br/>パフォーマンス影響あり?}
    perf_gate_run[/perf-gate スキル実行/]
    agent_rust_simplification[agent-rust-simplification]
    agent_rust_codex_review[agent-rust-codex-review]
    agent_shell_script_implementation[agent-shell-script-implementation]
    agent_shell_simplification[agent-shell-simplification]
    agent_shell_codex_review[agent-shell-codex-review]
    agent_documentation[agent-documentation]
    agent_documentation_codex_review[agent-documentation-codex-review]
    agent_final_review[agent-final-review]
    phase_boundary_confirm[/phase-boundary: ユーザー承認/]
    end_node_default([End])

    start_node_default --> prompt_input_requirement
    prompt_input_requirement --> agent_pr_preparation
    agent_pr_preparation --> agent_implementation_clarification
    agent_implementation_clarification --> agent_rust_implementation
    agent_implementation_clarification --> agent_shell_script_implementation
    agent_implementation_clarification --> agent_documentation
    agent_rust_implementation --> perf_gate_check
    perf_gate_check -->|はい| perf_gate_run
    perf_gate_check -->|いいえ| agent_rust_simplification
    perf_gate_run -->|PASS| agent_rust_simplification
    perf_gate_run -->|FAIL| agent_rust_implementation
    agent_rust_simplification --> agent_rust_codex_review
    agent_shell_script_implementation --> agent_shell_simplification
    agent_shell_simplification --> agent_shell_codex_review
    agent_documentation --> agent_documentation_codex_review
    agent_rust_codex_review --> phase_boundary_confirm
    agent_shell_codex_review --> phase_boundary_confirm
    agent_documentation_codex_review --> phase_boundary_confirm
    phase_boundary_confirm --> agent_final_review
    agent_final_review --> end_node_default
```

## Workflow Execution Guide

Follow the Mermaid flowchart above to execute the workflow. Each node type has specific execution methods as described below.

### Execution Methods by Node Type

- **Rectangle nodes**: Execute Sub-Agents using the Task tool
- **Diamond nodes (AskUserQuestion:...)**: Use the AskUserQuestion tool to prompt the user and branch based on their response
- **Diamond nodes (Branch/Switch:...)**: Automatically branch based on the results of previous processing (see details section)
- **Rectangle nodes (Prompt nodes)**: Execute the prompts described in the details section below

### Prompt Node Details

#### prompt_input_requirement(対応する要件定義をユーザーに確認する)

```
対応する要件定義をユーザーに確認する
```

### Skill Node Details

#### perf_gate_check(パフォーマンス影響あり?)

要件定義の内容から、パフォーマンスに影響する変更かどうかを判定する。以下の場合は「はい」:
- パフォーマンス最適化タスク
- データ構造の変更
- アルゴリズムの変更
- ホットパス上のコード変更

#### perf_gate_run(/perf-gate スキル実行)

`/perf-gate` スキルのワークフローに従ってベンチマーク比較を実行する。
- **PASS**: agent_rust_simplification に進む
- **FAIL**: agent_rust_implementation に戻り、リグレッションを修正

#### phase_boundary_confirm(/phase-boundary: ユーザー承認)

全実装フロー（Rust/Shell/ドキュメント）の完了後、最終レビュー前にユーザーに承認を求める:
```
実装フェーズ完了:
- Rust: [完了/スキップ]
- Shell: [完了/スキップ]
- ドキュメント: [完了/スキップ]

最終レビューフェーズを開始してよいですか？
```
