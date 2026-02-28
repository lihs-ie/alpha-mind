---
name: dev_tdd-infrastructure
description: TDD (Red-Green-Refactor) cycle for infrastructure implementation
model: sonnet
---
```mermaid
flowchart TD
    inf_sf_start([Start])
    inf_sf_tdd_skill[[Skill: tdd-workflow]]
    inf_sf_red[【TDD赤フェーズ】インフラ — 失敗するテストを書く]
    inf_sf_green[【TDD緑フェーズ】インフラ — テストを通す最小限の実装]
    inf_sf_refactor[【TDDリファクタリング】インフラ — コード整理]
    inf_sf_end([End])

    inf_sf_start --> inf_sf_tdd_skill
    inf_sf_tdd_skill --> inf_sf_red
    inf_sf_red --> inf_sf_green
    inf_sf_green --> inf_sf_refactor
    inf_sf_refactor --> inf_sf_end
```

## Workflow Execution Guide

Follow the Mermaid flowchart above to execute the workflow. Each node type has specific execution methods as described below.

### Execution Methods by Node Type

- **Rectangle nodes**: Execute Sub-Agents using the Task tool
- **Diamond nodes (AskUserQuestion:...)**: Use the AskUserQuestion tool to prompt the user and branch based on their response
- **Diamond nodes (Branch/Switch:...)**: Automatically branch based on the results of previous processing (see details section)
- **Rectangle nodes (Prompt nodes)**: Execute the prompts described in the details section below

## Skill Nodes

#### inf_sf_tdd_skill(tdd-workflow)

- **Prompt**: skill "tdd-workflow" load-skill-knowledge-into-context-only

### Prompt Node Details

#### inf_sf_red(【TDD赤フェーズ】インフラ — 失敗するテストを書く)

```
【TDD赤フェーズ】インフラ — 失敗するテストを書く
```

#### inf_sf_green(【TDD緑フェーズ】インフラ — テストを通す最小限の実装)

```
【TDD緑フェーズ】インフラ — テストを通す最小限の実装
```

#### inf_sf_refactor(【TDDリファクタリング】インフラ — コード整理)

```
【TDDリファクタリング】インフラ — コード整理
```
