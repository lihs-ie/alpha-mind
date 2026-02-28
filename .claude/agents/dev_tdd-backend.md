---
name: dev_tdd-backend
description: TDD (Red-Green-Refactor) cycle for backend implementation
model: sonnet
---
```mermaid
flowchart TD
    be_sf_start([Start])
    be_sf_tdd_skill[[Skill: tdd-workflow]]
    be_sf_red[【TDD赤フェーズ】バックエンド — 失敗するテストを書く]
    be_sf_green[【TDD緑フェーズ】バックエンド — テストを通す最小...]
    be_sf_refactor[【TDDリファクタリング】バックエンド — コード整理]
    be_sf_end([End])

    be_sf_start --> be_sf_tdd_skill
    be_sf_tdd_skill --> be_sf_red
    be_sf_red --> be_sf_green
    be_sf_green --> be_sf_refactor
    be_sf_refactor --> be_sf_end
```

## Workflow Execution Guide

Follow the Mermaid flowchart above to execute the workflow. Each node type has specific execution methods as described below.

### Execution Methods by Node Type

- **Rectangle nodes**: Execute Sub-Agents using the Task tool
- **Diamond nodes (AskUserQuestion:...)**: Use the AskUserQuestion tool to prompt the user and branch based on their response
- **Diamond nodes (Branch/Switch:...)**: Automatically branch based on the results of previous processing (see details section)
- **Rectangle nodes (Prompt nodes)**: Execute the prompts described in the details section below

## Skill Nodes

#### be_sf_tdd_skill(tdd-workflow)

- **Prompt**: skill "tdd-workflow" load-skill-knowledge-into-context-only

### Prompt Node Details

#### be_sf_red(【TDD赤フェーズ】バックエンド — 失敗するテストを書く)

```
【TDD赤フェーズ】バックエンド — 失敗するテストを書く
```

#### be_sf_green(【TDD緑フェーズ】バックエンド — テストを通す最小...)

```
【TDD緑フェーズ】バックエンド — テストを通す最小限の実装
```

#### be_sf_refactor(【TDDリファクタリング】バックエンド — コード整理)

```
【TDDリファクタリング】バックエンド — コード整理
```
